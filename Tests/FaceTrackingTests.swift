import CoreGraphics
import XCTest

/// Landmark points laid out the way Vision reports a face, from head-relative numbers, so the maths can be checked
/// with no camera and no Vision.
extension RawFace {
    static func synthetic(center: CGPoint = CGPoint(x: 640, y: 400), scale: Double = 1, roll: Double = 0,
                          lipGap: Double = 0.02, browDistance: Double = 0.30, swapEyes: Bool = false,
                          eyeOpen: Double = 0.08, mouthHalfWidth: Double = 0.42, leftEyeOpen: Double? = nil,
                          yaw: Double = 0, pitch: Double = 0) -> RawFace {
        let io = 84 * scale
        func at(_ x: Double, _ y: Double) -> CGPoint {   // face units (eye spacings), then turned, tilted and placed
            let px = x * io * cos(yaw), py = y * io * cos(pitch)       // turning the head squeezes what is across it; tipping, what is up it
            return CGPoint(x: center.x + px * cos(roll) - py * sin(roll), y: center.y + px * sin(roll) + py * cos(roll))
        }
        func ring(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ n: Int = 8) -> [CGPoint] {
            (0..<n).map { i in
                let a = Double(i) / Double(n) * 2 * .pi
                return at(cx + rx * cos(a), cy + ry * sin(a))
            }
        }
        func line(_ x0: Double, _ x1: Double, _ y: Double) -> [CGPoint] { (0..<5).map { at(x0 + (x1 - x0) * Double($0) / 4, y) } }

        let eyeL = ring(-0.5, 0, 0.2, leftEyeOpen ?? eyeOpen), eyeR = ring(0.5, 0, 0.2, eyeOpen)
        let browY = browDistance
        return RawFace(leftEye: swapEyes ? eyeR : eyeL, rightEye: swapEyes ? eyeL : eyeR,
                       leftBrow: line(-0.72, -0.28, browY), rightBrow: line(0.28, 0.72, browY),
                       outerLips: ring(0, -0.95, mouthHalfWidth, 0.1 + lipGap / 2), innerLips: ring(0, -0.95, 0.3, max(0.001, lipGap / 2)),
                       rect: CGRect(x: center.x - 95 * scale, y: center.y - 130 * scale, width: 190 * scale, height: 250 * scale),
                       yaw: yaw, pitch: pitch)
    }
}

final class FaceFeatureTests: XCTestCase {
    func testEyesMouthAndBrowsAreFound() throws {
        let m = try XCTUnwrap(FaceFeatureExtractor.measure(.synthetic()))
        XCTAssertEqual(m.leftEye.x, 640 - 42, accuracy: 1)
        XCTAssertEqual(m.rightEye.x, 640 + 42, accuracy: 1)
        XCTAssertEqual(m.leftEye.y, 400, accuracy: 1)
        XCTAssertEqual(m.mouth.y, 400 - 0.95 * 84, accuracy: 1)
        XCTAssertEqual(m.mouthWidth, 0.84 * 84, accuracy: 3)
        XCTAssertEqual(m.browDistance, 0.30 / 0.95, accuracy: 0.01, "relative to the eyes-to-mouth distance, which is 0.95 eye-spacings here")
    }

    func testLeftAndRightAreAsSeenInThePictureWhateverVisionCallsThem() throws {
        let m = try XCTUnwrap(FaceFeatureExtractor.measure(.synthetic(swapEyes: true)))
        XCTAssertLessThan(m.leftEye.x, m.rightEye.x)
    }

    func testMeasurementsDoNotDependOnHowBigOrHowTiltedTheFaceIs() throws {
        let base = try XCTUnwrap(FaceFeatureExtractor.measure(.synthetic(lipGap: 0.4, browDistance: 0.4)))
        for (scale, roll) in [(0.5, 0.0), (1.8, 0.0), (1.0, 0.5), (0.7, -0.6)] {
            let m = try XCTUnwrap(FaceFeatureExtractor.measure(.synthetic(scale: scale, roll: roll, lipGap: 0.4, browDistance: 0.4)))
            XCTAssertEqual(m.lipGap, base.lipGap, accuracy: 0.02, "lip gap at scale \(scale), roll \(roll)")
            XCTAssertEqual(m.browDistance, base.browDistance, accuracy: 0.02, "brow distance at scale \(scale), roll \(roll)")
            XCTAssertEqual(m.mouthWidth / (84 * scale), base.mouthWidth / 84, accuracy: 0.03)
        }
    }

