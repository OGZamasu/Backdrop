import simd
import XCTest

final class HandPoseTests: XCTestCase {
    func testMadeUpHandsAreReadAsWhatTheyAre() {
        XCTAssertEqual(HandFixtures.hand(.open).pose, .openPalm)
        XCTAssertEqual(HandFixtures.hand(.fist).pose, .fist)
        XCTAssertEqual(HandFixtures.hand(.point).pose, .point)
        XCTAssertEqual(HandFixtures.hand(.peace).pose, .peace)
        XCTAssertEqual(HandFixtures.hand(.gun).pose, .fingerGun)
        XCTAssertEqual(HandFixtures.hand(.gunFired).pose, .point, "hammer down: the thumb is in, so it is a plain point")
        XCTAssertEqual(HandFixtures.hand(.open).fingersUp, 4)
        XCTAssertEqual(HandFixtures.hand(.fist).fingersUp, 0)
        XCTAssertEqual(HandFixtures.hand(.peace).fingersUp, 2)
    }

    func testTurningOrResizingOrMirroringAHandChangesNothing() {
        for fingers in [HandFixtures.Fingers.open, .fist, .point, .peace, .gun] {
            let expected = HandFixtures.hand(fingers).pose
            for angle in stride(from: 0.0, to: 2 * Double.pi, by: .pi / 6) {
                for size in [40.0, 100, 260] {
                    for mirrored in [false, true] {
                        let h = HandFixtures.hand(fingers, size: size, angle: angle, mirrored: mirrored)
                        XCTAssertEqual(h.pose, expected, "angle \(angle) size \(size) mirrored \(mirrored)")
                    }
                }
            }
        }
    }

    func testTheThumbIsOutOrInAndNothingInBetweenConfusesIt() {
        XCTAssertGreaterThan(HandFixtures.hand(.gun).thumbOpen, 0.9)
        XCTAssertLessThan(HandFixtures.hand(.gunFired).thumbOpen, 0.1)
        XCTAssertGreaterThan(HandFixtures.hand(.open).thumbOpen, 0.9)
    }

    func testTheHandsSizeIsThePalmLengthWhereverItIs() {
        let h = HandFixtures.hand(.open, at: CGPoint(x: 100, y: 500), size: 130, angle: 0.7)
        XCTAssertEqual(h.size, 130, accuracy: 0.5)
        XCTAssertEqual(HandFixtures.hand(.point, size: 100).aimLength, 0.84, accuracy: 0.06, "an index finger is a bit under a palm long")
    }

    func testTheIndexFingerAimsWhereTheHandPoints() {
        for angle in stride(from: 0.0, to: 2 * Double.pi, by: .pi / 4) {
            let h = HandFixtures.hand(.gun, angle: angle)
            // The hand's fingers are straight up at angle 0, so its aim is up turned by `angle` (counter-clockwise).
            XCTAssertEqual(Double(h.aim.dx), -sin(angle), accuracy: 0.12)
            XCTAssertEqual(Double(h.aim.dy), cos(angle), accuracy: 0.12)
        }
    }

    func testTheLeadTipIsTheFingerThatReachesFurthest() {
        let h = HandFixtures.hand(.open, at: CGPoint(x: 600, y: 200), size: 100)
        XCTAssertEqual(Double(h.leadTip.x), Double(h[.middleTip].x), accuracy: 0.001)
        let p = HandFixtures.hand(.point, at: CGPoint(x: 600, y: 200), size: 100)
        XCTAssertEqual(Double(p.leadTip.x), Double(p.indexTip.x), accuracy: 0.001)
    }

    // MARK: What Vision actually reported

    func testHandsVisionReportedAreReadTheSameWay() {
        let open = HandFixtures.recorded(HandFixtures.Recorded.openPalm)
        XCTAssertEqual(open.pose, .openPalm)
        XCTAssertEqual(open.fingersUp, 4)

        let up = HandFixtures.recorded(HandFixtures.Recorded.pointUp)
        XCTAssertEqual(up.fingersUp, 1)
        XCTAssertTrue(up.isExtended(.index))
        XCTAssertEqual(up.pose, .fingerGun, "index out and thumb out to the side")

        let right = HandFixtures.recorded(HandFixtures.Recorded.pointRight)
        XCTAssertEqual(right.fingersUp, 1)
        XCTAssertEqual(right.pose, .fingerGun, "the closest thing to a finger gun among the emoji")
        XCTAssertEqual(Double(right.aim.dx), 1, accuracy: 0.1, "pointing right")
        XCTAssertEqual(Double(right.aim.dy), 0, accuracy: 0.15)
    }
}

