import CoreImage
import simd
import XCTest

/// Shared setup for the expression lens tests: one synthetic person, a clock, and a way to pose their face.
class ExpressionLensTestCase: XCTestCase {
    let h = LensHarness()
    let scene = SyntheticScene(center: CGPoint(x: 640, y: 400))
    lazy var base: LensInput = h.input(scene)
    lazy var plain: Bitmap = h.bitmap(base.composed)

    /// The scene's face with some of its signals changed.
    func face(_ edit: (inout FaceState) -> Void = { _ in }) -> FaceState {
        var f = scene.face()
        edit(&f)
        return f
    }

    /// Feeds a lens frames of one face (or none) and keeps the clock running between calls.
    final class Player {
        let lens: Lens
        let base: LensInput
        var clock = 0.0
        var last: CIImage

        init(_ lens: Lens, base: LensInput) {
            self.lens = lens
            self.base = base
            last = base.composed
        }

        @discardableResult
        func play(_ face: FaceState?, seconds: Double, dt: Double = 1.0 / 30) -> CIImage {
            for _ in 0..<max(1, Int((seconds / dt).rounded())) {
                clock += dt
                last = lens.render(LensInput(time: clock, dt: dt, rect: base.rect, camera: base.camera, matte: base.matte, background: base.background,
                                             composed: base.composed, matteGrid: base.matteGrid, face: face, services: base.services))
            }
            return last
        }
    }

    func player(_ lens: Lens, background: Bool = true, scene other: SyntheticScene? = nil) -> Player {
        Player(lens, base: other.map { h.input($0, background: background) } ?? (background ? base : h.input(scene, background: false)))
    }

    func bits(_ image: CIImage) -> Bitmap { h.bitmap(image) }

    /// How many pixels in `rect` satisfy a test.
    func count(_ bitmap: Bitmap, in rect: CGRect, where test: (RGB) -> Bool) -> Int {
        var n = 0
        for x in Int(max(0, rect.minX))..<Int(min(Double(bitmap.width), rect.maxX)) {
            for y in Int(max(0, rect.minY))..<Int(min(Double(bitmap.height), rect.maxY)) where test(bitmap.pixel(x, y)) { n += 1 }
        }
        return n
    }

    /// The four corners of the picture, far from a face in the middle.
    var corners: [CGRect] {
        [CGRect(x: 0, y: 0, width: 200, height: 120), CGRect(x: 1080, y: 0, width: 200, height: 120),
         CGRect(x: 0, y: 600, width: 200, height: 120), CGRect(x: 1080, y: 600, width: 200, height: 120)]
    }

    func assertCornersUntouched(_ out: Bitmap, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        for corner in corners {
            XCTAssertLessThanOrEqual(out.change(from: plain, in: corner), 4, "\(message): nothing out in the corners", file: file, line: line)
        }
    }

    func nobody(_ at: LensInput) -> LensInput {
        LensInput(time: 0, dt: 1.0 / 30, rect: at.rect, camera: at.camera, matte: at.matte, background: at.background,
                  composed: at.composed, matteGrid: nil, face: nil, services: at.services)
    }
}

// MARK: - The whole set

final class ExpressionCatalogTests: ExpressionLensTestCase {
    func testEveryEntryIsSetUpAndRendersWithAndWithoutAFace() {
        let entries = ExpressionFaces.all
        XCTAssertEqual(entries.count, 28, "eleven from round one and seventeen more")
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count, "ids are unique")
        for info in entries {
            XCTAssertEqual(info.category, .faces, info.name)
            XCTAssertTrue(info.needsFace, info.name)
            XCTAssertFalse(info.needsHands, info.name)
            XCTAssertFalse(info.blurb.isEmpty, info.name)
            XCTAssertEqual(info.glyph.count, 1, "\(info.name): one emoji")
            XCTAssertEqual(info.id, info.id.lowercased())

            let lens = info.make()
            XCTAssertTrue(lens.needs.contains(.face), info.name)
            let p = Player(lens, base: base)
            let out = p.play(face { $0.smile = 1; $0.browRaise = 1; $0.mouthOpen = 0.8 }, seconds: 0.5)
            XCTAssertEqual(out.extent, base.rect, "\(info.name) covers the picture")

            let lonely = info.make()
            let empty = bits(lonely.render(nobody(base)))
            XCTAssertEqual(empty.change(from: plain, in: base.rect), 0, "\(info.name): nothing is drawn when there is no face")
            XCTAssertEqual(lonely.status?.title, "Looking for your face…", info.name)
            XCTAssertNotNil(lens.status?.detail, "\(info.name): the status shows the readings while a face is there")
        }
    }

    func testEffectsFinishWhenTheFaceIsLost() {
        for info in ExpressionFaces.all {
            let p = Player(info.make(), base: base)
            p.play(face { $0.smile = 1; $0.browRaise = 1; $0.mouthOpen = 0.8 }, seconds: 1.5)
            let out = bits(p.play(nil, seconds: 4))
            XCTAssertEqual(out.change(from: plain, in: base.rect), 0, "\(info.name): everything has gone four seconds after the face does")
        }
    }

    func testAHugeFrameTimeAndRestartAreHarmless() {
        for info in ExpressionFaces.all {
            let lens = info.make()
            let p = Player(lens, base: base)
            for dt in [5.0, 0.0001, 1.0] {
                let out = p.play(face { $0.smile = 1; $0.browRaise = 1; $0.mouthOpen = 1; $0.blink = 1 }, seconds: dt * 3, dt: dt)
                XCTAssertEqual(out.extent, base.rect, "\(info.name) with dt \(dt)")
            }
            lens.restart()
            XCTAssertEqual(p.play(face(), seconds: 0.2).extent, base.rect, "\(info.name) after a restart")
        }
    }

    func testEveryLensDrawsInsideTheFrameForAFarFaceAndATiltedOne() {
        let far = SyntheticScene(center: CGPoint(x: 900, y: 300), scale: 0.4)
        var tilted = SyntheticScene(center: CGPoint(x: 400, y: 360)); tilted.roll = 0.6
        for (name, s) in [("far", far), ("tilted", tilted)] {
            let frame = h.input(s)
            let still = bits(frame.composed)
            for info in ExpressionFaces.all {
                var f = s.face(); f.smile = 1; f.browRaise = 1; f.mouthOpen = 0.9
                let p = Player(info.make(), base: frame)
                let out = bits(p.play(f, seconds: 1.5))
                XCTAssertEqual(p.last.extent, frame.rect)
                // The face is somewhere inside the frame, so something happened there.
                let io = f.interocular
                let near = CGRect(x: f.eyeCenter.x - io * 3, y: f.eyeCenter.y - io * 3, width: io * 6, height: io * 6)
                XCTAssertGreaterThan(out.change(from: still, in: near), 0, "\(info.name) (\(name) face) changes the picture near the face")
                Output.save(p.last, as: "expr-\(info.id)-\(name).png")
            }
        }
    }
}

// MARK: - Shared kit

final class ExpressionKitTests: XCTestCase {
    func testALatchNeedsMoreToSwitchOnThanToStayOn() {
        var latch = ExprLatch()
        XCTAssertFalse(latch.update(0.4, on: 0.5, off: 0.3))
        XCTAssertTrue(latch.update(0.6, on: 0.5, off: 0.3))
        XCTAssertTrue(latch.update(0.35, on: 0.5, off: 0.3), "a dip that stays above the lower bar keeps it on")
        XCTAssertFalse(latch.update(0.25, on: 0.5, off: 0.3))
        XCTAssertFalse(latch.update(0.45, on: 0.5, off: 0.3), "and a half-hearted rise doesn't turn it back on")
        latch.update(0.9, on: 0.5, off: 0.3)
        latch.reset()
        XCTAssertFalse(latch.isOn)
    }

    func testFaceSpaceFollowsTheFace() {
        var scene = SyntheticScene(center: CGPoint(x: 500, y: 300), scale: 1)
        var f = scene.face()
        XCTAssertEqual(f.exprPoint(0, 0).x, f.eyeCenter.x, accuracy: 0.001)
        XCTAssertEqual(f.exprPoint(1, 0).x - f.eyeCenter.x, f.interocular, accuracy: 0.001, "one unit along the eyes is one eye spacing")
        XCTAssertGreaterThan(f.exprPoint(0, 1).y, f.eyeCenter.y, "up the face is up the picture")
        XCTAssertLessThan(f.exprFaceCenter.y, f.eyeCenter.y, "the middle of the face is below the eyes")
        scene.roll = .pi / 2
        f = scene.face()
        XCTAssertEqual(f.exprPoint(0, 1).x, f.eyeCenter.x - f.interocular, accuracy: 0.01, "turned a quarter, up the face is across the picture")
        XCTAssertEqual(f.exprPoint(0, 1).y, f.eyeCenter.y, accuracy: 0.001)
        XCTAssertEqual(SyntheticScene(center: .zero, scale: 0.05).face().exprScale, 0.3, "a tiny face still gets visible sprites")
    }