    func testTheMouthOpensMonotonically() throws {
        let opens = try [0.0, 0.1, 0.25, 0.45, 0.7].map { gap -> Double in
            FaceFeatureExtractor.mouthOpen(lipGap: try XCTUnwrap(FaceFeatureExtractor.measure(.synthetic(lipGap: gap))).lipGap)
        }
        XCTAssertEqual(opens, opens.sorted())
        XCTAssertEqual(opens[0], 0, accuracy: 0.05, "closed")
        XCTAssertEqual(opens.last!, 1, accuracy: 0.001, "wide open")
        XCTAssertGreaterThan(opens[3], 0.5)
    }

    func testIncompleteLandmarksAreRejected() {
        var raw = RawFace.synthetic()
        raw.innerLips = []
        XCTAssertNotNil(FaceFeatureExtractor.measure(raw), "no inner lips still gives a face, with a closed mouth")
        raw.leftEye = []
        XCTAssertNil(FaceFeatureExtractor.measure(raw))
        var tiny = RawFace.synthetic(scale: 0.02)
        tiny.rect = .zero
        XCTAssertNil(FaceFeatureExtractor.measure(tiny), "a speck isn't a face")
    }
}

final class FaceSmootherTests: XCTestCase {
    private let dt = 1.0 / 30
    private func measure(x: Double = 640, lipGap: Double = 0.02, brow: Double = 0.30, eyeOpen: Double = 0.08, mouth: Double = 0.42,
                         leftEyeOpen: Double? = nil, yaw: Double = 0, pitch: Double = 0) -> FaceMeasure {
        FaceFeatureExtractor.measure(.synthetic(center: CGPoint(x: x, y: 400), lipGap: lipGap, browDistance: brow, eyeOpen: eyeOpen, mouthHalfWidth: mouth,
                                                leftEyeOpen: leftEyeOpen, yaw: yaw, pitch: pitch))!
    }

    func testBlinksAreSeenAgainstHowWideOpenTheseEyesAre() throws {
        var smoother = FaceSmoother()
        var face: FaceState?
        for _ in 0..<60 { face = smoother.update(measure(eyeOpen: 0.08), dt: dt) }
        XCTAssertEqual(try XCTUnwrap(face).blink, 0, accuracy: 0.05)
        for _ in 0..<6 { face = smoother.update(measure(eyeOpen: 0.02), dt: dt) }
        XCTAssertGreaterThan(try XCTUnwrap(face).blink, 0.85, "eyes shut")
        for _ in 0..<12 { face = smoother.update(measure(eyeOpen: 0.08), dt: dt) }
        XCTAssertLessThan(try XCTUnwrap(face).blink, 0.1, "and open again")
    }

    func testPeopleWithNarrowEyesDoNotLookLikeTheyAreBlinking() throws {
        var smoother = FaceSmoother()
        var worst = 0.0
        for i in 0..<300 {
            // Narrow eyes with the sort of measurement noise real landmarks have, different on each frame.
            let noise = 0.003 * sin(Double(i) * 2.3) + 0.002 * sin(Double(i) * 0.7)        // about plus or minus a tenth
            worst = max(worst, try XCTUnwrap(smoother.update(measure(eyeOpen: 0.045 + noise), dt: dt)).blink)
        }
        XCTAssertLessThan(worst, 0.3, "narrow eyes with jitter never look like blinks")
    }

    func testSmilesAreWiderThanThisMouthAtRest() throws {
        var smoother = FaceSmoother()
        var face: FaceState?
        for _ in 0..<90 { face = smoother.update(measure(mouth: 0.40), dt: dt) }
        XCTAssertEqual(try XCTUnwrap(face).smile, 0, accuracy: 0.05)
        for _ in 0..<20 { face = smoother.update(measure(mouth: 0.55), dt: dt) }
        XCTAssertGreaterThan(try XCTUnwrap(face).smile, 0.8, "a broad smile")
        for _ in 0..<30 { face = smoother.update(measure(mouth: 0.40), dt: dt) }
        XCTAssertLessThan(try XCTUnwrap(face).smile, 0.15, "and relaxed again")
    }

    // MARK: Things a real face does