final class HandSmootherTests: XCTestCase {
    private func sample(_ hands: [HandState], at time: Double) -> HandSample {
        HandSample(hands: hands.map { RawHand(joints: $0.joints) }, at: time)
    }

    func testAHandKeepsItsIdAsItMoves() {
        var smoother = HandSmoother()
        var ids: [Int] = []
        for i in 0..<20 {
            let h = HandFixtures.hand(.open, at: CGPoint(x: 300 + Double(i) * 20, y: 300))
            ids += smoother.update(sample([h], at: Double(i) * 0.04), dt: 0.04).map(\.id)
        }
        XCTAssertEqual(Set(ids).count, 1)
    }

    func testTwoHandsKeepTheirIdsEvenWhenListedInAnotherOrder() {
        var smoother = HandSmoother()
        let left = HandFixtures.hand(.open, at: CGPoint(x: 300, y: 300), mirrored: true)
        let right = HandFixtures.hand(.open, at: CGPoint(x: 900, y: 300))
        let first = smoother.update(sample([left, right], at: 0), dt: 0.04)
        XCTAssertEqual(first.count, 2)
        let idOfLeft = first.first { $0.palm.x < 640 }!.id
        let second = smoother.update(sample([right, left], at: 0.04), dt: 0.04)
        XCTAssertEqual(second.first { $0.palm.x < 640 }!.id, idOfLeft)
        XCTAssertEqual(Set(second.map(\.id)).count, 2)
    }

    func testSpeedIsWorkedOutFromTheMovementBetweenLooks() {
        var smoother = HandSmoother()
        var last: [HandState] = []
        // Moving 1000 pixels a second to the right for a while.
        for i in 0..<30 {
            let h = HandFixtures.hand(.point, at: CGPoint(x: 100 + Double(i) * 40, y: 300))
            last = smoother.update(sample([h], at: Double(i) * 0.04), dt: 0.04)
        }
        XCTAssertEqual(Double(last[0].velocity.dx), 1000, accuracy: 150)
        XCTAssertEqual(Double(last[0].velocity.dy), 0, accuracy: 30)
        XCTAssertEqual(Double(last[0].tipVelocity.dx), 1000, accuracy: 150)
    }

    func testTheSameLookSeenAgainDoesNotMoveOrSpeedUpAnything() {
        var smoother = HandSmoother()
        let a = HandFixtures.hand(.open, at: CGPoint(x: 300, y: 300))
        let b = HandFixtures.hand(.open, at: CGPoint(x: 340, y: 300))
        _ = smoother.update(sample([a], at: 0), dt: 0.033)
        let moving = smoother.update(sample([b], at: 0.04), dt: 0.033)[0]
        let again = smoother.update(sample([b], at: 0.04), dt: 0.033)[0]
        XCTAssertEqual(again.joints, moving.joints, "nothing new was measured")
        XCTAssertLessThan(abs(again.velocity.dx), abs(moving.velocity.dx), "and the speed fades rather than carrying on")
    }

    func testJointsFollowAJumpQuickly() {
        var smoother = HandSmoother()
        _ = smoother.update(sample([HandFixtures.hand(.open, at: CGPoint(x: 300, y: 300))], at: 0), dt: 0.04)
        let out = smoother.update(sample([HandFixtures.hand(.open, at: CGPoint(x: 400, y: 300))], at: 0.04), dt: 0.04)[0]
        XCTAssertGreaterThan(Double(out.wrist.x), 380, "a blade has to stay on the hand")
    }

    func testAHandThatVanishesIsHeldBrieflyThenDropped() {
        var smoother = HandSmoother()
        _ = smoother.update(sample([HandFixtures.hand(.open)], at: 0), dt: 0.04)
        XCTAssertEqual(smoother.update(nil, dt: 0.1).count, 1, "a blur in a fast swipe shouldn't lose the hand")
        XCTAssertEqual(smoother.update(nil, dt: 0.1).count, 1)
        XCTAssertEqual(smoother.update(nil, dt: 0.2).count, 0, "but not for long")
    }

