import CoreGraphics
import XCTest

/// Landmark points laid out the way Vision reports a face, from head-relative numbers, so the maths can be checked
/// with no camera and no Vision.
extension RawFace {
    static func synthetic(center: CGPoint = CGPoint(x: 640, y: 400), scale: Double = 1, roll: Double = 0,
                          lipGap: Double = 0.02, browDistance: Double = 0.30, swapEyes: Bool = false) -> RawFace {
        let io = 84 * scale
        func at(_ x: Double, _ y: Double) -> CGPoint {   // face units (eye spacings), then tilted and placed
            let px = x * io, py = y * io
            return CGPoint(x: center.x + px * cos(roll) - py * sin(roll), y: center.y + px * sin(roll) + py * cos(roll))
        }
        func ring(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ n: Int = 8) -> [CGPoint] {
            (0..<n).map { i in
                let a = Double(i) / Double(n) * 2 * .pi
                return at(cx + rx * cos(a), cy + ry * sin(a))
            }
        }
        func line(_ x0: Double, _ x1: Double, _ y: Double) -> [CGPoint] { (0..<5).map { at(x0 + (x1 - x0) * Double($0) / 4, y) } }

        let eyeL = ring(-0.5, 0, 0.2, 0.08), eyeR = ring(0.5, 0, 0.2, 0.08)
        let browY = browDistance
        return RawFace(leftEye: swapEyes ? eyeR : eyeL, rightEye: swapEyes ? eyeL : eyeR,
                       leftBrow: line(-0.72, -0.28, browY), rightBrow: line(0.28, 0.72, browY),
                       outerLips: ring(0, -0.95, 0.42, 0.1 + lipGap / 2), innerLips: ring(0, -0.95, 0.3, max(0.001, lipGap / 2)),
                       rect: CGRect(x: center.x - 95 * scale, y: center.y - 130 * scale, width: 190 * scale, height: 250 * scale))
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
        XCTAssertEqual(m.browDistance, 0.30, accuracy: 0.01)
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
    private func measure(x: Double = 640, lipGap: Double = 0.02, brow: Double = 0.30) -> FaceMeasure {
        FaceFeatureExtractor.measure(.synthetic(center: CGPoint(x: x, y: 400), lipGap: lipGap, browDistance: brow))!
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