    func testTurningTheHeadDoesNotRaiseEyebrowsOpenTheMouthOrBlink() throws {
        for yaw in [0.3, 0.5, 0.6] {
            var smoother = FaceSmoother()
            for _ in 0..<60 { _ = smoother.update(measure(brow: 0.32), dt: dt) }                    // settled, facing the camera
            var worst = FaceState(leftEye: .zero, rightEye: .zero, mouth: .zero, mouthWidth: 0, browCenter: .zero, rect: .zero,
                                  mouthOpen: 0, browRaise: 0, browDistance: 0)
            for _ in 0..<45 {                                                                          // a second and a half looking at another screen
                let face = try XCTUnwrap(smoother.update(measure(brow: 0.32, yaw: yaw), dt: dt))
                worst.browRaise = max(worst.browRaise, face.browRaise); worst.blink = max(worst.blink, face.blink)
                worst.smile = max(worst.smile, face.smile); worst.mouthOpen = max(worst.mouthOpen, face.mouthOpen)
            }
            XCTAssertLessThan(worst.browRaise, 0.2, "yaw \(yaw): brows")
            XCTAssertLessThan(worst.blink, 0.2, "yaw \(yaw): blink")
            XCTAssertLessThan(worst.smile, 0.2, "yaw \(yaw): smile")
            XCTAssertLessThan(worst.mouthOpen, 0.1, "yaw \(yaw): mouth")
            // And turning back leaves nothing behind.
            var after: FaceState?
            for _ in 0..<10 { after = smoother.update(measure(brow: 0.32), dt: dt) }
            XCTAssertLessThan(try XCTUnwrap(after).browRaise, 0.2, "yaw \(yaw): back to the camera")
            XCTAssertLessThan(try XCTUnwrap(after).blink, 0.2)
        }
    }

    func testLookingDownAtTheKeyboardDoesNotSetAnythingOff() throws {
        var smoother = FaceSmoother()
        for _ in 0..<60 { _ = smoother.update(measure(brow: 0.32), dt: dt) }
        var worstBrow = 0.0
        for _ in 0..<30 { worstBrow = max(worstBrow, try XCTUnwrap(smoother.update(measure(brow: 0.32, pitch: 0.5), dt: dt)).browRaise) }
        XCTAssertLessThan(worstBrow, 0.2)
        var after: FaceState?
        for _ in 0..<150 { after = smoother.update(measure(brow: 0.32), dt: dt) }
        XCTAssertLessThan(try XCTUnwrap(after).browRaise, 0.1, "no lingering raise ten seconds after looking down")
    }

    func testWideEyesDoNotMakeTheNextRestingMomentLookLikeABlink() throws {
        var smoother = FaceSmoother()
        for _ in 0..<60 { _ = smoother.update(measure(eyeOpen: 0.08), dt: dt) }
        for _ in 0..<15 { _ = smoother.update(measure(eyeOpen: 0.11), dt: dt) }                 // half a second of surprise
        var worst = 0.0
        for _ in 0..<90 { worst = max(worst, try XCTUnwrap(smoother.update(measure(eyeOpen: 0.08), dt: dt)).blink) }
        XCTAssertLessThan(worst, 0.5, "back to normal, not shut (\(worst))")
    }

    func testSquintingInASmileIsNotABlinkButAShutEyeIs() throws {
        var smoother = FaceSmoother()
        for _ in 0..<60 { _ = smoother.update(measure(eyeOpen: 0.08, mouth: 0.40), dt: dt) }
        var worstSquint = 0.0
        for _ in 0..<20 { worstSquint = max(worstSquint, try XCTUnwrap(smoother.update(measure(eyeOpen: 0.06, mouth: 0.55), dt: dt)).blink) }   // a quarter closed
        XCTAssertLessThan(worstSquint, 0.5, "squint \(worstSquint)")
        var best = 0.0
        for _ in 0..<4 { best = max(best, try XCTUnwrap(smoother.update(measure(eyeOpen: 0.02, mouth: 0.55), dt: dt)).blink) }               // three quarters closed for 0.13 s
        XCTAssertGreaterThan(best, 0.5, "a real blink still shows (\(best))")
    }

    func testAWinkIsNotABlink() throws {
        var smoother = FaceSmoother()
        for _ in 0..<60 { _ = smoother.update(measure(eyeOpen: 0.08), dt: dt) }
        var worst = 0.0
        for _ in 0..<10 { worst = max(worst, try XCTUnwrap(smoother.update(measure(eyeOpen: 0.08, leftEyeOpen: 0.01), dt: dt)).blink) }
        XCTAssertLessThan(worst, 0.2)
    }

    func testABriefWiderMouthForAWordIsNotASmileButAHeldOneIs() throws {
        var smoother = FaceSmoother()
        for _ in 0..<90 { _ = smoother.update(measure(mouth: 0.40), dt: dt) }
        var worst = 0.0
        for _ in 0..<6 { worst = max(worst, try XCTUnwrap(smoother.update(measure(mouth: 0.44), dt: dt)).smile) }      // 0.2 s of "ee", a tenth wider
        XCTAssertLessThan(worst, 0.4, "a word \(worst)")
        var held: FaceState?
        for _ in 0..<(30 * 30) { held = smoother.update(measure(mouth: 0.55), dt: dt) }                              // thirty seconds of a real smile
        XCTAssertGreaterThan(try XCTUnwrap(held).smile, 0.8, "a smile held for half a minute doesn't fade")
    }