    func testAHandThatComesBackIsANewOneAfterBeingDropped() {
        var smoother = HandSmoother()
        let first = smoother.update(sample([HandFixtures.hand(.open)], at: 0), dt: 0.04)[0].id
        _ = smoother.update(nil, dt: 0.5)
        let again = smoother.update(sample([HandFixtures.hand(.open)], at: 1), dt: 0.04)[0].id
        XCTAssertNotEqual(first, again)
    }

    func testAHandFarFromAnyEarlierOneIsNew() {
        var smoother = HandSmoother()
        let a = smoother.update(sample([HandFixtures.hand(.open, at: CGPoint(x: 200, y: 300))], at: 0), dt: 0.04)[0].id
        let after = smoother.update(sample([HandFixtures.hand(.open, at: CGPoint(x: 1100, y: 300))], at: 0.04), dt: 0.04)
        let b = after.first { $0.palm.x > 640 }?.id
        XCTAssertNotNil(b)
        XCTAssertNotEqual(a, b, "a different hand, not one that flew across the room in 40 ms")
    }
}

final class HandGeometryTests: XCTestCase {
    func testABladeCutsACircleItPassesThroughEvenIfItMovedPastInOneStep() {
        XCTAssertTrue(HandGeometry.segment(from: SIMD2(0, 0), to: SIMD2(400, 0), hits: SIMD2(200, 20), radius: 30), "swept right through it")
        XCTAssertFalse(HandGeometry.segment(from: SIMD2(0, 0), to: SIMD2(400, 0), hits: SIMD2(200, 60), radius: 30), "passed above it")
        XCTAssertFalse(HandGeometry.segment(from: SIMD2(0, 0), to: SIMD2(100, 0), hits: SIMD2(200, 0), radius: 30), "stopped short")
        XCTAssertTrue(HandGeometry.segment(from: SIMD2(5, 5), to: SIMD2(5, 5), hits: SIMD2(10, 5), radius: 30), "not moving, but inside")
    }

    func testARayHitsWhatItPointsAtAndNothingBehindIt() {
        let origin = SIMD2<Double>(100, 100), right = SIMD2<Double>(1, 0)
        XCTAssertEqual(HandGeometry.ray(from: origin, direction: right, hits: SIMD2(400, 110), radius: 30) ?? -1, 300, accuracy: 1)
        XCTAssertNil(HandGeometry.ray(from: origin, direction: right, hits: SIMD2(400, 200), radius: 30))
        XCTAssertNil(HandGeometry.ray(from: origin, direction: right, hits: SIMD2(0, 100), radius: 30), "behind the finger")
        XCTAssertNil(HandGeometry.ray(from: origin, direction: right, hits: SIMD2(900, 100), radius: 30, maxDistance: 500), "out of range")
    }

    func testSlackMakesDistantTargetsEasierToHit() {
        let origin = SIMD2<Double>(0, 0), right = SIMD2<Double>(1, 0)
        XCTAssertNil(HandGeometry.ray(from: origin, direction: right, hits: SIMD2(1000, 80), radius: 30))
        XCTAssertNotNil(HandGeometry.ray(from: origin, direction: right, hits: SIMD2(1000, 80), radius: 30, slack: 0.06))
        XCTAssertNil(HandGeometry.ray(from: origin, direction: right, hits: SIMD2(100, 80), radius: 30, slack: 0.06), "but close up it is still a miss")
    }

    func testARayLeavesTheFrameAtTheEdgeItHeadsFor() {
        let rect = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let out = HandGeometry.exit(from: SIMD2(640, 360), direction: SIMD2(1, 0), rect: rect)
        XCTAssertEqual(out.x, 1280, accuracy: 0.001)
        XCTAssertEqual(out.y, 360, accuracy: 0.001)
        let diagonal = HandGeometry.exit(from: SIMD2(640, 360), direction: simd_normalize(SIMD2(1, 1)), rect: rect)
        XCTAssertEqual(diagonal.y, 720, accuracy: 0.001)
    }
}

// MARK: - Gestures

final class HandGameGesturePoseTests: XCTestCase {
    func testEveryMadeUpPoseIsReadAtAnyAngleSizeAndHand() {
        let cases: [(HandFixtures.Fingers, HandGesture.Pose)] = [(.open, .openPalm), (.fist, .fist), (.point, .point), (.peace, .peace), (.gun, .fingerGun),
                                                                (.gunFired, .point), (.pinch, .pinch), (.okSign, .okSign)]
        for (fingers, expected) in cases {
            for angle in stride(from: 0.0, to: 2 * Double.pi, by: .pi / 6) {
                for size in [40.0, 100, 260] {
                    for mirrored in [false, true] {
                        let h = HandFixtures.hand(fingers, size: size, angle: angle, mirrored: mirrored)
                        XCTAssertEqual(h.gesturePose, expected, "\(fingers) angle \(angle) size \(size) mirrored \(mirrored)")
                    }
                }
            }
        }
    }