    func testShapesFitTheirBoxAndSpritesDraw() {
        for (name, path) in [("heart", ExprShapes.heart()), ("star", ExprShapes.roundedStar(outer: 0.9, inner: 0.46, rounding: 0.13)),
                             ("sparkle", ExprShapes.sparkle()), ("drop", ExprShapes.teardrop()), ("cloud", ExprShapes.cloud())] {
            let box = path.boundingBox
            XCTAssertGreaterThanOrEqual(box.minX, -1.02, name); XCTAssertLessThanOrEqual(box.maxX, 1.02, name)
            XCTAssertGreaterThanOrEqual(box.minY, -1.02, name); XCTAssertLessThanOrEqual(box.maxY, 1.02, name)
            XCTAssertGreaterThan(box.width, 0.8, name)
        }
        let sprites: [(String, CGImage?)] = [("heart", ExprSprites.heart(variant: 0)), ("pink heart", ExprSprites.heart(variant: 1)), ("star", ExprSprites.star()),
                                             ("twinkle", ExprSprites.twinkle(variant: 2)), ("tear", ExprSprites.tear()), ("calm cloud", ExprSprites.cloud(stormy: false)),
                                             ("storm cloud", ExprSprites.cloud(stormy: true)), ("leaf", ExprSprites.leaf())]
        for (name, image) in sprites { XCTAssertNotNil(image, name) }
        XCTAssertTrue(ExprSprites.heart(variant: 7) === ExprSprites.heart(variant: 1), "sprites are made once and kept")
    }

    func testEmojiAreTrimmedToThePictureItself() throws {
        let image = try XCTUnwrap(ExprEmoji.image("🙂"))
        XCTAssertEqual(Double(image.width) / Double(image.height), 1, accuracy: 0.06, "a round face in a square box")
        XCTAssertGreaterThan(image.width, 200)
    }

    func testWarpOnlyTouchesTheRegionItIsGiven() {
        let h = LensHarness()
        let frame = h.input()
        let plain = h.bitmap(frame.composed)
        let region = CGRect(x: 540, y: 300, width: 200, height: 200)
        let out = h.bitmap(ExprWarp.apply(to: frame.composed, in: region, bounds: frame.rect) {
            ExprWarp.bump($0, center: CGPoint(x: 640, y: 400), radius: 100, scale: 0.8)
        })
        XCTAssertGreaterThan(out.change(from: plain, in: region), 30)
        XCTAssertLessThanOrEqual(out.change(from: plain, in: CGRect(x: 0, y: 0, width: 520, height: 720)), 4)
        XCTAssertLessThanOrEqual(out.change(from: plain, in: CGRect(x: 760, y: 0, width: 520, height: 720)), 4)
        XCTAssertLessThanOrEqual(out.change(from: plain, in: CGRect(x: 0, y: 0, width: 1280, height: 280)), 4)
        XCTAssertEqual(ExprWarp.union(of: [(CGPoint(x: 10, y: 10), 5), (CGPoint(x: 30, y: 40), 10)]), CGRect(x: 5, y: 5, width: 35, height: 45))
        // A region off the picture is ignored rather than breaking anything.
        XCTAssertEqual(ExprWarp.apply(to: frame.composed, in: CGRect(x: 5000, y: 5000, width: 10, height: 10), bounds: frame.rect) { $0 }.extent, frame.rect)
    }
}

// MARK: - Heart Eyes

final class ExpressionHeartEyesTests: ExpressionLensTestCase {
    func testHeartsSitInTheEyesAndNothingStreamsWhileYouDontSmile() {
        let lens = ExprHeartEyesLens()
        let p = Player(lens, base: base)
        let f = face()
        let out = bits(p.play(f, seconds: 1))
        Output.save(p.last, as: "expr-heart-eyes-idle.png")
        for eye in [f.leftEye, f.rightEye] {
            XCTAssertGreaterThan(out.change(from: plain, in: CGRect(x: eye.x - 20, y: eye.y - 15, width: 40, height: 30)), 150, "a heart over each eye")
            let p0 = out.pixel(Int(eye.x), Int(eye.y))
            XCTAssertGreaterThan(p0.r, p0.g + 60, "and it is red, got \(p0)")
        }
        XCTAssertEqual(lens.heartCount, 0)
        XCTAssertFalse(lens.isStreaming)
        assertCornersUntouched(out, "idle hearts")
    }

    func testTheHeartsThrob() {
        let p = player(ExprHeartEyesLens())
        let f = face()
        var sizes: Set<Int> = []
        for _ in 0..<30 {
            let out = bits(p.play(f, seconds: 1.0 / 30))
            sizes.insert(count(out, in: CGRect(x: f.leftEye.x - 50, y: f.leftEye.y - 50, width: 100, height: 100)) { $0.r > 200 && $0.g < 110 && $0.b < 140 })
        }
        XCTAssertGreaterThan(sizes.count, 8, "the heart is a different size from frame to frame")
    }

    func testOnlyASmileMakesHeartsFloatUp() {
        for (name, edit) in [("smile", { (f: inout FaceState) in f.smile = 1 }), ("mouth", { $0.mouthOpen = 1 }), ("brows", { $0.browRaise = 1 }), ("blink", { $0.blink = 1 })] as [(String, (inout FaceState) -> Void)] {
            let lens = ExprHeartEyesLens()
            let p = Player(lens, base: base)
            let out = bits(p.play(face(edit), seconds: 2))
            if name == "smile" {
                XCTAssertGreaterThan(lens.heartCount, 8, "a smile sends hearts up")
                XCTAssertTrue(lens.isStreaming)
                let above = CGRect(x: 440, y: 520, width: 400, height: 200)
                XCTAssertGreaterThan(out.change(from: plain, in: above), 120, "they float above the head")
                assertCornersUntouched(out, "the heart stream")
                Output.save(p.last, as: "expr-heart-eyes-smile.png")
            } else {
                XCTAssertEqual(lens.heartCount, 0, "\(name) alone makes no stream")
                XCTAssertFalse(lens.isStreaming)
            }
        }
    }

    func testAWobblySmileDoesNotStutterTheStream() {
        let lens = ExprHeartEyesLens()
        let p = Player(lens, base: base)
        p.play(face { $0.smile = 0.4 }, seconds: 0.5)
        XCTAssertFalse(lens.isStreaming, "not enough to start")
        p.play(face { $0.smile = 0.9 }, seconds: 0.2)
        XCTAssertTrue(lens.isStreaming)
        for i in 0..<30 { p.play(face { $0.smile = i % 2 == 0 ? 0.55 : 0.35 }, seconds: 1.0 / 30) }
        XCTAssertTrue(lens.isStreaming, "flickering between 35% and 55% keeps it going")
        p.play(face { $0.smile = 0.1 }, seconds: 0.2)
        XCTAssertFalse(lens.isStreaming)
        p.play(face { $0.smile = 0 }, seconds: 3)
        XCTAssertEqual(lens.heartCount, 0, "the last hearts float away")
    }

    func testHeartsStayNearAFarFace() {
        let far = SyntheticScene(center: CGPoint(x: 900, y: 300), scale: 0.4)
        let frame = h.input(far)
        let still = bits(frame.composed)
        let p = Player(ExprHeartEyesLens(), base: frame)
        var f = far.face(); f.smile = 1
        let out = bits(p.play(f, seconds: 3))
        let io = f.interocular
        let near = CGRect(x: f.eyeCenter.x - io * 4, y: f.eyeCenter.y - io * 3, width: io * 8, height: io * 7)
        XCTAssertGreaterThan(out.change(from: still, in: near), 100)
        XCTAssertEqual(out.change(from: still, in: CGRect(x: 0, y: 0, width: 600, height: 720)), 0, "a small face makes small hearts nowhere near the other side")
        Output.save(p.last, as: "expr-heart-eyes-far.png")
    }
}

// MARK: - Star Eyes

final class ExpressionStarEyesTests: ExpressionLensTestCase {
    func testStarsTwinkleInTheEyes() {
        let p = player(ExprStarEyesLens())
        let f = face()
        let first = bits(p.play(f, seconds: 1))
        for eye in [f.leftEye, f.rightEye] {
            XCTAssertGreaterThan(first.change(from: plain, in: CGRect(x: eye.x - 20, y: eye.y - 15, width: 40, height: 30)), 150)
            let c = first.pixel(Int(eye.x), Int(eye.y))
            XCTAssertGreaterThan(c.r, 200, "gold, got \(c)"); XCTAssertGreaterThan(c.g, 150); XCTAssertLessThan(c.b, 170)
        }
        let later = bits(p.play(f, seconds: 0.3))
        XCTAssertGreaterThan(later.change(from: first, in: CGRect(x: f.leftEye.x - 60, y: f.leftEye.y - 60, width: 120, height: 120)), 40, "it keeps twinkling")
        Output.save(p.last, as: "expr-star-eyes-idle.png")
    }