    func testBlinkingAndSmilingMeasureTheSameWhateverTheHeadDoes() throws {
        for (scale, roll) in [(0.6, 0.0), (1.6, 0.4), (1.0, -0.5)] {
            let a = try XCTUnwrap(FaceFeatureExtractor.measure(.synthetic(scale: scale, roll: roll, eyeOpen: 0.05, mouthHalfWidth: 0.5)))
            let b = try XCTUnwrap(FaceFeatureExtractor.measure(.synthetic(eyeOpen: 0.05, mouthHalfWidth: 0.5)))
            XCTAssertEqual(a.eyeOpenness, b.eyeOpenness, accuracy: 0.02, "scale \(scale), roll \(roll)")
            XCTAssertEqual(a.mouthWidthRatio, b.mouthWidthRatio, accuracy: 0.03)
        }
    }

    func testTheFirstSightingIsUsedAsIs() throws {
        var smoother = FaceSmoother()
        let face = try XCTUnwrap(smoother.update(measure(), dt: dt))
        XCTAssertEqual(face.eyeCenter.x, 640, accuracy: 1)
        XCTAssertEqual(face.browRaise, 0, accuracy: 0.01)
    }

    func testMovementIsFollowedWithoutJumping() throws {
        var smoother = FaceSmoother()
        _ = smoother.update(measure(x: 600), dt: dt)
        let a = try XCTUnwrap(smoother.update(measure(x: 700), dt: dt)).eyeCenter.x
        XCTAssertGreaterThan(a, 600); XCTAssertLessThan(a, 700, "partway, not a jump")
        var last = a
        for _ in 0..<30 { last = try XCTUnwrap(smoother.update(measure(x: 700), dt: dt)).eyeCenter.x }
        XCTAssertEqual(last, 700, accuracy: 2, "and gets there within a second")
    }

    func testRaisingEyebrowsReadsAsARaiseRelativeToRest() throws {
        var smoother = FaceSmoother()
        var face: FaceState?
        for _ in 0..<60 { face = smoother.update(measure(brow: 0.36), dt: dt) }       // someone whose rest is high
        XCTAssertEqual(try XCTUnwrap(face).browRaise, 0, accuracy: 0.05)
        for _ in 0..<30 { face = smoother.update(measure(brow: 0.36 + 0.14), dt: dt) }
        XCTAssertGreaterThan(try XCTUnwrap(face).browRaise, 0.85)
        for _ in 0..<30 { face = smoother.update(measure(brow: 0.36), dt: dt) }
        XCTAssertLessThan(try XCTUnwrap(face).browRaise, 0.1, "and back down")
    }

    func testARestingFaceNeverLooksSurprised() throws {
        var smoother = FaceSmoother()
        var worst = 0.0
        for i in 0..<300 {
            let noise = 0.01 * sin(Double(i) * 1.7)       // measurement jitter
            worst = max(worst, try XCTUnwrap(smoother.update(measure(brow: 0.32 + noise), dt: dt)).browRaise)
        }
        XCTAssertLessThan(worst, 0.35, "jitter shouldn't set off laser eyes")
    }

    func testMouthOpenIsSmoothedAndReachesFull() throws {
        var smoother = FaceSmoother()
        _ = smoother.update(measure(), dt: dt)
        let first = try XCTUnwrap(smoother.update(measure(lipGap: 0.6), dt: dt)).mouthOpen
        XCTAssertGreaterThan(first, 0.1); XCTAssertLessThan(first, 0.9)
        var last = first
        for _ in 0..<15 { last = try XCTUnwrap(smoother.update(measure(lipGap: 0.6), dt: dt)).mouthOpen }
        XCTAssertGreaterThan(last, 0.95)
    }

    func testBriefLossesAreBridgedAndLongOnesReported() throws {
        var smoother = FaceSmoother()
        _ = smoother.update(measure(), dt: dt)
        XCTAssertNotNil(smoother.update(nil, dt: dt), "one missed frame isn't worth reporting")
        XCTAssertNotNil(smoother.update(nil, dt: dt))
        for _ in 0..<12 { _ = smoother.update(nil, dt: dt) }
        XCTAssertNil(smoother.update(nil, dt: dt), "gone for good after about \(FaceSmoother.holdSeconds) s")
        let back = try XCTUnwrap(smoother.update(measure(x: 900), dt: dt))
        XCTAssertEqual(back.eyeCenter.x, 900, accuracy: 1, "coming back starts where the face is, not where it was")
    }
}