    func testAThumbsUpNeedsTheThumbUpAndAThumbsDownDown() {
        for mirrored in [false, true] {
            XCTAssertEqual(HandFixtures.thumbsUp(mirrored: mirrored).gesturePose, .thumbsUp)
            XCTAssertEqual(HandFixtures.thumbsUp(down: true, mirrored: mirrored).gesturePose, .thumbsDown)
            // The same fist held with the thumb out sideways is just a fist.
            XCTAssertEqual(HandFixtures.hand(.thumbsUp, angle: 0, mirrored: mirrored).gesturePose, .fist)
        }
        XCTAssertGreaterThan(HandFixtures.thumbsUp().thumbClearance, HandGesture.Pose.thumbOutAbove)
        XCTAssertLessThan(HandFixtures.hand(.fist).thumbClearance, 0.85)
    }

    func testTheOlderPoseIsUnchangedForTheNewShapes() {
        XCTAssertEqual(HandFixtures.thumbsUp().pose, .fist, "other lenses read a thumbs up as a fist, as before")
        XCTAssertEqual(HandGesture.Pose.thumbsUp.handPose, .fist)
        XCTAssertEqual(HandGesture.Pose.pinch.handPose, .unknown)
        for pose in HandGesture.Pose.allCases { XCTAssertGreaterThan(HandGestureRecognizer.hold(for: pose), 0) }
    }

    /// The thresholds were set on Vision's own output: every kept reading must still be read as what it is.
    func testEveryVisionReadingInTheGalleryIsReadAsWhatItShows() {
        XCTAssertGreaterThanOrEqual(HandFixtures.gallery.count, 30)
        for reading in HandFixtures.gallery {
            let hand = HandFixtures.recorded(reading)
            XCTAssertEqual(hand.gesturePose, reading.expected, reading.picture)
            // And the same at another size and place.
            XCTAssertEqual(HandFixtures.recorded(reading, at: CGPoint(x: 200, y: 500), size: 60).gesturePose, reading.expected, reading.picture)
        }
        let poses = Set(HandFixtures.gallery.map(\.expected))
        for pose in [HandGesture.Pose.openPalm, .fist, .point, .fingerGun, .peace, .thumbsUp, .thumbsDown, .pinch, .okSign] {
            XCTAssertTrue(poses.contains(pose), "the gallery has a \(pose)")
        }
    }

    func testAFingerPointedAtTheCameraLooksForeshortened() {
        var hand = HandFixtures.hand(.point)
        XCTAssertLessThan(hand.towardCamera, 0.2, "held across the picture")
        let knuckle = hand[.indexMCP]
        for joint in [HandJoint.indexPIP, .indexDIP, .indexTip] { hand.joints[joint.rawValue] = CGPoint(x: knuckle.x + 4, y: knuckle.y + 6) }
        XCTAssertGreaterThan(hand.towardCamera, 0.9, "down the lens")
    }
}

final class HandGameGestureRecognizerTests: XCTestCase {
    private let tick = 1.0 / 30

    private func run(_ recognizer: inout HandGestureRecognizer, _ frames: Int, _ hands: (Int) -> [HandState]) -> [HandGesture] {
        (0..<frames).flatMap { recognizer.update(hands($0), dt: tick) }
    }

    private func started(_ events: [HandGesture]) -> [HandGesture.Pose] {
        events.compactMap { if case .poseStarted(let p) = $0.kind { return p } else { return nil } }
    }

    func testAPoseHeldLongEnoughStartsOnce() {
        var r = HandGestureRecognizer()
        let events = run(&r, 30) { _ in [HandFixtures.hand(.open)] }
        XCTAssertEqual(started(events), [.openPalm])
        XCTAssertEqual(r.pose(of: 1), .openPalm)
        XCTAssertEqual(r.heldFor(1), 1 - HandGestureRecognizer.hold(for: .openPalm), accuracy: 0.1)
    }