    func testRaisedBrowsSetOffOneBurstPerRaise() {
        let lens = ExprStarEyesLens()
        let p = Player(lens, base: base)
        p.play(face(), seconds: 0.5)
        XCTAssertEqual(lens.burstCount, 0)
        let out = bits(p.play(face { $0.browRaise = 1 }, seconds: 0.2))
        XCTAssertEqual(lens.burstCount, 1)
        XCTAssertGreaterThan(lens.sparkleCount, 20, "a burst of sparkles")
        let f = face()
        XCTAssertGreaterThan(out.change(from: plain, in: CGRect(x: f.leftEye.x - 150, y: f.browCenter.y - 20, width: 300, height: 140)), 150, "around the brows")
        Output.save(p.last, as: "expr-star-eyes-burst.png")
        p.play(face { $0.browRaise = 1 }, seconds: 2)
        XCTAssertEqual(lens.burstCount, 1, "holding them up doesn't burst again")
        XCTAssertTrue(lens.isRaised)
        p.play(face(), seconds: 1)
        XCTAssertFalse(lens.isRaised)
        p.play(face { $0.browRaise = 1 }, seconds: 0.2)
        XCTAssertEqual(lens.burstCount, 2, "lower and raise again for another")
    }

    func testBurstsIgnoreEverythingButTheBrows() {
        for (name, edit) in [("smile", { (f: inout FaceState) in f.smile = 1 }), ("mouth", { $0.mouthOpen = 1 }), ("blink", { $0.blink = 1 }), ("half raise", { $0.browRaise = 0.45 })] as [(String, (inout FaceState) -> Void)] {
            let lens = ExprStarEyesLens()
            let p = Player(lens, base: base)
            p.play(face(edit), seconds: 1.5)
            XCTAssertEqual(lens.burstCount, 0, name)
            XCTAssertEqual(lens.sparkleCount, 0, name)
        }
    }

    func testBurstsDoNotRetriggerFromABrowFlutter() {
        let lens = ExprStarEyesLens()
        let p = Player(lens, base: base)
        p.play(face { $0.browRaise = 0.9 }, seconds: 0.2)
        for i in 0..<45 { p.play(face { $0.browRaise = i % 2 == 0 ? 0.7 : 0.4 }, seconds: 1.0 / 30) }
        XCTAssertEqual(lens.burstCount, 1, "wobbling between 40% and 70% is still one raise")
    }

    func testSparklesStayNearTheFace() {
        let p = player(ExprStarEyesLens())
        var out = bits(p.play(face { $0.browRaise = 1 }, seconds: 0.1))
        assertCornersUntouched(out, "the burst")
        out = bits(p.play(face { $0.browRaise = 1 }, seconds: 0.6))
        assertCornersUntouched(out, "the burst a moment later")
    }
}

// MARK: - Happy Tears

final class ExpressionHappyTearsTests: ExpressionLensTestCase {
    func testABroadSmileSquirtsTearsThatFallAndSplash() {
        let lens = ExprHappyTearsLens()
        let p = Player(lens, base: base)
        let f = face { $0.smile = 1 }
        p.play(f, seconds: 0.25)
        XCTAssertTrue(lens.isCrying)
        XCTAssertGreaterThan(lens.dropCount, 2)
        let early = bits(p.last)
        // Drops arc outward past the sides of the head.
        XCTAssertGreaterThan(early.change(from: plain, in: CGRect(x: 700, y: 330, width: 200, height: 170)), 100, "squirting out to the side")
        Output.save(p.last, as: "expr-happy-tears-early.png")
        p.play(f, seconds: 2)
        XCTAssertGreaterThan(lens.splashCount, 3, "they hit the shoulders and splash")
        let late = bits(p.last)
        XCTAssertGreaterThan(late.change(from: plain, in: CGRect(x: 740, y: 100, width: 400, height: 220)), 80, "tears have fallen well below the eyes")
        assertCornersUntouched(late, "the tears")
        Output.save(p.last, as: "expr-happy-tears-late.png")
    }

    func testOnlyABroadSmileMakesTears() {
        for (name, edit) in [("half smile", { (f: inout FaceState) in f.smile = 0.5 }), ("mouth", { $0.mouthOpen = 1 }), ("brows", { $0.browRaise = 1 }), ("blink", { $0.blink = 1 })] as [(String, (inout FaceState) -> Void)] {
            let lens = ExprHappyTearsLens()
            let p = Player(lens, base: base)
            let out = bits(p.play(face(edit), seconds: 2))
            XCTAssertFalse(lens.isCrying, name)
            XCTAssertEqual(lens.dropCount, 0, name)
            XCTAssertEqual(out.change(from: plain, in: base.rect), 0, "\(name): the picture is untouched")
        }
    }

    func testTearsNeedAFirmSmileToStartAndASlackerOneToKeepGoing() {
        let lens = ExprHappyTearsLens()
        let p = Player(lens, base: base)
        p.play(face { $0.smile = 0.6 }, seconds: 0.5)
        XCTAssertFalse(lens.isCrying)
        p.play(face { $0.smile = 0.85 }, seconds: 0.3)
        XCTAssertTrue(lens.isCrying)
        p.play(face { $0.smile = 0.55 }, seconds: 0.5)
        XCTAssertTrue(lens.isCrying, "a dip to 55% doesn't stop them")
        p.play(face { $0.smile = 0.2 }, seconds: 0.2)
        XCTAssertFalse(lens.isCrying)
        p.play(face { $0.smile = 0 }, seconds: 4)
        XCTAssertEqual(lens.dropCount, 0)
        XCTAssertEqual(bits(p.last).change(from: plain, in: base.rect), 0, "all dried up")
    }

    func testDropsFallStraightDownWhenTheHeadIsTilted() {
        var tilted = SyntheticScene(center: CGPoint(x: 640, y: 400)); tilted.roll = 0.5
        let frame = h.input(tilted)
        let p = Player(ExprHappyTearsLens(), base: frame)
        var f = tilted.face(); f.smile = 1
        p.play(f, seconds: 2)
        Output.save(p.last, as: "expr-happy-tears-tilted.png")
        let out = bits(p.last)
        let still = bits(frame.composed)
        XCTAssertGreaterThan(out.change(from: still, in: CGRect(x: 380, y: 100, width: 520, height: 220)), 80, "gravity points down the picture, not down the face")
    }
}

// MARK: - Storm Cloud

final class ExpressionStormCloudTests: ExpressionLensTestCase {
    func testACalmCloudSitsAboveTheHeadAndDoesNothingElse() {
        let lens = ExprStormCloudLens()
        let p = Player(lens, base: base)
        let out = bits(p.play(face(), seconds: 1.5))
        let f = face()
        XCTAssertGreaterThan(out.change(from: plain, in: CGRect(x: 560, y: f.eyeCenter.y + 150, width: 160, height: 120)), 100, "a cloud overhead")
        XCTAssertEqual(out.change(from: plain, in: CGRect(x: 540, y: 250, width: 200, height: 170)), 0, "and nothing on the face")
        XCTAssertFalse(lens.isStormy)
        XCTAssertEqual(lens.rainCount, 0)
        XCTAssertEqual(lens.stormLevel, 0, accuracy: 0.001)
        Output.save(p.last, as: "expr-storm-calm.png")
    }

    func testRaisedBrowsBringRainAndLightningOnTheFace() {
        let lens = ExprStormCloudLens()
        let p = Player(lens, base: base)
        var flash = 0.0, struck = false
        let f = face { $0.browRaise = 1 }
        var sawRain = false
        for _ in 0..<90 {
            let out = bits(p.play(f, seconds: 1.0 / 30))
            flash = max(flash, lens.flashLevel)
            if lens.flashLevel > 0.9 && !struck {
                struck = true
                Output.save(p.last, as: "expr-storm-lightning.png")
                XCTAssertGreaterThan(out.change(from: plain, in: CGRect(x: 540, y: 250, width: 200, height: 170)), 200, "lightning lights up the face")
                assertCornersUntouched(out, "the flash")
            }
            if lens.rainCount > 20 { sawRain = true }
        }
        XCTAssertTrue(lens.isStormy)
        XCTAssertTrue(sawRain, "it rains")
        XCTAssertGreaterThanOrEqual(lens.boltCount, 1, "within three seconds there is lightning")
        XCTAssertGreaterThan(flash, 0.9)
        XCTAssertGreaterThan(lens.stormLevel, 0.95, "the cloud is fully dark")
        let rain = bits(p.last)
        XCTAssertGreaterThan(rain.change(from: plain, in: CGRect(x: 540, y: 250, width: 200, height: 200)), 60, "rain over the face")
        XCTAssertGreaterThan(rain.change(from: plain, in: CGRect(x: 540, y: 120, width: 200, height: 100)), 40, "and below it")
        assertCornersUntouched(rain, "the rain")
        Output.save(p.last, as: "expr-storm-rain.png")
    }

    func testTheStormIgnoresEverythingButTheBrows() {
        for (name, edit) in [("smile", { (f: inout FaceState) in f.smile = 1 }), ("mouth", { $0.mouthOpen = 1 }), ("blink", { $0.blink = 1 }), ("slight raise", { $0.browRaise = 0.45 })] as [(String, (inout FaceState) -> Void)] {
            let lens = ExprStormCloudLens()
            let p = Player(lens, base: base)
            p.play(face(edit), seconds: 3)
            XCTAssertFalse(lens.isStormy, name)
            XCTAssertEqual(lens.rainCount, 0, name)
            XCTAssertEqual(lens.boltCount, 0, name)
        }
    }

    func testTheStormBlowsOverWhenYouRelax() {
        let lens = ExprStormCloudLens()
        let p = Player(lens, base: base)
        p.play(face { $0.browRaise = 0.9 }, seconds: 0.5)
        XCTAssertTrue(lens.isStormy)
        p.play(face { $0.browRaise = 0.45 }, seconds: 0.5)
        XCTAssertTrue(lens.isStormy, "half a raise keeps it going")
        p.play(face(), seconds: 1.5)
        XCTAssertFalse(lens.isStormy)
        XCTAssertEqual(lens.rainCount, 0)
        XCTAssertLessThan(lens.stormLevel, 0.05)
        XCTAssertEqual(lens.flashLevel, 0, accuracy: 0.001)
    }

    func testTheCloudFollowsAFarAndATiltedHead() {
        var tilted = SyntheticScene(center: CGPoint(x: 400, y: 330)); tilted.roll = 0.35
        let frame = h.input(tilted)
        let still = bits(frame.composed)
        let p = Player(ExprStormCloudLens(), base: frame)
        var f = tilted.face(); f.browRaise = 1
        let out = bits(p.play(f, seconds: 1.5))
        XCTAssertGreaterThan(out.change(from: still, in: CGRect(x: 200, y: 500, width: 400, height: 220)), 100, "a cloud over where the head is now")
        XCTAssertEqual(out.change(from: still, in: CGRect(x: 900, y: 0, width: 380, height: 720)), 0, "and nothing on the other side")
        Output.save(p.last, as: "expr-storm-tilted.png")
    }
}

// MARK: - Emoji Mask

final class ExpressionEmojiMaskTests: ExpressionLensTestCase {
    func testTheExpressionPicksTheEmoji() {
        typealias Mood = ExprEmojiMaskLens.Mood
        let cases: [(String, (inout FaceState) -> Void, Mood)] = [
            ("neutral", { _ in }, .neutral), ("smile", { $0.smile = 1 }, .smile), ("mouth open", { $0.mouthOpen = 1 }, .surprised),
            ("brows", { $0.browRaise = 1 }, .astonished), ("blink", { $0.blink = 1 }, .sleepy), ("laugh", { $0.smile = 1; $0.mouthOpen = 0.9 }, .laugh),
            ("kiss", { $0.mouthWidth = 0.45 * $0.interocular }, .kiss),
        ]
        for (name, edit, expected) in cases {
            XCTAssertEqual(ExprEmojiMaskLens.mood(for: face(edit), current: .neutral), expected, name)
        }
        XCTAssertEqual(Set(Mood.allCases.map(\.emoji)).count, Mood.allCases.count, "every expression has its own emoji")
    }

    func testAnExpressionNeedsLessToStayThanToStart() {
        typealias Mood = ExprEmojiMaskLens.Mood
        XCTAssertEqual(ExprEmojiMaskLens.mood(for: face { $0.smile = 0.4 }, current: .neutral), .neutral)
        XCTAssertEqual(ExprEmojiMaskLens.mood(for: face { $0.smile = 0.4 }, current: .smile), .smile)
        XCTAssertEqual(ExprEmojiMaskLens.mood(for: face { $0.mouthOpen = 0.35 }, current: .neutral), .neutral)
        XCTAssertEqual(ExprEmojiMaskLens.mood(for: face { $0.mouthOpen = 0.35 }, current: .surprised), .surprised)
        XCTAssertEqual(ExprEmojiMaskLens.mood(for: face { $0.browRaise = 0.45 }, current: .astonished), .astonished)
    }

    func testTheMaskFollowsYourExpressionAfterAMomentAndPops() {
        let lens = ExprEmojiMaskLens()
        let p = Player(lens, base: base)
        p.play(face(), seconds: 1)
        XCTAssertEqual(lens.shown, .neutral)
        p.play(face { $0.smile = 1 }, seconds: 1.0 / 30)
        XCTAssertEqual(lens.shown, .neutral, "one frame of a smile isn't enough")
        p.play(face { $0.smile = 1 }, seconds: 0.3)
        XCTAssertEqual(lens.shown, .smile)
        p.play(face { $0.mouthOpen = 1 }, seconds: 0.4)
        XCTAssertEqual(lens.shown, .surprised)
        p.play(face(), seconds: 0.4)
        XCTAssertEqual(lens.shown, .neutral)

        XCTAssertLessThan(ExprEmojiMaskLens.pop(0), 0.75, "starts small")
        XCTAssertGreaterThan((0..<40).map { ExprEmojiMaskLens.pop(Double($0) / 100) }.max() ?? 0, 1.03, "overshoots")
        XCTAssertEqual(ExprEmojiMaskLens.pop(1), 1, accuracy: 0.01, "and settles")
    }

    func testABlinkIsNotAnExpression() {
        let lens = ExprEmojiMaskLens()
        let p = Player(lens, base: base)
        p.play(face(), seconds: 1)
        p.play(face { $0.blink = 1 }, seconds: 0.13)
        p.play(face(), seconds: 0.3)
        XCTAssertEqual(lens.shown, .neutral, "a natural blink goes by without the emoji changing")
        p.play(face { $0.blink = 1 }, seconds: 0.5)
        XCTAssertEqual(lens.shown, .sleepy, "but closing your eyes for a while does")
    }

    func testAFlickerOfTheTrackerDoesNotFlickerTheEmoji() {
        let lens = ExprEmojiMaskLens()
        let p = Player(lens, base: base)
        p.play(face(), seconds: 1)
        for i in 0..<30 { p.play(face { $0.smile = i % 2 == 0 ? 1 : 0 }, seconds: 1.0 / 30) }
        XCTAssertEqual(lens.shown, .neutral, "alternating frames never settle on anything")
    }

    func testTheMaskCoversTheFaceTiltsWithItAndLeavesTheRoomAlone() throws {
        let lens = ExprEmojiMaskLens()
        let p = Player(lens, base: base)
        let f = face()
        let out = bits(p.play(f, seconds: 1))
        Output.save(p.last, as: "expr-emoji-mask.png")
        func yellow(_ c: RGB) -> Bool { c.r > 200 && c.g > 110 && c.b < 120 }
        for spot in [f.exprPoint(0, 0.2), f.exprPoint(-0.7, -0.9), f.exprPoint(0.7, -0.9), f.exprPoint(0, -1.5)] {
            XCTAssertTrue(yellow(out.pixel(Int(spot.x), Int(spot.y))), "the emoji covers \(spot): \(out.pixel(Int(spot.x), Int(spot.y)))")
        }
        XCTAssertEqual(out.change(from: plain, in: CGRect(x: 0, y: 0, width: 400, height: 720)), 0)
        XCTAssertEqual(out.change(from: plain, in: CGRect(x: 880, y: 0, width: 400, height: 720)), 0)

        var tilted = SyntheticScene(center: CGPoint(x: 640, y: 400)); tilted.roll = 0.5
        let tiltedFrame = h.input(tilted)
        let q = Player(ExprEmojiMaskLens(), base: tiltedFrame)
        let t = bits(q.play(tilted.face(), seconds: 1))
        Output.save(q.last, as: "expr-emoji-mask-tilted.png")
        let tf = tilted.face()
        XCTAssertTrue(yellow(t.pixel(Int(tf.exprPoint(0.9, -1.2).x), Int(tf.exprPoint(0.9, -1.2).y))), "the mask turns with the head")
        XCTAssertGreaterThan(t.change(from: out, in: CGRect(x: 500, y: 250, width: 280, height: 300)), 100, "its eyes and mouth are in other places")
    }

    func testTheMaskIsSizedToAFarFace() {
        let far = SyntheticScene(center: CGPoint(x: 300, y: 250), scale: 0.4)
        let frame = h.input(far)
        let still = bits(frame.composed)
        let p = Player(ExprEmojiMaskLens(), base: frame)
        let f = far.face()
        let out = bits(p.play(f, seconds: 1))
        XCTAssertEqual(out.change(from: still, in: CGRect(x: 500, y: 0, width: 780, height: 720)), 0)
        let size = f.interocular * ExprEmojiMaskLens.sizeInEyeSpacings
        let box = CGRect(x: f.exprPoint(0, -0.35).x - size, y: f.exprPoint(0, -0.35).y - size, width: size * 2, height: size * 2)
        XCTAssertEqual(out.change(from: still, in: CGRect(x: 0, y: 0, width: 1280, height: box.minY - 5)), 0, "nothing below the small mask")
        Output.save(p.last, as: "expr-emoji-mask-far.png")
    }
}

// MARK: - Pinocchio

final class ExpressionPinocchioTests: ExpressionLensTestCase {
    func testTheNoseGrowsWhileYourMouthIsOpenAndShrinksWhenShut() {
        let lens = ExprPinocchioLens()
        let p = Player(lens, base: base)
        p.play(face(), seconds: 0.5)
        XCTAssertEqual(lens.noseLength, 0)
        XCTAssertEqual(lens.leafCount, 0)
        let lie = face { $0.mouthOpen = 0.8 }
        p.play(lie, seconds: 1)
        let midway = lens.noseLength
        XCTAssertGreaterThan(midway, 0.3)
        XCTAssertLessThan(midway, 0.7)
        p.play(lie, seconds: 2)
        XCTAssertEqual(lens.noseLength, 1, accuracy: 0.001, "full length")
        XCTAssertEqual(lens.leafCount, 5, "and leaves all along it")
        Output.save(p.last, as: "expr-pinocchio-long.png")
        let long = bits(p.last)
        XCTAssertGreaterThan(count(long, in: CGRect(x: 700, y: 150, width: 580, height: 300)) { $0.g > $0.r + 40 && $0.g > $0.b }, 300, "green leaves")
        p.play(face(), seconds: 1)
        XCTAssertLessThan(lens.noseLength, midway, "shut your mouth and it shrinks")
        p.play(face(), seconds: 2)
        XCTAssertEqual(lens.noseLength, 0, accuracy: 0.001)
        XCTAssertEqual(lens.leafCount, 0)
    }