    func testAOneFrameFlickerChangesNothing() {
        var r = HandGestureRecognizer()
        _ = run(&r, 10) { _ in [HandFixtures.hand(.open)] }
        let events = run(&r, 30) { $0 == 12 ? [HandFixtures.hand(.fist)] : [HandFixtures.hand(.open)] }
        XCTAssertTrue(events.isEmpty, "\(events)")
        XCTAssertEqual(r.pose(of: 1), .openPalm)
    }

    func testAThumbsUpTakesAQuarterOfASecond() {
        var r = HandGestureRecognizer()
        var frames = 0
        while r.pose(of: 1) != .thumbsUp && frames < 60 { _ = r.update([HandFixtures.thumbsUp()], dt: tick); frames += 1 }
        XCTAssertEqual(Double(frames) * tick, HandGestureRecognizer.hold(for: .thumbsUp), accuracy: 2 * tick)
    }

    func testAPointingFingerTurnedToTheCameraKeepsPointingForAMoment() {
        var r = HandGestureRecognizer()
        _ = run(&r, 10) { _ in [HandFixtures.hand(.point)] }
        XCTAssertEqual(r.pose(of: 1), .point)
        // Vision reads a finger pointed down the lens as a fist.
        _ = run(&r, 9) { _ in [HandFixtures.hand(.fist)] }
        XCTAssertEqual(r.pose(of: 1), .point, "still aiming")
        XCTAssertTrue(r.isTowardCamera(1))
        _ = run(&r, 9) { _ in [HandFixtures.hand(.fist)] }
        XCTAssertEqual(r.pose(of: 1), .fist, "but a fist held on is a fist")
        XCTAssertFalse(r.isTowardCamera(1))
    }

    func testANewPoseFromOtherShapesIsQuick() {
        var r = HandGestureRecognizer()
        _ = run(&r, 10) { _ in [HandFixtures.hand(.open)] }
        let events = run(&r, 8) { _ in [HandFixtures.hand(.fist)] }
        XCTAssertEqual(started(events), [.fist])
        XCTAssertTrue(events.contains { $0.kind == .poseEnded(.openPalm) })
    }

    func testFramesOfNothingInParticularDoNotEndAPoseAtOnce() {
        var r = HandGestureRecognizer()
        _ = run(&r, 10) { _ in [HandFixtures.hand(.open)] }
        let odd = HandFixtures.hand(HandFixtures.Fingers(index: true, middle: false, ring: true, little: false, thumb: 0))
        XCTAssertEqual(odd.gesturePose, .unknown)
        _ = run(&r, 6) { _ in [odd] }
        XCTAssertEqual(r.pose(of: 1), .openPalm)
        _ = run(&r, 12) { _ in [odd] }
        XCTAssertEqual(r.pose(of: 1), .unknown)
    }

    func testASwipeIsOneEventWithItsDirectionAndSpeed() {
        for (dx, dy, direction) in [(1.0, 0.0, HandGesture.Direction.right), (-1, 0, .left), (0, 1, .up), (0, -1, .down)] {
            var r = HandGestureRecognizer()
            let events = run(&r, 20) { i in
                let k = Double(max(0, i - 5)) * 70       // still for a moment, then 2100 pixels a second
                return [HandFixtures.hand(.open, at: CGPoint(x: 640 + dx * k - dx * 300, y: 330 + dy * k - dy * 200))]
            }
            let swipes = events.compactMap { e -> (HandGesture.Direction, Double)? in
                if case .swipe(let d, let speed) = e.kind { return (d, speed) } else { return nil }
            }
            XCTAssertEqual(swipes.count, 1, "\(direction)")
            XCTAssertEqual(swipes.first?.0, direction)
            XCTAssertEqual(swipes.first?.1 ?? 0, 2100, accuracy: 400)
        }
    }

    func testDriftingIsNotASwipe() {
        var r = HandGestureRecognizer()
        let events = run(&r, 60) { i in [HandFixtures.hand(.open, at: CGPoint(x: 300 + Double(i) * 8, y: 330))] }
        XCTAssertFalse(events.contains { if case .swipe = $0.kind { return true } else { return false } })
    }

    func testAJabOfTheFingertipIsATap() {
        var r = HandGestureRecognizer()
        let path: [Double] = [0, 0, 0, 0, 0, 25, 55, 70, 72, 72, 72, 72]
        let events = run(&r, path.count) { i in [HandFixtures.hand(.point, at: CGPoint(x: 600 + path[i], y: 300))] }
        let taps = events.filter { $0.kind == .tap }
        XCTAssertEqual(taps.count, 1)
        XCTAssertEqual(Double(taps.first?.point.x ?? 0), Double(HandFixtures.hand(.point, at: CGPoint(x: 672, y: 300)).indexTip.x), accuracy: 6)
        // Holding still or moving slowly taps nothing.
        var still = HandGestureRecognizer()
        XCTAssertTrue(run(&still, 40) { i in [HandFixtures.hand(.point, at: CGPoint(x: 600 + Double(i), y: 300))] }.filter { $0.kind == .tap }.isEmpty)
    }

    func testAPinchStartsAndEnds() {
        var r = HandGestureRecognizer()
        var events = run(&r, 6) { _ in [HandFixtures.hand(.point)] }
        events += run(&r, 6) { _ in [HandFixtures.hand(.pinch)] }
        XCTAssertEqual(events.filter { $0.kind == .pinchStarted }.count, 1)
        XCTAssertTrue(r.isPinching(1))
        events += run(&r, 6) { _ in [HandFixtures.hand(.open)] }
        XCTAssertEqual(events.filter { $0.kind == .pinchEnded }.count, 1)
        XCTAssertFalse(r.isPinching(1))
    }

    func testAHandThatLeavesEndsItsPose() {
        var r = HandGestureRecognizer()
        _ = run(&r, 10) { _ in [HandFixtures.hand(.open, id: 4)] }
        let events = r.update([], dt: tick)
        XCTAssertEqual(events.map(\.kind), [.poseEnded(.openPalm)])
        XCTAssertEqual(events.first?.hand, 4)
        XCTAssertEqual(r.pose(of: 4), .unknown)
    }

    func testTwoHandsAreReadApart() {
        var r = HandGestureRecognizer()
        _ = run(&r, 12) { _ in [HandFixtures.hand(.open, at: CGPoint(x: 300, y: 300), id: 1), HandFixtures.hand(.fist, at: CGPoint(x: 900, y: 300), id: 2)] }
        XCTAssertEqual(r.pose(of: 1), .openPalm)
        XCTAssertEqual(r.pose(of: 2), .fist)
    }

    func testAHandBeingCarriedThroughAGapKeepsItsPose() {
        var r = HandGestureRecognizer()
        _ = run(&r, 10) { _ in [HandFixtures.hand(.open)] }
        var guessed = HandFixtures.hand(.fist)
        guessed.unseenFor = 0.1
        _ = run(&r, 10) { _ in [guessed] }
        XCTAssertEqual(r.pose(of: 1), .openPalm)
    }

    func testHugeStepsAndNoHandsNeverBreakIt() {
        var r = HandGestureRecognizer()
        for i in 0..<50 { _ = r.update(i % 3 == 0 ? [] : [HandFixtures.hand(i % 2 == 0 ? .open : .pinch)], dt: i % 7 == 0 ? 5 : 0) }
        XCTAssertLessThanOrEqual(r.time, 50 * 0.5)
    }
}

// MARK: - The tracker on a real camera's troubles

final class HandGameSmootherRobustnessTests: XCTestCase {
    private func sample(_ hands: [HandState], at time: Double, confidence: Double = 1, chirality: HandState.Chirality = .unknown) -> HandSample {
        HandSample(hands: hands.map { RawHand(joints: $0.joints, chirality: chirality, confidence: confidence) }, at: time)
    }

    private func jittered(_ hand: HandState, _ rng: inout SplitMix64, amount: Double) -> HandState {
        var out = hand
        out.joints = hand.joints.map { CGPoint(x: Double($0.x) + Double.random(in: -amount...amount, using: &rng), y: Double($0.y) + Double.random(in: -amount...amount, using: &rng)) }
        return out
    }

    func testAStillHandTremblesFarLessThanTheCameraSaysItDoes() {
        var smoother = HandSmoother()
        var rng = SplitMix64(seed: 3)
        let still = HandFixtures.hand(.open, size: 100)
        var spreadIn = 0.0, spreadOut = 0.0, n = 0.0
        for i in 0..<75 {
            let seen = jittered(still, &rng, amount: 4)
            let out = smoother.update(sample([seen], at: Double(i) * 0.04), dt: 0.04)[0]
            if i > 20 {
                spreadIn += pow(Double(seen.indexTip.x - still.indexTip.x), 2)
                spreadOut += pow(Double(out.indexTip.x - still.indexTip.x), 2)
                n += 1
            }
        }
        XCTAssertLessThan((spreadOut / n).squareRoot(), 0.6 * (spreadIn / n).squareRoot(), "a resting fingertip is steadied")
    }