    func testLeavesSproutOneByOneAsItGrows() {
        let lens = ExprPinocchioLens()
        let p = Player(lens, base: base)
        var counts: [Int] = []
        for _ in 0..<80 {
            p.play(face { $0.mouthOpen = 1 }, seconds: 1.0 / 30)
            if counts.last != lens.leafCount { counts.append(lens.leafCount) }
        }
        XCTAssertEqual(counts, [0, 1, 2, 3, 4, 5], "a leaf at a time, never going back")
    }

    func testOnlyAnOpenMouthGrowsTheNose() {
        for (name, edit) in [("smile", { (f: inout FaceState) in f.smile = 1 }), ("brows", { $0.browRaise = 1 }), ("blink", { $0.blink = 1 })] as [(String, (inout FaceState) -> Void)] {
            let lens = ExprPinocchioLens()
            let p = Player(lens, base: base)
            p.play(face(edit), seconds: 3)
            XCTAssertEqual(lens.noseLength, 0, name)
            XCTAssertFalse(lens.isLying, name)
        }
    }

    func testTalkingKeepsItGoingAndAMutterDoesNot() {
        let lens = ExprPinocchioLens()
        let p = Player(lens, base: base)
        p.play(face { $0.mouthOpen = 0.2 }, seconds: 1)
        XCTAssertFalse(lens.isLying, "20% is just a mutter")
        XCTAssertEqual(lens.noseLength, 0)
        p.play(face { $0.mouthOpen = 0.5 }, seconds: 0.2)
        XCTAssertTrue(lens.isLying)
        for i in 0..<30 { p.play(face { $0.mouthOpen = i % 2 == 0 ? 0.4 : 0.2 }, seconds: 1.0 / 30) }
        XCTAssertTrue(lens.isLying, "mouthing between 20% and 40% counts as one long fib")
        p.play(face { $0.mouthOpen = 0.05 }, seconds: 0.1)
        XCTAssertFalse(lens.isLying)
    }

    func testTheStubShowsAtRestAndTheNoseStaysOnTheFaceSide() {
        let lens = ExprPinocchioLens()
        let p = Player(lens, base: base)
        let f = face()
        let rest = bits(p.play(f, seconds: 1))
        XCTAssertGreaterThan(rest.change(from: plain, in: CGRect(x: f.nose.x - 15, y: f.nose.y - 15, width: 40, height: 30)), 100, "a wooden stub where the nose is")
        XCTAssertEqual(rest.change(from: plain, in: CGRect(x: 0, y: 0, width: 400, height: 720)), 0)
        assertCornersUntouched(rest, "the stub")
        p.play(face { $0.mouthOpen = 1 }, seconds: 4)
        let long = bits(p.last)
        assertCornersUntouched(long, "the long nose")
        XCTAssertEqual(long.change(from: plain, in: CGRect(x: 0, y: 0, width: 440, height: 720)), 0, "it grows to one side only")
    }

    func testTheNoseTurnsWithATiltedHeadAndShrinksWithAFarOne() {
        var tilted = SyntheticScene(center: CGPoint(x: 500, y: 400)); tilted.roll = 0.5
        let frame = h.input(tilted)
        let still = bits(frame.composed)
        let p = Player(ExprPinocchioLens(), base: frame)
        var f = tilted.face(); f.mouthOpen = 1
        let out = bits(p.play(f, seconds: 4))
        Output.save(p.last, as: "expr-pinocchio-tilted.png")
        XCTAssertGreaterThan(out.change(from: still, in: CGRect(x: 640, y: 380, width: 360, height: 220)), 100, "pointing up and away with the tilt")

        let far = SyntheticScene(center: CGPoint(x: 300, y: 300), scale: 0.4)
        let farFrame = h.input(far)
        let farStill = bits(farFrame.composed)
        let q = Player(ExprPinocchioLens(), base: farFrame)
        var g = far.face(); g.mouthOpen = 1
        let small = bits(q.play(g, seconds: 4))
        Output.save(q.last, as: "expr-pinocchio-far.png")
        XCTAssertEqual(small.change(from: farStill, in: CGRect(x: 700, y: 0, width: 580, height: 720)), 0, "a distant face grows a short nose")
    }
}

// MARK: - Mood Aura

final class ExpressionMoodAuraTests: ExpressionLensTestCase {
    func testTheMoodPicksTheColourAndTheSize() {
        typealias Aura = ExprMoodAuraLens
        let calm = Aura.mood(for: face()), happy = Aura.mood(for: face { $0.smile = 1 })
        let loud = Aura.mood(for: face { $0.mouthOpen = 1 }), shocked = Aura.mood(for: face { $0.browRaise = 1 })
        XCTAssertGreaterThan(calm.colour.b, calm.colour.r + 0.4, "calm is blue")
        XCTAssertGreaterThan(happy.colour.r, 0.9); XCTAssertGreaterThan(happy.colour.g, 0.7); XCTAssertLessThan(happy.colour.b, 0.3)
        XCTAssertGreaterThan(loud.colour.r, 0.9); XCTAssertLessThan(loud.colour.g, 0.3); XCTAssertLessThan(loud.colour.b, 0.3)
        XCTAssertGreaterThan(shocked.colour.b, 0.9); XCTAssertGreaterThan(shocked.colour.r, 0.6); XCTAssertLessThan(shocked.colour.g, 0.5)
        XCTAssertGreaterThan(loud.size, shocked.size)
        XCTAssertGreaterThan(shocked.size, happy.size)
        XCTAssertGreaterThan(happy.size, calm.size)
        XCTAssertEqual(calm.size, 1)
        let laugh = Aura.mood(for: face { $0.smile = 1; $0.mouthOpen = 1 })
        XCTAssertGreaterThan(laugh.colour.g, 0.6, "a laugh is golden, not red")
    }

    func testTheGlowSettlesOnYourMoodAndFollowsItWithoutJumping() {
        let lens = ExprMoodAuraLens()
        let p = Player(lens, base: base)
        p.play(face(), seconds: 2)
        XCTAssertGreaterThan(lens.colour.b, 0.9)
        let before = lens.colour
        p.play(face { $0.smile = 1 }, seconds: 1.0 / 30)
        XCTAssertLessThan(abs(lens.colour.r - before.r), 0.2, "one frame doesn't flip the colour")
        p.play(face { $0.smile = 1 }, seconds: 2.5)
        XCTAssertGreaterThan(lens.colour.r, 0.9)
        XCTAssertLessThan(lens.colour.b, 0.3)
        XCTAssertEqual(lens.size, 1.25, accuracy: 0.05)
        p.play(face { $0.mouthOpen = 1 }, seconds: 3)
        XCTAssertGreaterThan(lens.size, 1.45)
        lens.restart()
        XCTAssertEqual(lens.size, 1)
    }

    func testWithABackdropTheGlowIsBehindYouAndYourFaceIsLeftAlone() {
        let lens = ExprMoodAuraLens()
        let p = Player(lens, base: base)
        let f = face()
        let out = bits(p.play(f, seconds: 2))
        Output.save(p.last, as: "expr-mood-aura-behind.png")
        XCTAssertTrue(lens.glowedBehind)
        XCTAssertEqual(out.change(from: plain, in: CGRect(x: f.nose.x - 20, y: f.nose.y - 10, width: 40, height: 20)), 0, "you are in front of it")
        XCTAssertGreaterThan(out.change(from: plain, in: CGRect(x: 770, y: 380, width: 60, height: 100)), 80, "it shines past the side of your head")
        XCTAssertGreaterThan(out.change(from: plain, in: CGRect(x: 580, y: 570, width: 120, height: 60)), 60, "and above it")
        assertCornersUntouched(out, "the aura")
        let side = out.pixel(790, 430), was = plain.pixel(790, 430)
        XCTAssertGreaterThan(side.b - was.b, side.r - was.r + 10, "it adds blue for calm, got \(side) over \(was)")
    }

    func testWithoutABackdropItIsAHaloAroundYou() {
        let lens = ExprMoodAuraLens()
        let frame = h.input(scene, background: false)
        let still = bits(frame.composed)
        let p = Player(lens, base: frame)
        let f = scene.face()
        let out = bits(p.play(f, seconds: 2))
        Output.save(p.last, as: "expr-mood-aura-halo.png")
        XCTAssertFalse(lens.glowedBehind)
        XCTAssertEqual(out.change(from: still, in: CGRect(x: f.nose.x - 20, y: f.nose.y - 10, width: 40, height: 20)), 0, "the middle of the face is clear")
        XCTAssertGreaterThan(out.change(from: still, in: CGRect(x: 770, y: 380, width: 60, height: 100)), 100, "but there is a ring around it")
        XCTAssertEqual(out.change(from: still, in: CGRect(x: 0, y: 0, width: 200, height: 120)), 0)
        XCTAssertEqual(out.change(from: still, in: CGRect(x: 1080, y: 600, width: 200, height: 120)), 0)
    }

    func testAFaceThatLeavesFadesTheGlowOutAndComesBackIn() {
        let lens = ExprMoodAuraLens()
        let p = Player(lens, base: base)
        p.play(face(), seconds: 1)
        XCTAssertEqual(bits(p.play(nil, seconds: 1)).change(from: plain, in: base.rect), 0)
        let first = bits(p.play(face(), seconds: 1.0 / 30))
        let later = bits(p.play(face(), seconds: 1))
        XCTAssertLessThan(first.change(from: plain, in: CGRect(x: 770, y: 380, width: 60, height: 100)), later.change(from: plain, in: CGRect(x: 770, y: 380, width: 60, height: 100)), "it fades back in")
    }
}

// MARK: - Alien

final class ExpressionAlienTests: ExpressionLensTestCase {
    func testTheFaceGoesGreenWithBlackEyesAndAntennae() {
        let lens = ExprAlienLens()
        let p = Player(lens, base: base)
        let f = face()
        let out = bits(p.play(f, seconds: 1.2))
        Output.save(p.last, as: "expr-alien.png")
        let cheek = f.exprPoint(-0.6, -0.8)
        let before = plain.pixel(Int(cheek.x), Int(cheek.y)), after = out.pixel(Int(cheek.x), Int(cheek.y))
        XCTAssertGreaterThan(before.r, before.g, "skin starts warm: \(before)")
        XCTAssertGreaterThan(after.g, after.r + 15, "and ends green: \(after)")
        XCTAssertGreaterThan(after.g, 150, "bright, not muddy: \(after)")
        for eye in [f.leftEye, f.rightEye] {
            let c = out.pixel(Int(eye.x), Int(eye.y))
            XCTAssertLessThan(c.r + c.g + c.b, 130, "glossy black eyes over yours: \(c)")
        }
        let top = f.exprPoint(0, 1.25)
        XCTAssertGreaterThan(count(out, in: CGRect(x: top.x - 100, y: top.y, width: 200, height: 100)) { $0.g > 200 && $0.r < 190 }, 20, "bright green bulbs above the head")
        assertCornersUntouched(out, "the alien")
    }

    func testTheWarpMakesABigForeheadAndLeavesTheTintOutOfIt() {
        let p = player(ExprAlienLens())
        let f = face()
        let out = bits(p.play(f, seconds: 1.2))
        // The hair line moves up: a bit above the top of the plain head is now hair.
        let spot = CGRect(x: f.eyeCenter.x - 10, y: f.eyeCenter.y + 1.4 * f.interocular + 3, width: 20, height: 12)
        XCTAssertGreaterThan(out.change(from: plain, in: spot), 60, "the forehead swells upward")
    }

    func testTheAntennaeWiggleAndStandUpWhenYouRaiseYourBrows() {
        let lens = ExprAlienLens()
        let p = Player(lens, base: base)
        let f = face()
        let region = CGRect(x: 520, y: 520, width: 240, height: 180)
        var seen: Set<Int> = []
        for _ in 0..<20 { seen.insert(count(bits(p.play(f, seconds: 1.0 / 30)), in: region) { $0.g > 200 && $0.r < 190 }) }
        XCTAssertGreaterThan(seen.count, 6, "the antennae are never still")
        XCTAssertEqual(lens.antennaePerk, 0, accuracy: 0.01)
        p.play(face { $0.browRaise = 1 }, seconds: 1)
        XCTAssertGreaterThan(lens.antennaePerk, 0.95, "they perk up")
        p.play(face { $0.smile = 1; $0.mouthOpen = 1; $0.blink = 1 }, seconds: 1)
        XCTAssertEqual(lens.antennaePerk, 0, accuracy: 0.01, "only the brows do that")
    }

    func testBlinkingShutsTheBigEyes() {
        var closed = scene; closed.blink = 1
        let p = Player(ExprAlienLens(), base: h.input(closed))
        let f = face()
        let open = bits(Player(ExprAlienLens(), base: base).play(f, seconds: 1))
        let shut = bits(p.play(closed.face(), seconds: 1))
        func darkPixels(_ b: Bitmap) -> Int { count(b, in: CGRect(x: f.leftEye.x - 30, y: f.leftEye.y - 20, width: 60, height: 35)) { $0.r + $0.g + $0.b < 130 } }
        XCTAssertGreaterThan(darkPixels(open), darkPixels(shut) * 3, "closed eyes are slits")
    }

    func testTheAlienTurnsWithAFarTiltedHead() {
        var s = SyntheticScene(center: CGPoint(x: 900, y: 330), scale: 0.5); s.roll = -0.4
        let frame = h.input(s)
        let still = bits(frame.composed)
        let p = Player(ExprAlienLens(), base: frame)
        let out = bits(p.play(s.face(), seconds: 1.2))
        Output.save(p.last, as: "expr-alien-far.png")
        XCTAssertGreaterThan(out.change(from: still, in: CGRect(x: 840, y: 300, width: 120, height: 120)), 100)
        XCTAssertLessThanOrEqual(out.change(from: still, in: CGRect(x: 0, y: 0, width: 600, height: 720)), 4)
    }
}

// MARK: - Swirl

final class ExpressionSwirlTests: ExpressionLensTestCase {
    func testTheTwirlGrowsWithAnOpenMouthAndTurnsWithTheTilt() {
        typealias Swirl = ExprSwirlLens
        let rest = Swirl.targetTwist(for: face())
        XCTAssertEqual(rest, Swirl.restingTwist, accuracy: 0.001)
        XCTAssertGreaterThan(Swirl.targetTwist(for: face { $0.mouthOpen = 0.5 }), rest + 1)
        XCTAssertGreaterThan(Swirl.targetTwist(for: face { $0.mouthOpen = 1 }), Swirl.targetTwist(for: face { $0.mouthOpen = 0.5 }) + 1)
        var left = scene, right = scene
        left.roll = 0.3; right.roll = -0.3
        XCTAssertGreaterThan(Swirl.targetTwist(for: left.face()), rest + 0.8)
        XCTAssertLessThan(Swirl.targetTwist(for: right.face()), rest - 0.8, "tipping the other way turns it the other way")
        var wild = scene; wild.roll = 1.4
        XCTAssertLessThanOrEqual(Swirl.targetTwist(for: wild.face()), 6)
        XCTAssertEqual(Swirl.targetTwist(for: face { $0.smile = 1; $0.browRaise = 1; $0.blink = 1 }), rest, accuracy: 0.001, "smiles, brows and blinks don't count")
    }

    func testTheLensFollowsTheMouthSmoothly() {
        let lens = ExprSwirlLens()
        let p = Player(lens, base: base)
        p.play(face(), seconds: 1)
        XCTAssertEqual(lens.currentTwist, ExprSwirlLens.restingTwist, accuracy: 0.02)
        p.play(face { $0.mouthOpen = 1 }, seconds: 1.0 / 30)
        XCTAssertLessThan(lens.currentTwist, 2, "it takes a few frames to wind up")
        p.play(face { $0.mouthOpen = 1 }, seconds: 1)
        XCTAssertGreaterThan(lens.currentTwist, 3.4)
        p.play(face { $0.smile = 1; $0.browRaise = 1 }, seconds: 1.5)
        XCTAssertEqual(lens.currentTwist, ExprSwirlLens.restingTwist, accuracy: 0.05)
    }

    func testTheSwirlStaysAroundTheFace() {
        let lens = ExprSwirlLens()
        let p = Player(lens, base: base)
        let f = face { $0.mouthOpen = 1 }
        let out = bits(p.play(f, seconds: 1.5))
        Output.save(p.last, as: "expr-swirl-open.png")
        XCTAssertGreaterThan(out.change(from: plain, in: CGRect(x: 560, y: 330, width: 160, height: 140)), 200, "the middle of the face is twisted")
        let reach = f.interocular * (ExprSwirlLens.reach + 0.1)
        let centre = f.exprFaceCenter
        XCTAssertLessThanOrEqual(out.change(from: plain, in: CGRect(x: 0, y: 0, width: centre.x - reach, height: 720)), 4)
        XCTAssertLessThanOrEqual(out.change(from: plain, in: CGRect(x: centre.x + reach, y: 0, width: 1280 - centre.x - reach, height: 720)), 4)
        XCTAssertLessThanOrEqual(out.change(from: plain, in: CGRect(x: 0, y: centre.y + reach, width: 1280, height: 720 - centre.y - reach)), 4)
        XCTAssertLessThanOrEqual(out.change(from: plain, in: CGRect(x: 0, y: 0, width: 1280, height: centre.y - reach)), 4)

        var tilted = SyntheticScene(center: CGPoint(x: 640, y: 400)); tilted.roll = 0.35
        let tiltedFrame = h.input(tilted)
        let q = Player(ExprSwirlLens(), base: tiltedFrame)
        q.play(tilted.face(), seconds: 1.5)
        Output.save(q.last, as: "expr-swirl-tilted.png")
        var far = SyntheticScene(center: CGPoint(x: 1000, y: 250), scale: 0.4); far.mouthOpen = 0.8
        let farFrame = h.input(far)
        let r = Player(ExprSwirlLens(), base: farFrame)
        r.play(far.face(), seconds: 1.5)
        Output.save(r.last, as: "expr-swirl-far.png")
        XCTAssertLessThanOrEqual(bits(r.last).change(from: bits(farFrame.composed), in: CGRect(x: 0, y: 0, width: 700, height: 720)), 4)
    }