    func testAFastHandIsFollowedClosely() {
        var smoother = HandSmoother()
        var last: HandState?
        for i in 0..<20 {
            let h = HandFixtures.hand(.open, at: CGPoint(x: 100 + Double(i) * 60, y: 300), size: 100)      // 1500 pixels a second
            last = smoother.update(sample([h], at: Double(i) * 0.04), dt: 0.04)[0]
        }
        XCTAssertEqual(Double(last?.wrist.x ?? 0), 100 + 19 * 60, accuracy: 30, "a blade must stay on the hand")
    }

    func testOneOfTwoHandsMissingForALookKeepsBothIds() {
        var smoother = HandSmoother()
        let left = HandFixtures.hand(.open, at: CGPoint(x: 300, y: 300)), right = HandFixtures.hand(.fist, at: CGPoint(x: 900, y: 300))
        let first = smoother.update(sample([left, right], at: 0), dt: 0.04)
        let ids = Set(first.map(\.id))
        let gap = smoother.update(sample([left], at: 0.04), dt: 0.04)
        XCTAssertEqual(Set(gap.map(\.id)), ids, "the missing one is held")
        XCTAssertGreaterThan(gap.first { $0.palm.x > 640 }?.unseenFor ?? 0, 0)
        let back = smoother.update(sample([right, left], at: 0.08), dt: 0.04)
        XCTAssertEqual(Set(back.map(\.id)), ids, "and comes back as itself")
        XCTAssertEqual(back.first { $0.palm.x > 640 }?.unseenFor, 0)
    }

    func testAHandLostInAFastSwipeDriftsOnThenHolds() {
        var smoother = HandSmoother()
        for i in 0..<10 {
            _ = smoother.update(sample([HandFixtures.hand(.open, at: CGPoint(x: 200 + Double(i) * 40, y: 300))], at: Double(i) * 0.04), dt: 0.04)
        }
        let before = smoother.hands[0].wrist.x
        _ = smoother.update(nil, dt: 0.04)
        let drifting = smoother.hands[0].wrist.x
        XCTAssertGreaterThan(drifting, before + 10, "it carries on along its swing")
        for _ in 0..<3 { _ = smoother.update(nil, dt: 0.04) }
        let held = smoother.hands[0].wrist.x
        _ = smoother.update(nil, dt: 0.04)
        XCTAssertEqual(Double(smoother.hands[0].wrist.x), Double(held), accuracy: 0.5, "then holds still")
        XCTAssertLessThan(Double(held - before), 120, "and does not fly off")
    }

    func testTwoHandsPassingEachOtherKeepTheirIds() {
        var smoother = HandSmoother()
        var leftID: Int?
        for i in 0..<25 {
            let t = Double(i) * 0.04
            let a = HandFixtures.hand(.open, at: CGPoint(x: 300 + 700 * t, y: 300)), b = HandFixtures.hand(.fist, at: CGPoint(x: 1000 - 700 * t, y: 340))
            let out = smoother.update(sample(i % 2 == 0 ? [a, b] : [b, a], at: t), dt: 0.04)
            if i == 0 { leftID = out.min { $0.palm.x < $1.palm.x }?.id }
        }
        // The hand that started on the left, an open one, is now on the right with the same id.
        let open = smoother.hands.first { $0.gesturePose == .openPalm }
        XCTAssertEqual(open?.id, leftID)
        XCTAssertGreaterThan(Double(open?.palm.x ?? 0), 640)
    }

    func testAnUnsureNewHandMustBeSeenTwice() {
        var smoother = HandSmoother()
        XCTAssertTrue(smoother.update(sample([HandFixtures.hand(.open)], at: 0, confidence: 0.3), dt: 0.04).isEmpty, "one look might be a face or a knee")
        XCTAssertEqual(smoother.update(sample([HandFixtures.hand(.open)], at: 0.04, confidence: 0.3), dt: 0.04).count, 1)
        var once = HandSmoother()
        _ = once.update(sample([HandFixtures.hand(.open)], at: 0, confidence: 0.3), dt: 0.04)
        XCTAssertTrue(once.update(sample([], at: 0.04), dt: 0.04).isEmpty, "a one-look ghost never shows")
    }