    func testSparklesTurnAroundTheCentre() {
        let p = player(ExprSwirlLens())
        let f = face { $0.mouthOpen = 1 }
        let a = bits(p.play(f, seconds: 1.5)), b = bits(p.play(f, seconds: 0.15))
        XCTAssertGreaterThan(b.change(from: a, in: CGRect(x: 580, y: 330, width: 120, height: 120)), 40, "the sparkles move")
        XCTAssertGreaterThan(count(a, in: CGRect(x: 540, y: 300, width: 200, height: 200)) { $0.r > 235 && $0.g > 225 && $0.b > 200 }, 3, "bright points")
    }
}

// MARK: - Squeeze

final class ExpressionSqueezeTests: ExpressionLensTestCase {
    func testTheSqueezeSwingsBetweenTinyAndGiantOnASineWave() {
        let samples = stride(from: 0.0, to: 8.0, by: 0.02).map { ExprSqueezeLens.amount(at: $0) }
        XCTAssertLessThan(samples.min() ?? 0, -0.75, "tiny")
        XCTAssertGreaterThan(samples.max() ?? 0, 0.75, "giant")
        XCTAssertTrue(samples.allSatisfy { abs($0) <= 1 })
        XCTAssertEqual(ExprSqueezeLens.amount(at: 0), 0, accuracy: 0.001)
        XCTAssertEqual(ExprSqueezeLens.amount(at: 12.3), ExprSqueezeLens.amount(at: 12.3))
        // The pulse: within a second the value wiggles up and down.
        let second = stride(from: 1.0, to: 2.0, by: 0.02).map { ExprSqueezeLens.amount(at: $0) }
        var turns = 0
        for i in 2..<second.count where (second[i] - second[i - 1]) * (second[i - 1] - second[i - 2]) < 0 { turns += 1 }
        XCTAssertGreaterThanOrEqual(turns, 2, "the beat rides on top of the slow swing")
    }

    func testFeaturesShrinkThenSwellAndNothingElseMoves() {
        let f = face()
        let eyeBox = CGRect(x: f.leftEye.x - 45, y: f.leftEye.y - 35, width: 80, height: 60)
        /// How much white is showing in the left eye's box.
        func eyeArea(_ b: Bitmap) -> Int { count(b, in: eyeBox) { $0.r > 225 && $0.g > 225 && $0.b > 225 } }
        func whiteOfTheEyes(at time: Double) -> (Int, Bitmap) {
            let lens = ExprSqueezeLens()
            var out = base.composed
            for i in 0..<20 { out = lens.render(h.at(base, time: time + Double(i) * 0.001)) }
            let b = bits(out)
            return (eyeArea(b), b)
        }
        let rest = eyeArea(plain)
        let (tinyCount, tinyBits) = whiteOfTheEyes(at: 5.25)       // three quarters through: most squeezed
        let (giantCount, giantBits) = whiteOfTheEyes(at: 1.75)     // a quarter through: most swollen
        XCTAssertLessThan(ExprSqueezeLens.amount(at: 5.25), -0.6)
        XCTAssertGreaterThan(ExprSqueezeLens.amount(at: 1.75), 0.6)
        XCTAssertLessThan(tinyCount, rest / 2, "tiny eyes")
        XCTAssertGreaterThan(giantCount, rest * 13 / 10, "giant eyes")
        for b in [tinyBits, giantBits] {
            XCTAssertLessThanOrEqual(b.change(from: plain, in: CGRect(x: 0, y: 0, width: 490, height: 720)), 4)
            XCTAssertLessThanOrEqual(b.change(from: plain, in: CGRect(x: 790, y: 0, width: 490, height: 720)), 4)
            XCTAssertLessThanOrEqual(b.change(from: plain, in: CGRect(x: 0, y: 0, width: 1280, height: 220)), 4)
        }
        Output.save(CIImage(bitmapData: Data(tinyBits.bytes), bytesPerRow: tinyBits.width * 4, size: CGSize(width: tinyBits.width, height: tinyBits.height), format: .RGBA8, colorSpace: TestSupport.srgb), as: "expr-squeeze-tiny.png")
        Output.save(CIImage(bitmapData: Data(giantBits.bytes), bytesPerRow: giantBits.width * 4, size: CGSize(width: giantBits.width, height: giantBits.height), format: .RGBA8, colorSpace: TestSupport.srgb), as: "expr-squeeze-giant.png")
    }

    func testExpressionsDontChangeTheSqueeze() {
        // The warp depends on where the face is and what time it is, not on what the face is doing.
        func warped(_ f: FaceState) -> Bitmap {
            let lens = ExprSqueezeLens()
            var out = base.composed
            for i in 0..<20 { out = lens.render(LensInput(time: 4 + Double(i) / 30, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: base.matte, background: base.background, composed: base.composed, matteGrid: nil, face: f, services: base.services)) }
            return bits(out)
        }
        let calm = warped(face())
        for edit in [{ (f: inout FaceState) in f.smile = 1 }, { $0.mouthOpen = 1 }, { $0.browRaise = 1 }, { $0.blink = 1 }] as [(inout FaceState) -> Void] {
            XCTAssertEqual(warped(face(edit)).change(from: calm, in: base.rect), 0)
        }
    }

    func testTheSqueezeFollowsATiltedFarFace() {
        var s = SyntheticScene(center: CGPoint(x: 300, y: 300), scale: 0.5); s.roll = 0.4
        let frame = h.input(s)
        let still = bits(frame.composed)
        let lens = ExprSqueezeLens()
        var out = frame.composed
        for i in 0..<20 { out = lens.render(h.at(frame, time: 1.75 + Double(i) / 30)) }
        let b = bits(out)
        Output.save(out, as: "expr-squeeze-far.png")
        XCTAssertGreaterThan(b.change(from: still, in: CGRect(x: 240, y: 250, width: 120, height: 120)), 100)
        XCTAssertLessThanOrEqual(b.change(from: still, in: CGRect(x: 600, y: 0, width: 680, height: 720)), 4)
    }
}

// MARK: - Googly Eyes

final class ExpressionGooglyEyesTests: ExpressionLensTestCase {
    func testPupilsSinkToTheBottomOfTheirEyesWhenYouHoldStill() {
        let lens = ExprGooglyEyesLens()
        let p = Player(lens, base: base)
        let f = face()
        let out = bits(p.play(f, seconds: 1.5))
        Output.save(p.last, as: "expr-googly-eyes.png")
        for pupil in lens.pupilPositions {
            XCTAssertLessThan(pupil.y, -0.1, "sunk to the bottom: \(pupil)")
            XCTAssertEqual(simd_length(pupil), ExprGooglyEyesLens.whiteRadius - ExprGooglyEyesLens.pupilRadius - 0.015, accuracy: 0.03, "and resting against the rim")
        }
        for eye in [f.leftEye, f.rightEye] {
            let c = out.pixel(Int(eye.x), Int(eye.y + f.interocular * 0.25))
            XCTAssertGreaterThan(c.r + c.g + c.b, 600, "white eyeballs, got \(c)")
        }
        assertCornersUntouched(out, "the googly eyes")
    }

    func testPupilsSloshWhenTheHeadIsShaken() {
        let lens = ExprGooglyEyesLens()
        let p = Player(lens, base: base)
        p.play(face(), seconds: 1)
        var widest = 0.0
        for i in 0..<45 {
            var s = scene
            s.center.x += 40 * sin(Double(i) * 0.9)
            p.play(s.face(), seconds: 1.0 / 30)
            widest = max(widest, abs(Double(lens.pupilPositions[0].x)))
        }
        XCTAssertGreaterThan(widest, 0.08, "the pupils swing sideways as the head shakes")
    }

    func testPupilsNeverLeaveTheirEyes() {
        var pupil = ExprGooglyEyesLens.Pupil()
        let room = ExprGooglyEyesLens.whiteRadius - ExprGooglyEyesLens.pupilRadius
        for i in 0..<400 {
            ExprGooglyEyesLens.step(&pupil, push: SIMD2(sin(Double(i)) * 60, cos(Double(i) * 1.7) * 60), dt: i % 7 == 0 ? 0.2 : 1.0 / 30)
            XCTAssertLessThanOrEqual(simd_length(pupil.position), room, "frame \(i)")
        }
    }

    func testBlinkingSquashesTheEyeballs() {
        var closed = scene; closed.blink = 1
        let f = face()
        let open = bits(Player(ExprGooglyEyesLens(), base: base).play(f, seconds: 1))
        let shut = bits(Player(ExprGooglyEyesLens(), base: h.input(closed)).play(closed.face(), seconds: 1))
        func white(_ b: Bitmap) -> Int { count(b, in: CGRect(x: f.leftEye.x - 40, y: f.leftEye.y - 40, width: 80, height: 80)) { $0.r > 235 && $0.g > 235 && $0.b > 235 } }
        XCTAssertGreaterThan(white(open), white(shut) * 4)
    }
}

// MARK: - Cost

/// What each lens adds to a frame while a face is making expressions. Opt in with TEST_RUNNER_BACKDROP_PERF=1.
final class ExpressionCostTests: ExpressionLensTestCase {
    func testEveryExpressionLensIsCheap() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BACKDROP_PERF"] != nil, "set TEST_RUNNER_BACKDROP_PERF=1 to measure")
        let buffer = try XCTUnwrap(h.compositor.makeOutputBuffer())
        let poses: [FaceState] = [face(), face { $0.smile = 1 }, face { $0.browRaise = 1 }, face { $0.mouthOpen = 1 }, face { $0.smile = 1; $0.mouthOpen = 0.8; $0.browRaise = 1 }]
        func milliseconds(_ lens: Lens?) -> Double {
            var total = 0.0
            let frames = 150
            for i in 0..<frames {
                let f = poses[(i / 24) % poses.count]
                let started = CFAbsoluteTimeGetCurrent()
                let image = lens?.render(LensInput(time: Double(i) / 30, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: base.matte, background: base.background,
                                                   composed: base.composed, matteGrid: nil, face: f, services: base.services)) ?? base.composed
                h.compositor.render(image, into: buffer)
                if i >= 30 { total += CFAbsoluteTimeGetCurrent() - started }
            }
            return total / Double(frames - 30) * 1000
        }
        let baseline = milliseconds(nil)
        print(String(format: "PERF %-14@ %5.1f ms", "(no lens)" as NSString, baseline))
        // The round-one funhouse, breath and laser lenses live in the core catalog but are looked after here too.
        let core: [(String, () -> Lens)] = [("Big Eyes", { FunhouseLens(kind: .bigEyes) }), ("Chipmunk", { FunhouseLens(kind: .chipmunk) }),
                                            ("Big Mouth", { FunhouseLens(kind: .bigMouth) }), ("Rainbow", { BreathLens(kind: .rainbow) }),
                                            ("Fire Breath", { BreathLens(kind: .fire) }), ("Laser Eyes", { LaserEyesLens() })]
        for (name, make) in ExpressionFaces.all.map({ ($0.name, $0.make) }) + core {
            let cost = milliseconds(make()) - baseline
            print(String(format: "PERF %-14@ adds %5.1f ms", name as NSString, cost))
            XCTAssertLessThan(cost, 9, "\(name) adds too much to every frame")
        }
    }
}

extension ExpressionCostTests {
    /// Lenses are made on the main thread and their art is baked on the first frame, so that first frame must stay short.
    func testFirstFramesAreQuick() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BACKDROP_PERF"] != nil, "set TEST_RUNNER_BACKDROP_PERF=1 to measure")
        let entries = ExpressionFaces.all      // as at launch: this also starts building the warp kernel
        let buffer = try XCTUnwrap(h.compositor.makeOutputBuffer())
        // Warm the pipeline itself (the first composite of a drawn layer in a process is slow whatever the lens).
        h.compositor.render(base.services.overlay { _ in }!.composited(over: base.composed), into: buffer)
        Thread.sleep(forTimeInterval: 1.5)
        let poses = [face { $0.smile = 1; $0.mouthOpen = 0.8; $0.browRaise = 1 }]
        for info in entries {
            var made = 0.0, first = 0.0
            let start = CFAbsoluteTimeGetCurrent()
            let lens = info.make()
            made = (CFAbsoluteTimeGetCurrent() - start) * 1000
            let t0 = CFAbsoluteTimeGetCurrent()
            for f in poses {
                h.compositor.render(lens.render(LensInput(time: 0, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: base.matte, background: base.background,
                                                          composed: base.composed, matteGrid: nil, face: f, services: base.services)), into: buffer)
            }
            first = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            print(String(format: "FIRST %-14@ make %5.1f ms, first frame %5.1f ms", info.name as NSString, made, first))
            XCTAssertLessThan(made, 5, "\(info.name) is slow to make")
            XCTAssertLessThan(first, 30, "\(info.name) hitches on its first frame")
        }
    }
}

// MARK: - Pictures

/// Contact sheets of the lenses in several poses, to look at (set BACKDROP_TEST_OUTPUT to save them).
final class ExpressionGalleryTests: ExpressionLensTestCase {
    private func snapshot(_ image: CIImage) -> CIImage {
        let b = bits(image)
        return CIImage(bitmapData: Data(b.bytes), bytesPerRow: b.width * 4, size: CGSize(width: b.width, height: b.height), format: .RGBA8, colorSpace: TestSupport.srgb)
    }

    private func sheet(_ cells: [CIImage], crop: CGRect) -> CIImage {
        var out = CIImage(color: CIColor(red: 0.08, green: 0.08, blue: 0.08)).cropped(to: CGRect(x: 0, y: 0, width: crop.width * Double(cells.count), height: crop.height))
        for (i, cell) in cells.enumerated() {
            out = cell.cropped(to: crop).transformed(by: CGAffineTransform(translationX: Double(i) * crop.width - crop.minX, y: -crop.minY)).composited(over: out)
        }
        return out
    }

    private func gallery(_ name: String, _ make: () -> Lens, _ states: [(SyntheticScene, Double)], crop: CGRect = CGRect(x: 400, y: 120, width: 480, height: 600), background: Bool = true) {
        let cells = states.map { state -> CIImage in
            let p = Player(make(), base: h.input(state.0, background: background))
            p.play(state.0.face(), seconds: state.1)
            return snapshot(p.last)
        }
        Output.save(sheet(cells, crop: crop), as: "gallery-\(name).png")
    }

    private func pose(_ build: (inout SyntheticScene) -> Void) -> SyntheticScene {
        var s = SyntheticScene(center: CGPoint(x: 640, y: 400))
        build(&s)
        return s
    }

    func testGalleries() {
        gallery("heart-eyes", { ExprHeartEyesLens() }, [(pose { _ in }, 1), (pose { $0.smile = 1 }, 2), (pose { $0.smile = 1; $0.roll = 0.35 }, 2), (pose { $0.blink = 1 }, 1)])
        gallery("star-eyes", { ExprStarEyesLens() }, [(pose { _ in }, 1), (pose { $0.browRaise = 1 }, 0.2), (pose { $0.browRaise = 1 }, 1), (pose { $0.roll = -0.3 }, 1)])
        gallery("happy-tears", { ExprHappyTearsLens() }, [(pose { _ in }, 1), (pose { $0.smile = 1 }, 0.5), (pose { $0.smile = 1; $0.mouthOpen = 0.6 }, 1.5), (pose { $0.smile = 1; $0.roll = 0.3 }, 2)])
        gallery("storm-cloud", { ExprStormCloudLens() }, [(pose { _ in }, 1), (pose { $0.browRaise = 1 }, 0.5), (pose { $0.browRaise = 1 }, 1.4), (pose { $0.browRaise = 1; $0.roll = 0.3 }, 1.2)])
        gallery("emoji-mask", { ExprEmojiMaskLens() }, [(pose { _ in }, 1), (pose { $0.smile = 1 }, 1), (pose { $0.mouthOpen = 1 }, 1), (pose { $0.browRaise = 1 }, 1), (pose { $0.blink = 1 }, 1), (pose { $0.smile = 1; $0.mouthOpen = 1; $0.roll = 0.3 }, 1)])
        gallery("pinocchio", { ExprPinocchioLens() }, [(pose { _ in }, 1), (pose { $0.mouthOpen = 0.8 }, 0.8), (pose { $0.mouthOpen = 0.8 }, 1.6), (pose { $0.mouthOpen = 0.8 }, 3), (pose { $0.mouthOpen = 0.8; $0.roll = 0.3 }, 3)],
                crop: CGRect(x: 360, y: 80, width: 640, height: 600))
        gallery("mood-aura", { ExprMoodAuraLens() }, [(pose { _ in }, 2), (pose { $0.smile = 1 }, 2), (pose { $0.mouthOpen = 1 }, 2), (pose { $0.browRaise = 1 }, 2)], crop: CGRect(x: 340, y: 100, width: 600, height: 620))
        gallery("mood-aura-halo", { ExprMoodAuraLens() }, [(pose { _ in }, 2), (pose { $0.smile = 1 }, 2), (pose { $0.mouthOpen = 1 }, 2), (pose { $0.browRaise = 1 }, 2)], crop: CGRect(x: 340, y: 100, width: 600, height: 620), background: false)
        gallery("alien", { ExprAlienLens() }, [(pose { _ in }, 1), (pose { $0.browRaise = 1 }, 1), (pose { $0.blink = 1 }, 1), (pose { $0.roll = 0.3 }, 1)])
        gallery("swirl", { ExprSwirlLens() }, [(pose { _ in }, 1), (pose { $0.mouthOpen = 1 }, 1), (pose { $0.roll = 0.3 }, 1), (pose { $0.roll = -0.3 }, 1)])
        gallery("googly-eyes", { ExprGooglyEyesLens() }, [(pose { _ in }, 1), (pose { $0.blink = 1 }, 1), (pose { $0.roll = 0.3 }, 1)])
    }
}