    func testLeftAndRightAreDecidedByAVoteNotOneLook() {
        var smoother = HandSmoother()
        var out: [HandState] = []
        out = smoother.update(sample([HandFixtures.hand(.open)], at: 0, chirality: .left), dt: 0.04)
        XCTAssertEqual(out[0].chirality, .unknown, "one look is not enough")
        for i in 1..<6 { out = smoother.update(sample([HandFixtures.hand(.open)], at: Double(i) * 0.04, chirality: .left), dt: 0.04) }
        XCTAssertEqual(out[0].chirality, .left)
        out = smoother.update(sample([HandFixtures.hand(.open)], at: 0.3, chirality: .right), dt: 0.04)
        XCTAssertEqual(out[0].chirality, .left, "one contrary look changes nothing")
    }

    func testAJointVisionWasUnsureOfFollowsMoreSlowly() {
        var smoother = HandSmoother()
        let still = HandFixtures.hand(.open, size: 100)
        for i in 0..<10 { _ = smoother.update(sample([still], at: Double(i) * 0.04), dt: 0.04) }
        var jumped = still
        jumped.joints[HandJoint.littleTip.rawValue].x += 60
        jumped.joints[HandJoint.indexTip.rawValue].x += 60
        var confidences = [Double](repeating: 0.9, count: HandJoint.count)
        confidences[HandJoint.littleTip.rawValue] = 0.1
        let out = smoother.update(HandSample(hands: [RawHand(joints: jumped.joints, confidences: confidences)], at: 0.4), dt: 0.04)[0]
        let sure = Double(out.indexTip.x - still.indexTip.x), unsure = Double(out[.littleTip].x - still[.littleTip].x)
        XCTAssertGreaterThan(sure, 2 * unsure)
        XCTAssertEqual(out.confidence(of: .littleTip), 0.1, accuracy: 1e-9)
    }

    func testNeverMoreThanTwoHands() {
        var smoother = HandSmoother()
        let hands = [HandFixtures.hand(.open, at: CGPoint(x: 200, y: 300)), HandFixtures.hand(.open, at: CGPoint(x: 640, y: 300))]
        _ = smoother.update(sample(hands, at: 0), dt: 0.04)
        let out = smoother.update(sample([HandFixtures.hand(.open, at: CGPoint(x: 1100, y: 300)), hands[1]], at: 0.04), dt: 0.04)
        XCTAssertLessThanOrEqual(out.count, 2)
    }
}

final class HandGameVisionReadingTests: XCTestCase {
    private func confidences(_ value: Double = 0.8) -> [Double] { [Double](repeating: value, count: HandJoint.count) }

    func testAWeakFingertipKeepsTheHandAndIsFilledInAlongItsFinger() throws {
        let hand = HandFixtures.hand(.point)
        var c = confidences()
        c[HandJoint.indexTip.rawValue] = 0
        let raw = try XCTUnwrap(HandTrackingService.reading(hand.joints, confidences: c, chirality: .right))
        let filled = HandState(id: 1, joints: raw.joints)
        XCTAssertGreaterThan(filled.reach(of: .index), 1.45, "the finger still reads as out")
        XCTAssertEqual(raw.chirality, .right)
        XCTAssertEqual(raw.confidences[HandJoint.indexTip.rawValue], 0)
    }

    func testAMissingKnuckleIsPlacedBesideItsNeighbours() throws {
        let hand = HandFixtures.hand(.open)
        var c = confidences()
        c[HandJoint.ringMCP.rawValue] = 0
        var joints = hand.joints
        joints[HandJoint.ringMCP.rawValue] = .zero
        let raw = try XCTUnwrap(HandTrackingService.reading(joints, confidences: c))
        XCTAssertEqual(Double(raw.joints[HandJoint.ringMCP.rawValue].x), Double(hand[.ringMCP].x), accuracy: 15)
    }

    func testAHandWithoutAWristOrMostlyUnseenIsDropped() {
        let hand = HandFixtures.hand(.open)
        var noWrist = confidences()
        noWrist[HandJoint.wrist.rawValue] = 0
        XCTAssertNil(HandTrackingService.reading(hand.joints, confidences: noWrist))
        XCTAssertNil(HandTrackingService.reading(hand.joints, confidences: confidences(0.2)))
        XCTAssertNotNil(HandTrackingService.reading(hand.joints, confidences: confidences(0.6)))
    }
}
