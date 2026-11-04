import CoreImage
import XCTest

/// The five beam moves of the Dragon Ball lens (Kamehameha, Final Flash, Special Beam Cannon, Ki Blast, Finger Beam): each fires from its
/// pose with hands of several sizes, turned and mirrored; goes through its states; holds its charge through a tracker dropout; stays quiet
/// through the near misses of a real call; and never engages alongside another. Contact sheets of each in five forms.
final class SaiyanBeamMoveTests: XCTestCase {
    private static let forms: [SaiyanForm] = [.base, .superSaiyan, .superSaiyanGod, .superSaiyanBlue, .ultraInstinct]

    /// The five, in the router's priority order.
    private func mine() -> [SaiyanMove] { [SpecialBeamCannonMove(), KamehamehaMove(), FinalFlashMove(), KiBlastMove(), FingerBeamMove()] }

    // MARK: Driving the bench

    /// Runs a set of moves over the synthetic scene frame by frame, and counts any frame where two moves are engaged at once.
    private final class Run {
        let bench: SaiyanBench
        let set: SaiyanMoveSet
        var form: SaiyanForm
        var face = true
        var blocked = false
        private(set) var together = 0
        private(set) var frames = 0

        init(_ moves: [SaiyanMove], form: SaiyanForm = .superSaiyan, scene: SyntheticScene = SyntheticScene()) {
            bench = SaiyanBench(scene: scene)
            set = SaiyanMoveSet(moves: moves)
            self.form = form
        }

        var faceState: FaceState { bench.face! }
        var h: LensHarness { bench.h }

        func step(_ hands: [HandState], dt: Double = 1.0 / 30) {
            set.update(bench.context(hands: hands, form: form, face: face, dt: dt), blocked: blocked)
            count()
        }

        func hold(_ hands: [HandState], seconds: Double) {
            for _ in 0..<max(1, Int((seconds * 30).rounded())) { step(hands) }
        }

        /// Runs one frame and renders it at once: pictures share drawing buffers, so each must be read before the next frame.
        func picture(_ hands: [HandState]) -> CIImage {
            let out = bench.step(set, hands: hands, form: form, blocked: blocked, face: face)
            count()
            return capture(out)
        }

        func capture(_ image: CIImage) -> CIImage {
            guard let cg = bench.h.ciContext.createCGImage(image, from: bench.rect) else { return image }
            return CIImage(cgImage: cg)
        }

        /// The same scene with the hands painted in and no moves: what the picture looks like without the light.
        func plain(_ hands: [HandState]) -> CIImage { capture(bench.input(hands: hands, face: face).composed) }

        private func count() {
            frames += 1
            if set.moves.filter(\.isEngaged).count > 1 { together += 1 }
        }
    }

    // MARK: Poses

    /// A hand of `fingers` with the middle of its palm at `palm`. `angle` turns it counter-clockwise from fingers-up.
    private func place(_ fingers: HandFixtures.Fingers, palm p: CGPoint, size: Double = 110, angle: Double = 0, mirrored: Bool = false, id: Int = 1,
                       unseen: Double = 0, velocity: CGVector = .zero) -> HandState {
        let probe = HandFixtures.hand(fingers, at: .zero, size: size, angle: angle, mirrored: mirrored, id: id, velocity: velocity)
        var h = HandFixtures.moved(probe, by: CGVector(dx: p.x - probe.palm.x, dy: p.y - probe.palm.y))
        h.unseenFor = unseen
        return h
    }

    /// Kamehameha: cupped hands with the wrists together, fingers pointing out sideways (`side` +1 right, -1 left), palms facing, the upper
    /// thumb pointing down to the lower one. `gap` is palm to palm in palm lengths.
    private func cupped(at centre: CGPoint = CGPoint(x: 700, y: 190), size: Double = 110, side: Double = 1, tilt: Double = 0, gap: Double = 0.62,
                        unseen: Double = 0, velocity: CGVector = .zero) -> [HandState] {
        let angle = (side > 0 ? -Double.pi / 2 : Double.pi / 2) + tilt
        let fingers = SIMD2(-sin(angle), cos(angle))
        let up = SIMD2(-fingers.y, fingers.x) * side
        func hand(_ k: Double, mirrored: Bool, id: Int) -> HandState {
            let p = CGPoint(x: centre.x + up.x * k * gap / 2 * size, y: centre.y + up.y * k * gap / 2 * size)
            return place(.open, palm: p, size: size, angle: angle, mirrored: mirrored, id: id, unseen: unseen, velocity: velocity)
        }
        return [hand(1, mirrored: side < 0, id: 1), hand(-1, mirrored: side > 0, id: 2)]
    }

    /// Final Flash: both open palms up, side by side at the chest, facing the camera.
    private func palmsUp(at centre: CGPoint = CGPoint(x: 640, y: 200), size: Double = 110, tilt: Double = 0, gap: Double = 1.05, unseen: Double = 0) -> [HandState] {
        [place(.open, palm: CGPoint(x: centre.x - gap / 2 * size, y: centre.y), size: size, angle: tilt, mirrored: true, id: 1, unseen: unseen),
         place(.open, palm: CGPoint(x: centre.x + gap / 2 * size, y: centre.y), size: size, angle: -tilt, id: 2, unseen: unseen)]
    }

    /// Index and middle fingers held to the forehead.
    private func atForehead(_ face: FaceState, size: Double = 110, angle: Double = 0.15, mirrored: Bool = false, id: Int = 1, unseen: Double = 0) -> HandState {
        let probe = HandFixtures.hand(.peace, at: .zero, size: size, angle: angle, mirrored: mirrored, id: id)
        let tips = SaiyanBeamHands.twoTips(probe)
        var h = HandFixtures.moved(probe, by: CGVector(dx: face.forehead.x - tips.x, dy: face.forehead.y - tips.y))
        h.unseenFor = unseen
        return h
    }

    /// A finger pointing along `heading` (radians), palm at `p`.
    private func pointing(at p: CGPoint, heading: Double, size: Double = 110, fingers: HandFixtures.Fingers = .point, mirrored: Bool = false, id: Int = 1,
                          unseen: Double = 0, velocity: CGVector = .zero) -> HandState {
        place(fingers, palm: p, size: size, angle: heading - .pi / 2, mirrored: mirrored, id: id, unseen: unseen, velocity: velocity)
    }

    /// The scaled copies of a pose for a push at the camera: the hands growing by `growth` over `frames`, about the middle between them.
    private func growing(_ make: (Double) -> [HandState], from size: Double, growth: Double, frames: Int) -> [[HandState]] {
        (1...frames).map { i in make(size * pow(growth, Double(i) / Double(frames))) }
    }

    // MARK: Looking at the picture

    private func brightness(_ p: RGB) -> Int { p.r + p.g + p.b }

    /// Points along the middle of a beam, from `from` to `to` of its length.
    private func along(_ look: SaiyanBeamLook, from: Double = 0.25, to: Double = 0.9, count: Int = 6) -> [CGPoint] {
        (0..<count).map { i in
            let k = from + (to - from) * Double(i) / Double(max(1, count - 1))
            let x = look.tail + (look.head - look.tail) * k
            return CGPoint(x: look.origin.x + cos(look.angle) * x, y: look.origin.y + sin(look.angle) * x)
        }
    }

    /// Checks the beam lights the picture along its whole length, far above the plain scene.
    private func assertLit(_ run: Run, _ out: CIImage, _ look: SaiyanBeamLook, hands: [HandState], _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let plain = run.plain(hands)
        for p in along(look) where run.bench.rect.insetBy(dx: 2, dy: 2).contains(p) {
            let lit = brightness(run.h.pixel(out, Int(p.x), Int(p.y))), before = brightness(run.h.pixel(plain, Int(p.x), Int(p.y)))
            XCTAssertGreaterThan(lit - before, 180, "\(what): the beam lights the picture at \(p)", file: file, line: line)
        }
    }

    /// The average colour of the beam's body (outside its white core) halfway along it.
    private func bodyColour(_ run: Run, _ out: CIImage, _ look: SaiyanBeamLook) -> (r: Double, g: Double, b: Double) {
        let mid = along(look, from: 0.55, to: 0.55, count: 1)[0]
        let off = look.width * 0.42, r = max(2, look.width * 0.05)
        let p = CGPoint(x: mid.x - sin(look.angle) * off, y: mid.y + cos(look.angle) * off)
        return run.h.average(out, CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    // MARK: Thresholds against the fixtures

    func testThresholdsSitBetweenTheFixturePoses() {
        func open(_ f: HandFixtures.Fingers, angle: Double = 0, mirrored: Bool = false, size: Double = 110) -> HandState {
            HandFixtures.hand(f, size: size, angle: angle, mirrored: mirrored)
        }
        for size in [70.0, 110, 160] {
            for mirrored in [false, true] {
                // Kamehameha: open and cupped hands are open enough; a pointing finger and a fist are not.
                XCTAssertGreaterThan(HandFXPose.openness(open(.open, size: size)), KamehamehaMove.openAbove)
                XCTAssertGreaterThan(HandFXPose.openness(open(.peace, mirrored: mirrored, size: size)), KamehamehaMove.openAbove)
                XCTAssertLessThan(HandFXPose.openness(open(.point, mirrored: mirrored, size: size)), KamehamehaMove.openAbove)
                XCTAssertLessThan(HandFXPose.openness(open(.fist, mirrored: mirrored, size: size)), KamehamehaMove.openAbove)
                // Sideways within the Kamehameha's limit even turned half a radian; fingers up never are.
                for tilt in [-0.5, 0, 0.5] {
                    XCTAssertLessThan(SaiyanZones.fingerElevation(open(.open, angle: -.pi / 2 + tilt, mirrored: mirrored, size: size)), KamehamehaMove.sidewaysWithin)
                    XCTAssertGreaterThan(SaiyanZones.fingerElevation(open(.open, angle: tilt, mirrored: mirrored, size: size)), FinalFlashMove.upAbove)
                }
                // Final Flash wants open hands: an OK sign is open, a peace sign is not.
                XCTAssertGreaterThan(HandFXPose.openness(open(.okSign, mirrored: mirrored, size: size)), FinalFlashMove.openAbove)
                XCTAssertLessThan(HandFXPose.openness(open(.peace, mirrored: mirrored, size: size)), FinalFlashMove.openAbove)
                // A finger across the picture is long enough to aim; a pinch's bent finger is not taken for a point.
                XCTAssertGreaterThan(open(.point, mirrored: mirrored, size: size).aimLength, FingerBeamMove.aimLengthAbove)
                XCTAssertFalse(open(.pinch, mirrored: mirrored, size: size).gesturePose.isPointing)
            }
        }
        // Vision's readings: a finger pointed at the camera never reads as a point that is long enough to aim along.
        for r in HandFixtures.gallery where r.picture.hasPrefix("🫵") {
            let h = HandFixtures.recorded(r, size: 120)
            XCTAssertFalse(h.gesturePose.isPointing && h.aimLength > FingerBeamMove.aimLengthAbove, r.picture)
        }
        // Vision's open hands are open; its fists, thumbs and pinches are not open enough for Final Flash.
        for r in HandFixtures.gallery {
            let h = HandFixtures.recorded(r, size: 120), o = HandFXPose.openness(h)
            switch r.expected {
            case .openPalm: XCTAssertGreaterThan(o, FinalFlashMove.openAbove, r.picture)
            case .fist, .thumbsUp, .thumbsDown, .pinch, .point, .fingerGun: XCTAssertLessThan(o, KamehamehaMove.openAbove, r.picture)
            default: break
            }
        }
    }

    // MARK: Kamehameha

    func testKamehamehaChantsChargesAndFiresAcrossThePicture() {
        let run = Run(mine())
        let kame = run.set.moves[1] as! KamehamehaMove
        let pose = cupped()
        run.hold(pose, seconds: 0.15)
        XCTAssertFalse(kame.isEngaged, "not on the first moments of a pose")
        run.hold(pose, seconds: 0.15)
        XCTAssertTrue(kame.isEngaged)
        XCTAssertEqual(run.set.status?.title, "Ka...")
        run.hold(pose, seconds: 0.6)
        XCTAssertTrue(kame.hasLight, "the orb has started")
        let early = kame.orbRadius
        run.hold(pose, seconds: 0.5)
        XCTAssertGreaterThan(kame.orbRadius, early, "and grows")
        XCTAssertEqual(run.set.status?.title, "ha...")
        run.hold(pose, seconds: 1.4)
        XCTAssertEqual(kame.charge, 1, accuracy: 1e-9)
        XCTAssertEqual(run.set.status?.title, "Release!")
        XCTAssertEqual(kame.orbRadius, KamehamehaMove.radius(charge: 1, size: 110, power: SaiyanForm.superSaiyan.power), accuracy: 2)
        XCTAssertGreaterThan(kame.orbRadius, 0.55 * 110, "about 1.2 palm lengths across when full")
        let charged = run.picture(pose)
        Output.save(charged, as: "beam-kamehameha-charged.png")

        // Thrust both hands out along the fingers.
        var hands = pose
        for i in 1...4 { hands = cupped(at: CGPoint(x: 700 + Double(i) * 28, y: 190)); run.step(hands) }
        XCTAssertTrue(kame.isFiring)
        XCTAssertEqual(kame.lastTrigger, "thrust")
        XCTAssertEqual(run.set.status?.title, "Kamehameha!")
        XCTAssertGreaterThan(run.set.screenEffect.shake, 0.2, "it kicks")
        run.hold(hands, seconds: 0.4)
        let out = run.picture(hands)
        Output.save(out, as: "beam-kamehameha-fire.png")
        guard let look = kame.beam else { return XCTFail("no beam") }
        XCTAssertLessThan(abs(look.angle), 0.31, "it flies sideways, the way the fingers point")
        XCTAssertEqual(look.head + look.origin.x, 1280, accuracy: 4, "all the way to the edge")
        assertLit(run, out, look, hands: hands, "Kamehameha")
        // The splash at the edge.
        let edge = run.h.pixel(out, 1276, Int(look.origin.y))
        XCTAssertGreaterThan(brightness(edge), 600, "a hot splash where it meets the edge")

        // It pours for a while, then runs out and the picture is clean again.
        run.hold(hands, seconds: 1.0)
        XCTAssertTrue(kame.hasLight)
        run.hold([], seconds: 3)
        XCTAssertFalse(kame.isEngaged)
        XCTAssertFalse(kame.hasLight)
        XCTAssertTrue(run.set.screenEffect.isNone)
        XCTAssertEqual(run.together, 0)
    }

    func testKamehamehaFiresFromEveryWayOfPushing() {
        // Pushed at the camera: the hands grow.
        var run = Run(mine())
        var kame = run.set.moves[1] as! KamehamehaMove
        run.hold(cupped(), seconds: 1.3)
        for hands in growing({ self.cupped(size: $0) }, from: 110, growth: 1.35, frames: 5) { run.step(hands) }
        XCTAssertTrue(kame.isFiring)
        XCTAssertEqual(kame.lastTrigger, "push")

        // Sprung apart.
        run = Run(mine())
        kame = run.set.moves[1] as! KamehamehaMove
        run.hold(cupped(), seconds: 1.3)
        for i in 1...4 { run.step(cupped(gap: 0.62 + Double(i) * 0.5)) }
        XCTAssertTrue(kame.isFiring)
        XCTAssertEqual(kame.lastTrigger, "apart")

        // Not before there is enough charge: a quick pose and push fires nothing.
        run = Run(mine())
        kame = run.set.moves[1] as! KamehamehaMove
        run.hold(cupped(), seconds: 0.5)
        for i in 1...4 { run.step(cupped(at: CGPoint(x: 700 + Double(i) * 28, y: 190))) }
        XCTAssertEqual(kame.fired, 0, "a pose barely held is not enough")
    }

    func testKamehamehaFiresWithHandsOfEverySizeTurnAndSide() {
        for size in [80.0, 110, 145] {
            for side in [1.0, -1.0] {
                for tilt in [0.0, 0.32, -0.3] {
                    let run = Run(mine())
                    let kame = run.set.moves[1] as! KamehamehaMove
                    let centre = CGPoint(x: 640 + side * 70, y: 200)
                    run.hold(cupped(at: centre, size: size, side: side, tilt: tilt), seconds: 1.4)
                    let what = "size \(size), side \(side), tilt \(tilt)"
                    XCTAssertTrue(kame.isEngaged, what)
                    let dir = SIMD2(-sin((side > 0 ? -Double.pi / 2 : Double.pi / 2) + tilt), cos((side > 0 ? -Double.pi / 2 : Double.pi / 2) + tilt))
                    for i in 1...4 {
                        let shift = Double(i) * 0.25 * size
                        run.step(cupped(at: CGPoint(x: centre.x + dir.x * shift, y: centre.y + dir.y * shift), size: size, side: side, tilt: tilt))
                    }
                    XCTAssertTrue(kame.isFiring, what)
                    guard let look = kame.beam else { XCTFail(what); continue }
                    XCTAssertGreaterThan(cos(look.angle) * side, 0.9, "\(what): toward the side the fingers point, near level")
                    XCTAssertEqual(run.together, 0, what)
                }
            }
        }
    }

    // MARK: Final Flash

    func testFinalFlashGlowsOnBothPalmsAndBlastsAWideBeamWhenPushed() {
        let run = Run(mine())
        let flash = run.set.moves[2] as! FinalFlashMove
        let pose = palmsUp()
        run.hold(pose, seconds: 0.25)
        XCTAssertFalse(flash.isEngaged, "not on the first moments of a pose")
        run.hold(pose, seconds: 0.15)
        XCTAssertTrue(flash.isEngaged, "both palms up at the chest")
        XCTAssertTrue(flash.hasLight, "the palms begin to glow")
        run.hold(pose, seconds: 1.0)
        XCTAssertGreaterThan(flash.charge, 0.4)
        XCTAssertGreaterThan(flash.sphereRadius, 20, "a sphere gathers in front of the palms")
        XCTAssertEqual(run.set.status?.title, "Charging Final Flash...")
        run.hold(pose, seconds: 1.0)
        let charged = run.picture(pose)
        Output.save(charged, as: "beam-finalflash-charged.png")
        XCTAssertEqual(run.set.status?.title, "Final Flash ready")

        var hands = pose
        for frame in growing({ self.palmsUp(size: $0) }, from: 110, growth: 1.3, frames: 5) { hands = frame; run.step(hands) }
        XCTAssertTrue(flash.isFiring)
        XCTAssertGreaterThan(run.set.screenEffect.flash, 0.2, "a big flash")
        run.hold(hands, seconds: 0.4)
        let out = run.picture(hands)
        Output.save(out, as: "beam-finalflash-fire.png")
        guard let look = flash.beam else { return XCTFail("no beam") }
        XCTAssertEqual(abs(cos(look.angle)), 1, accuracy: 1e-6, "straight out sideways")
        XCTAssertGreaterThan(look.width, 150, "very wide")
        assertLit(run, out, look, hands: hands, "Final Flash")
        let colour = bodyColour(run, out, look)
        XCTAssertGreaterThan(colour.r, colour.b + 0.15, "yellow-white, got \(colour)")
        run.hold([], seconds: 3.5)
        XCTAssertFalse(flash.hasLight)
        XCTAssertTrue(run.set.screenEffect.isNone)
        XCTAssertEqual(run.together, 0)
    }

    func testFinalFlashFiresWithPalmsOfEverySizeAndLean() {
        for size in [85.0, 110, 140] {
            for tilt in [0.0, 0.3, -0.25] {
                for x in [560.0, 760] {
                    let run = Run(mine())
                    let flash = run.set.moves[2] as! FinalFlashMove
                    let centre = CGPoint(x: x, y: 190)
                    run.hold(palmsUp(at: centre, size: size, tilt: tilt), seconds: 1.2)
                    for frame in growing({ self.palmsUp(at: centre, size: $0, tilt: tilt) }, from: size, growth: 1.3, frames: 5) { run.step(frame) }
                    let what = "size \(size), lean \(tilt), at \(x)"
                    XCTAssertTrue(flash.isFiring, what)
                    if let look = flash.beam {
                        XCTAssertEqual(cos(look.angle) > 0, x > 640, "\(what): away from the middle of you")
                    }
                    XCTAssertEqual(run.together, 0, what)
                }
            }
        }
    }

    // MARK: Special Beam Cannon

    func testSpecialBeamCannonWaitsOutInstantTransmissionThenDrillsAcross() {
        let run = Run(mine())
        let cannon = run.set.moves[0] as! SpecialBeamCannonMove
        let touch = atForehead(run.faceState)
        XCTAssertTrue(SaiyanZones.fingersAtForehead(touch, run.faceState))
        // Nothing at all before the Instant Transmission limit.
        for _ in 0..<17 {
            run.step([touch])
            XCTAssertFalse(cannon.isEngaged)
            XCTAssertFalse(cannon.hasLight)
        }
        run.hold([touch], seconds: 0.15)
        XCTAssertTrue(cannon.isEngaged, "held past the limit, it charges")
        run.hold([touch], seconds: 1.5)
        XCTAssertEqual(cannon.charge, 1, accuracy: 1e-9)
        let charged = run.picture([touch])
        Output.save(charged, as: "beam-cannon-charged.png")
        XCTAssertEqual(run.set.status?.title, "Special Beam Cannon ready")

        // Pull away and point out to the right.
        let out1 = pointing(at: CGPoint(x: 800, y: 420), heading: 0.1, fingers: .peace)
        run.hold([out1], seconds: 0.4)
        XCTAssertTrue(cannon.isFiring, "pointing out fires it")
        let out = run.picture([out1])
        Output.save(out, as: "beam-cannon-fire.png")
        guard let look = cannon.beam else { return XCTFail("no beam") }
        XCTAssertEqual(look.angle, atan2(Double(out1.aim.dy), Double(out1.aim.dx)), accuracy: 0.05, "along the fingers")
        XCTAssertLessThan(look.width, 40, "thin")
        assertLit(run, out, look, hands: [out1], "Special Beam Cannon")
        run.hold([], seconds: 3)
        XCTAssertFalse(cannon.hasLight)
        XCTAssertEqual(run.together, 0)
    }

    func testSpecialBeamCannonFiresFromEitherHandTurnedAndSizedAndATiltedHead() {
        for roll in [0.0, 0.3] {
            for mirrored in [false, true] {
                for size in [90.0, 130] {
                    var scene = SyntheticScene()
                    scene.roll = roll
                    let run = Run(mine(), scene: scene)
                    let cannon = run.set.moves[0] as! SpecialBeamCannonMove
                    let touch = atForehead(run.faceState, size: size, angle: (mirrored ? -0.2 : 0.2) + roll, mirrored: mirrored)
                    run.hold([touch], seconds: 1.2)
                    let what = "roll \(roll), mirrored \(mirrored), size \(size)"
                    XCTAssertTrue(cannon.isEngaged, what)
                    let side = mirrored ? -1.0 : 1.0
                    let away = pointing(at: CGPoint(x: 640 + side * 180, y: 380), heading: mirrored ? .pi - 0.15 : 0.15, size: size, fingers: .point, mirrored: mirrored)
                    run.hold([away], seconds: 0.3)
                    XCTAssertTrue(cannon.isFiring, what)
                    if let look = cannon.beam { XCTAssertGreaterThan(cos(look.angle) * side, 0.8, what) }
                }
            }
        }
    }

    // MARK: Ki Blast

    func testKiBlastLeavesAPushedPalmAndRapidFires() {
        let run = Run(mine())
        let ki = run.set.moves[3] as! KiBlastMove
        let at = CGPoint(x: 760, y: 260)
        run.hold([place(.open, palm: at, size: 100)], seconds: 0.5)
        XCTAssertEqual(ki.fired, 0, "a palm held up does nothing")
        var out = run.capture(run.bench.input().composed)
        for frame in growing({ [self.place(.open, palm: at, size: $0)] }, from: 100, growth: 1.36, frames: 6) { out = run.picture(frame) }
        XCTAssertEqual(ki.fired, 1)
        XCTAssertTrue(ki.isEngaged)
        XCTAssertEqual(run.set.status?.title, "Ki Blast!")
        let pushed = place(.open, palm: at, size: 136)
        for _ in 0..<5 { out = run.picture([pushed]) }
        Output.save(out, as: "beam-kiblast-flight.png")
        guard let blast = ki.blasts.first else { return XCTFail("no blast") }
        XCTAssertGreaterThan(blast.position.x, at.x + 60, "it flies away from you, to the right")
        XCTAssertLessThan(abs(blast.direction.y), 0.25)
        // A glowing yellow ball where it is.
        let p = run.h.pixel(out, Int(blast.position.x), Int(blast.position.y))
        XCTAssertGreaterThan(brightness(p), 600)
        run.hold([pushed], seconds: 0.5)
        XCTAssertEqual(ki.landed, 1, "it bursts at the edge")

        // Pull back and push again, quickly, four times: several in the air at once.
        var most = 0
        for _ in 0..<4 {
            for frame in growing({ [self.place(.open, palm: at, size: $0)] }, from: 136, growth: 1 / 1.36, frames: 3) { run.step(frame) }
            for frame in growing({ [self.place(.open, palm: at, size: $0)] }, from: 100, growth: 1.36, frames: 4) { run.step(frame); most = max(most, ki.blasts.count) }
        }
        XCTAssertEqual(ki.fired, 5)
        XCTAssertGreaterThanOrEqual(most, 2, "rapid fire")
        XCTAssertLessThanOrEqual(most, KiBlastMove.most)
        run.hold([], seconds: 2)
        XCTAssertFalse(ki.hasLight)
        XCTAssertTrue(run.set.screenEffect.isNone)
        XCTAssertEqual(run.together, 0)
    }

    func testKiBlastFiresFromEitherHandAnySizeAndGoesTheWayItIsSent() {
        for size in [80.0, 125] {
            for (x, mirrored) in [(300.0, true), (980.0, false)] {
                for tilt in [0.0, 0.35] {
                    let run = Run(mine())
                    let ki = run.set.moves[3] as! KiBlastMove
                    let at = CGPoint(x: x, y: 250)
                    run.hold([place(.open, palm: at, size: size, angle: tilt, mirrored: mirrored)], seconds: 0.4)
                    for frame in growing({ [self.place(.open, palm: at, size: $0, angle: tilt, mirrored: mirrored)] }, from: size, growth: 1.35, frames: 6) {
                        run.step(frame)
                    }
                    let what = "size \(size), at \(x), tilt \(tilt)"
                    XCTAssertEqual(ki.fired, 1, what)
                    if let b = ki.blasts.first { XCTAssertEqual(b.direction.x > 0, x > 640, "\(what): away from you") }
                }
            }
        }
        // A push that also sweeps across the picture sends it that way, even toward the far side.
        let run = Run(mine())
        let ki = run.set.moves[3] as! KiBlastMove
        run.hold([place(.open, palm: CGPoint(x: 900, y: 250), size: 100)], seconds: 0.4)
        for (i, s) in [104.0, 110, 117, 124, 131, 138].enumerated() { run.step([place(.open, palm: CGPoint(x: 900 - Double(i + 1) * 14, y: 250), size: s)]) }
        XCTAssertEqual(ki.fired, 1)
        XCTAssertLessThan(ki.blasts.first?.direction.x ?? 1, 0, "sent left, the way the palm went")
    }

    // MARK: Finger Beam

    func testFingerBeamBuildsASparkThenPiercesAndLastsWhileHeld() {
        let run = Run(mine())
        let finger = run.set.moves[4] as! FingerBeamMove
        let hand = pointing(at: CGPoint(x: 820, y: 300), heading: 0.15)
        run.hold([hand], seconds: 0.35)
        XCTAssertTrue(finger.isEngaged, "held still, it aims")
        XCTAssertTrue(finger.hasLight, "a spark at the fingertip")
        XCTAssertFalse(finger.isFiring)
        XCTAssertEqual(run.set.status?.title, "Hold still...")
        let aiming = run.picture([hand])
        Output.save(aiming, as: "beam-finger-spark.png")
        run.hold([hand], seconds: 0.45)
        XCTAssertTrue(finger.isFiring)
        XCTAssertEqual(run.set.status?.title, "Finger Beam!")
        run.hold([hand], seconds: 0.3)
        let out = run.picture([hand])
        Output.save(out, as: "beam-finger-fire.png")
        guard let look = finger.beam else { return XCTFail("no beam") }
        XCTAssertEqual(look.angle, atan2(Double(hand.aim.dy), Double(hand.aim.dx)), accuracy: 0.05, "along the finger")
        XCTAssertLessThan(look.width, 30, "thin")
        XCTAssertEqual(look.origin.x + cos(look.angle) * look.head, 1280, accuracy: 4, "to the edge")
        assertLit(run, out, look, hands: [hand], "Finger Beam")
        let colour = bodyColour(run, out, look)
        XCTAssertGreaterThan(colour.r, colour.g + 0.1, "magenta, got \(colour)")
        XCTAssertGreaterThan(colour.b, colour.g + 0.1, "magenta, got \(colour)")

        // It lasts while held, at most two seconds, and once spent the finger must drop before it fires again.
        run.hold([hand], seconds: 2.0)
        XCTAssertFalse(finger.isFiring, "no longer than two seconds")
        XCTAssertFalse(finger.isEngaged)
        run.hold([hand], seconds: 1.5)
        XCTAssertEqual(finger.fired, 1, "held on, it does not fire again")
        run.hold([], seconds: 1)
        XCTAssertFalse(finger.hasLight)
        run.hold([hand], seconds: 1)
        XCTAssertEqual(finger.fired, 2, "pointed again, it fires again")

        // Lowering the hand stops it.
        run.hold([], seconds: 0.5)
        XCTAssertFalse(finger.isFiring)
        XCTAssertEqual(run.together, 0)
    }

    func testFingerBeamFiresFromEitherHandAndAFingerGun() {
        for size in [80.0, 130] {
            for (x, heading, mirrored) in [(820.0, 0.2, false), (460.0, Double.pi - 0.1, true)] {
                for fingers in [HandFixtures.Fingers.point, .gun] {
                    let run = Run(mine())
                    let finger = run.set.moves[4] as! FingerBeamMove
                    run.hold([pointing(at: CGPoint(x: x, y: 300), heading: heading, size: size, fingers: fingers, mirrored: mirrored)], seconds: 1.0)
                    let what = "size \(size), heading \(heading)"
                    XCTAssertTrue(finger.isFiring, what)
                    if let look = finger.beam { XCTAssertEqual(cos(look.angle), cos(heading), accuracy: 0.06, what) }
                }
            }
        }
    }

    // MARK: Colour and strength by form

    func testFormsTintTheBeamsAndPowerMakesThemBigger() {
        func kamehameha(_ form: SaiyanForm) -> (look: SaiyanBeamLook?, colour: (r: Double, g: Double, b: Double)) {
            let run = Run(mine(), form: form)
            let kame = run.set.moves[1] as! KamehamehaMove
            run.hold(cupped(), seconds: 2.6)
            var hands = cupped()
            for i in 1...4 { hands = cupped(at: CGPoint(x: 700 + Double(i) * 28, y: 190)); run.step(hands) }
            run.hold(hands, seconds: 0.5)
            let out = run.picture(hands)
            Output.save(out, as: "beam-kamehameha-\(form.shortTitle.lowercased().replacingOccurrences(of: " ", with: "-")).png")
            guard let look = kame.beam else { return (nil, (0, 0, 0)) }
            return (look, bodyColour(run, out, look))
        }
        let base = kamehameha(.base), ssj = kamehameha(.superSaiyan), god = kamehameha(.superSaiyanGod), blue = kamehameha(.superSaiyanBlue),
            ui = kamehameha(.ultraInstinct)
        XCTAssertGreaterThan(base.colour.b, base.colour.r + 0.12, "base: blue-white, got \(base.colour)")
        XCTAssertGreaterThan(god.colour.r, god.colour.b + 0.05, "God turns it red, got \(god.colour)")
        XCTAssertGreaterThan(blue.colour.b, blue.colour.r + 0.12, "Blue keeps it vivid cyan, got \(blue.colour)")
        XCTAssertLessThan(abs(ui.colour.r - ui.colour.b), 0.2, "Ultra Instinct makes it silver, got \(ui.colour)")
        let widths = [base, ssj, ui].map { $0.look?.width ?? 0 }
        XCTAssertLessThan(widths[0], widths[1], "a Super Saiyan beam is bigger than a base one")
        XCTAssertLessThan(widths[1] * 1.2, widths[2], "and Ultra Instinct bigger still")
        XCTAssertGreaterThan(ui.look?.crackle ?? 0, base.look?.crackle ?? 0, "and crackles more")
    }

    // MARK: Near misses

    /// Runs frames of hands through the five and checks nothing begins, nothing is drawn and the screen is left alone.
    private func assertQuiet(_ name: String, _ frames: [[HandState]], face: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        let run = Run(mine())
        run.face = face
        for (i, hands) in frames.enumerated() {
            run.step(hands)
            if let move = run.set.engaged { return XCTFail("\(name): \(move.id) began at frame \(i)", file: file, line: line) }
            if run.set.hasLight { return XCTFail("\(name): light at frame \(i)", file: file, line: line) }
            if !run.set.screenEffect.isNone { return XCTFail("\(name): the screen moved at frame \(i)", file: file, line: line) }
        }
    }

    func testNearMissesOfARealCallStayQuiet() {
        let seconds = 90
        // Waving hello: a palm rocking side to side at about two waves a second (up to 5 palm lengths a second), turning as it goes.
        assertQuiet("a wave", (0..<seconds).map { i in
            let t = Double(i) / 30, s = sin(t * 2 * .pi * 1.8)
            return [place(.open, palm: CGPoint(x: 900 + 55 * s, y: 400), size: 110 * (1 + 0.03 * sin(t * 7)), angle: 0.4 * s, id: 1,
                          velocity: CGVector(dx: 55 * 2 * .pi * 1.8 * cos(t * 2 * .pi * 1.8), dy: 0))]
        })
        // One cupped hand at the side, alone.
        assertQuiet("one hand", Array(repeating: [cupped()[0]], count: seconds))
        // A single fist, and both fists (the power-up, which is the body's business).
        assertQuiet("a fist", Array(repeating: [place(.fist, palm: CGPoint(x: 900, y: 250))], count: seconds))
        assertQuiet("two fists", Array(repeating: [place(.fist, palm: CGPoint(x: 560, y: 220), id: 1), place(.fist, palm: CGPoint(x: 720, y: 220), id: 2)],
                                       count: seconds))
        // An open palm resting, low and still; a hand held up by the face while talking; both palms low and apart (the power-down).
        assertQuiet("an open palm resting", Array(repeating: [place(.open, palm: CGPoint(x: 900, y: 200))], count: seconds))
        assertQuiet("a hand up while talking", (0..<seconds).map { i in
            let t = Double(i) / 30
            return [place(.open, palm: CGPoint(x: 780 + 10 * sin(t * 5), y: 430 + 8 * sin(t * 3)), size: 110 * (1 + 0.05 * sin(t * 4)), angle: 0.2 * sin(t * 2))]
        })
        assertQuiet("both palms low and apart", Array(repeating: [place(.open, palm: CGPoint(x: 420, y: 130), id: 1),
                                                                  place(.open, palm: CGPoint(x: 860, y: 130), id: 2)], count: seconds))
        // Hands together, but away from where the moves are made: above the head, in front of the face, off at the far side, or no face.
        assertQuiet("cupped hands above the head", Array(repeating: cupped(at: CGPoint(x: 640, y: 650)), count: seconds))
        assertQuiet("palms up in front of the face", Array(repeating: palmsUp(at: CGPoint(x: 640, y: 400)), count: seconds))
        assertQuiet("palms up off to the side", Array(repeating: palmsUp(at: CGPoint(x: 140, y: 120)), count: seconds))
        assertQuiet("cupped hands with no face", Array(repeating: cupped(), count: seconds), face: false)
        // Pointing while gesturing: the finger moving and turning.
        assertQuiet("pointing while talking", (0..<seconds).map { i in
            let t = Double(i) / 30
            let x = 820 + 40 * sin(t * 6), vx = 40 * 6 * cos(t * 6)
            return [pointing(at: CGPoint(x: x, y: 300), heading: 0.3 * sin(t * 4), velocity: CGVector(dx: vx, dy: 0))]
        })
        // A finger raised ("one thing...") held still: pointing up, not out.
        assertQuiet("a finger raised", Array(repeating: [pointing(at: CGPoint(x: 820, y: 330), heading: .pi / 2 - 0.2)], count: seconds))
        // A hand crossing the frame.
        assertQuiet("a hand crossing", (0..<seconds).map { i in
            [place(.open, palm: CGPoint(x: 80 + Double(i) * 13, y: 300), angle: -0.3, velocity: CGVector(dx: 390, dy: 0))]
        })
        // Resting by the face: two fingers at the temple while thinking, a fist under the chin.
        let face0 = SaiyanBench().face!
        let temple = HandFixtures.hand(.peace, at: .zero, size: 110, angle: 0.5)
        let templeTips = SaiyanBeamHands.twoTips(temple)
        let atTemple = HandFixtures.moved(temple, by: CGVector(dx: face0.eyeCenter.x + 0.8 * face0.interocular - templeTips.x,
                                                               dy: face0.eyeCenter.y + 0.3 * face0.interocular - templeTips.y))
        XCTAssertFalse(SaiyanZones.fingersAtForehead(atTemple, face0))
        assertQuiet("two fingers at the temple", Array(repeating: [atTemple], count: seconds))
        assertQuiet("a fist under the chin", Array(repeating: [place(.fist, palm: CGPoint(x: 650, y: 290), angle: 0.3)], count: seconds))
        // Fingers at the forehead for less than the Instant Transmission limit, then pointing out: Instant Transmission's, not ours.
        let face = SaiyanBench().face!
        let brief = Array(repeating: [atForehead(face)], count: 16)
        let then = Array(repeating: [pointing(at: CGPoint(x: 800, y: 420), heading: 0.1, fingers: .peace)], count: 10)
        assertQuiet("a quick touch of the forehead", brief + then + Array(repeating: [], count: 20))
    }

    func testPointingWhileMovingNeverFiresTheFingerBeamButHoldingStillDoes() {
        let run = Run(mine())
        let finger = run.set.moves[4] as! FingerBeamMove
        // Moving at 2.5 palm lengths a second: never.
        for i in 0..<120 {
            let t = Double(i) / 30
            run.step([pointing(at: CGPoint(x: 820 + 60 * sin(t * 4.6), y: 300), heading: 0.1, velocity: CGVector(dx: 60 * 4.6 * cos(t * 4.6), dy: 0))])
            XCTAssertFalse(finger.isFiring)
        }
        XCTAssertEqual(finger.fired, 0)
        // The moment it holds still, it aims and fires.
        run.hold([pointing(at: CGPoint(x: 820, y: 300), heading: 0.1)], seconds: 1)
        XCTAssertEqual(finger.fired, 1)
    }

    // MARK: Robustness

    func testATrackerDropoutHoldsTheCharge() {
        // Kamehameha: one hand lost for 0.2 s, then both carried through a blur for 0.2 s.
        let run = Run(mine())
        let kame = run.set.moves[1] as! KamehamehaMove
        run.hold(cupped(), seconds: 1.3)
        let before = kame.charge
        XCTAssertGreaterThan(before, 0.4)
        run.hold([cupped()[0]], seconds: 0.2)
        XCTAssertTrue(kame.isEngaged)
        XCTAssertEqual(kame.charge, before, accuracy: 0.01, "a hand lost for a moment keeps the charge")
        XCTAssertTrue(kame.hasLight, "and the orb stays")
        run.hold(cupped(unseen: 0.1), seconds: 0.2)
        XCTAssertEqual(kame.charge, before, accuracy: 0.01)
        run.hold(cupped(), seconds: 0.3)
        XCTAssertGreaterThan(kame.charge, before + 0.1, "and charging carries on")

        // Final Flash: both hands lost for 0.2 s.
        let flash = Run(mine())
        let ff = flash.set.moves[2] as! FinalFlashMove
        flash.hold(palmsUp(), seconds: 1.2)
        let held = ff.charge
        flash.hold([], seconds: 0.2)
        XCTAssertTrue(ff.isEngaged)
        XCTAssertEqual(ff.charge, held, accuracy: 0.01)

        // Special Beam Cannon: the hand at the forehead lost for 0.2 s.
        let sbc = Run(mine())
        let cannon = sbc.set.moves[0] as! SpecialBeamCannonMove
        sbc.hold([atForehead(sbc.faceState)], seconds: 1.2)
        let charge = cannon.charge
        sbc.hold([], seconds: 0.2)
        sbc.hold([atForehead(sbc.faceState)], seconds: 0.1)
        XCTAssertTrue(cannon.isEngaged)
        XCTAssertGreaterThanOrEqual(cannon.charge, charge)

        // Finger Beam: the hand carried through a blur while aiming, then lost for 0.2 s while firing.
        let fb = Run(mine())
        let finger = fb.set.moves[4] as! FingerBeamMove
        let hand = pointing(at: CGPoint(x: 820, y: 300), heading: 0.1)
        fb.hold([hand], seconds: 0.4)
        var blurred = hand
        blurred.unseenFor = 0.1
        fb.hold([blurred], seconds: 0.2)
        XCTAssertTrue(finger.isEngaged, "still aiming through the blur")
        fb.hold([hand], seconds: 0.5)
        XCTAssertTrue(finger.isFiring)
        fb.hold([], seconds: 0.2)
        XCTAssertTrue(finger.isFiring, "the beam does not vanish when the hand is lost for a moment")
        fb.hold([], seconds: 0.6)
        XCTAssertFalse(finger.isFiring)
    }

    func testTwoMovesNeverEngageTogetherAndBlockedStartsNothing() {
        // Each pose claims its own move only, and a held move keeps the others out.
        let run = Run(mine())
        run.hold(cupped(), seconds: 1)
        XCTAssertEqual(run.set.engaged?.id, "kamehameha")
        // Straight from one pose to the other: the first holds the hands until its charge has drained, then hands over cleanly.
        run.hold(palmsUp(), seconds: 0.3)
        XCTAssertEqual(run.set.engaged?.id, "kamehameha")
        run.hold(palmsUp(), seconds: 1.5)
        XCTAssertEqual(run.set.engaged?.id, "final-flash")
        // A Final Flash pushed out never also fires a Ki Blast.
        for frame in growing({ self.palmsUp(size: $0) }, from: 110, growth: 1.3, frames: 5) { run.step(frame) }
        XCTAssertEqual((run.set.moves[3] as! KiBlastMove).fired, 0)
        run.hold([], seconds: 3)

        // Special Beam Cannon released into a point fires the cannon, not the Finger Beam.
        run.hold([atForehead(run.faceState)], seconds: 1.2)
        run.hold([pointing(at: CGPoint(x: 820, y: 330), heading: 0.1)], seconds: 1.2)
        XCTAssertEqual((run.set.moves[0] as! SpecialBeamCannonMove).fired, 1)
        XCTAssertEqual((run.set.moves[4] as! FingerBeamMove).fired, 0)
        XCTAssertEqual(run.together, 0)

        // While blocked (both fists for a power-up), nothing begins, but a move already going carries on.
        let blocked = Run(mine())
        blocked.blocked = true
        blocked.hold(cupped(), seconds: 1.5)
        XCTAssertNil(blocked.set.engaged)
        blocked.blocked = false
        blocked.hold(cupped(), seconds: 1.2)
        blocked.blocked = true
        blocked.hold(cupped(), seconds: 0.3)
        XCTAssertEqual(blocked.set.engaged?.id, "kamehameha")
    }

    func testTheMovesWorkOnARealProportionedHead() {
        // A head with real proportions: mouth lower, head wider, face smaller. The moves read face units, so the same poses (placed for
        // this head) work.
        let head = HeadwearRealHead()
        let face = head.face()
        let set = SaiyanMoveSet(moves: mine())
        var gestures = HandGestureRecognizer()
        let rect = CGRect(x: 0, y: 0, width: 1280, height: 720)
        var time = 0.0
        func step(_ hands: [HandState]) {
            time += 1.0 / 30
            let events = gestures.update(hands, dt: 1.0 / 30)
            set.update(SaiyanMoveContext(hands: hands, gestures: gestures, events: events, face: face, personCenter: head.center, form: .superSaiyan,
                                         power: SaiyanForm.superSaiyan.power, dt: 1.0 / 30, time: time, rect: rect), blocked: false)
        }
        for _ in 0..<40 { step(cupped(at: CGPoint(x: 700, y: 170), size: 100)) }
        XCTAssertEqual(set.engaged?.id, "kamehameha")
        set.reset()
        for _ in 0..<40 { step([]) }
        for _ in 0..<40 { step(palmsUp(at: CGPoint(x: 640, y: 160), size: 100)) }
        XCTAssertEqual(set.engaged?.id, "final-flash")
        set.reset()
        for _ in 0..<40 { step([]) }
        for _ in 0..<30 { step([atForehead(face, size: 100)]) }
        XCTAssertEqual(set.engaged?.id, "special-beam-cannon")
    }

    // MARK: Cost

    private static func beamOf(_ move: SaiyanMove) -> SaiyanBeamLook? {
        (move as? KamehamehaMove)?.beam ?? (move as? FinalFlashMove)?.beam ?? (move as? SpecialBeamCannonMove)?.beam ?? (move as? FingerBeamMove)?.beam
    }

    func testEachMoveIsCheapWhileActiveAndFreeWhenIdle() {
        let ctx = HandFXKit.bitmap(width: 1280, height: 720)!
        func measure(_ name: String, _ move: SaiyanMove, frames: [[HandState]], form: SaiyanForm = .ultraInstinct) -> (mean: Double, worst: Double) {
            let bench = SaiyanBench()
            var times: [Double] = [], charging: [Double] = [], firing: [Double] = []
            for hands in frames {
                let c = bench.context(hands: hands, form: form)
                ctx.clear(CGRect(x: 0, y: 0, width: 1280, height: 720))
                let started = CFAbsoluteTimeGetCurrent()
                move.update(c, mayBegin: true)
                _ = move.washes()
                move.drawSolids(in: ctx)
                move.drawLight(in: ctx)
                let spent = (CFAbsoluteTimeGetCurrent() - started) * 1000
                if move.isEngaged || move.hasLight {
                    times.append(spent)
                    if Self.beamOf(move) != nil { firing.append(spent) } else { charging.append(spent) }
                }
            }
            let mean = times.reduce(0, +) / Double(max(1, times.count)), worst = times.max() ?? 0
            func avg(_ xs: [Double]) -> Double { xs.reduce(0, +) / Double(max(1, xs.count)) }
            print(String(format: "[beam-cost] %@: %.3f ms mean, %.3f ms worst over %d active frames (%.3f charging, %.3f with a beam)", name, mean, worst,
                         times.count, avg(charging), avg(firing)))
            return (mean, worst)
        }
        let thrust = (1...4).map { cupped(at: CGPoint(x: 700 + Double($0) * 28, y: 190)) }
        let kame = measure("kamehameha", KamehamehaMove(), frames: Array(repeating: cupped(), count: 75) + thrust + Array(repeating: thrust[3], count: 60))
        let push = growing({ self.palmsUp(size: $0) }, from: 110, growth: 1.3, frames: 5)
        let flash = measure("final-flash", FinalFlashMove(), frames: Array(repeating: palmsUp(), count: 60) + push + Array(repeating: push[4], count: 60))
        let face = SaiyanBench().face!
        let away = pointing(at: CGPoint(x: 800, y: 420), heading: 0.1, fingers: .peace)
        let cannon = measure("special-beam-cannon", SpecialBeamCannonMove(), frames: Array(repeating: [atForehead(face)], count: 60) + Array(repeating: [away], count: 50))
        let at = CGPoint(x: 960, y: 260)
        var kiFrames: [[HandState]] = Array(repeating: [place(.open, palm: at, size: 100)], count: 15)
        for _ in 0..<6 {
            kiFrames += growing({ [self.place(.open, palm: at, size: $0)] }, from: 100, growth: 1.36, frames: 4)
            kiFrames += growing({ [self.place(.open, palm: at, size: $0)] }, from: 136, growth: 1 / 1.36, frames: 4)
        }
        let ki = measure("ki-blast", KiBlastMove(), frames: kiFrames + Array(repeating: [], count: 20))
        let finger = measure("finger-beam", FingerBeamMove(), frames: Array(repeating: [pointing(at: CGPoint(x: 820, y: 300), heading: 0.15)], count: 75))
        // The budget is 1.5 ms; the machine is shared with other builds, so the test allows headroom and the report prints the real numbers.
        for (name, cost) in [("kamehameha", kame), ("final-flash", flash), ("special-beam-cannon", cannon), ("ki-blast", ki), ("finger-beam", finger)] {
            XCTAssertLessThan(cost.mean, 4, "\(name) costs \(cost.mean) ms a frame while active")
        }
        // The same in Super Saiyan, where the beams are smaller: for the report.
        _ = measure("kamehameha (Super Saiyan)", KamehamehaMove(), frames: Array(repeating: cupped(), count: 75) + thrust + Array(repeating: thrust[3], count: 60),
                    form: .superSaiyan)
        _ = measure("final-flash (Super Saiyan)", FinalFlashMove(), frames: Array(repeating: palmsUp(), count: 60) + push + Array(repeating: push[4], count: 60),
                    form: .superSaiyan)

        // Idle: nobody in view, or hands doing nothing in particular.
        let bench = SaiyanBench()
        let moves = mine()
        var idle: [Double] = []
        for i in 0..<120 {
            let hands = i % 2 == 0 ? [] : [place(.open, palm: CGPoint(x: 900, y: 300))]
            let c = bench.context(hands: hands)
            let started = CFAbsoluteTimeGetCurrent()
            for move in moves { move.update(c, mayBegin: true) }
            idle.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
        }
        let idleMean = idle.reduce(0, +) / Double(idle.count)
        print(String(format: "[beam-cost] all five idle: %.4f ms mean", idleMean))
        XCTAssertLessThan(idleMean, 0.1)
    }

    // MARK: Contact sheets

    /// Runs `frames` and returns the pictures of the frames numbered in `capture`.
    private func film(_ run: Run, _ frames: [[HandState]], capture: Set<Int>) -> [CIImage] {
        var out: [CIImage] = []
        for (i, hands) in frames.enumerated() {
            if capture.contains(i) { out.append(run.picture(hands)) } else { run.step(hands) }
        }
        return out
    }

    /// The real-proportioned head with hands painted in, composed the way the lens composes the moves.
    private func realHeadPicture(_ head: HeadwearRealHead, hands: [HandState], set: SaiyanMoveSet, h: LensHarness, time: Double) -> CIImage {
        let (person, matte) = head.pictures()
        let backdrop = SyntheticScene.backdrop()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let paint = CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
        paint.setFillColor(head.skin)
        paint.setStrokeColor(head.skin)
        paint.setLineCap(.round)
        paint.setLineJoin(.round)
        for hand in hands {
            let palm = CGMutablePath()
            palm.move(to: hand.wrist)
            for joint in [HandJoint.thumbCMC, .indexMCP, .middleMCP, .ringMCP, .littleMCP] { palm.addLine(to: hand[joint]) }
            palm.closeSubpath()
            paint.setLineWidth(hand.size * 0.26)
            paint.addPath(palm)
            paint.drawPath(using: .fillStroke)
            for finger in Finger.allCases {
                paint.setLineWidth(hand.size * (finger == .thumb ? 0.27 : 0.21))
                paint.beginPath()
                paint.move(to: hand[finger.knuckle])
                paint.addLine(to: hand[finger.middleJoint])
                paint.addLine(to: hand[HandJoint(rawValue: finger.middleJoint.rawValue + 1) ?? finger.tip])
                paint.addLine(to: hand[finger.tip])
                paint.strokePath()
            }
        }
        let picture = CIImage(cgImage: paint.makeImage()!).composited(over: CIImage(cgImage: person).composited(over: backdrop))
        let input = LensInput(time: time, dt: 1.0 / 30, rect: CGRect(x: 0, y: 0, width: 1280, height: 720), camera: picture, matte: CIImage(cgImage: matte),
                              background: backdrop, composed: picture, matteGrid: nil, face: head.face(), services: h.services, hands: hands)
        let lit = SaiyanCompose.moves(set, over: picture, input: input)
        let out = SaiyanCompose.screen(set.screenEffect, over: lit, rect: input.rect, time: time)
        return CIImage(cgImage: h.ciContext.createCGImage(out, from: input.rect)!)
    }

    /// The states and shapes a real call brings: firing to the left with the other hand, small and large hands, a smaller face, a tilted
    /// head, a hand lost mid-charge, and a head with real proportions.
    func testVariantSheet() {
        var pictures: [CIImage] = []
        // Kamehameha to the left, with hands mirrored.
        let left = (1...4).map { cupped(at: CGPoint(x: 580 - Double($0) * 28, y: 190), side: -1) }
        pictures += film(Run(mine()), Array(repeating: cupped(at: CGPoint(x: 580, y: 190), side: -1), count: 70) + left + Array(repeating: left[3], count: 12),
                         capture: [85])
        // Small hands (a person further back) and large ones (close to the camera), Super Saiyan 2.
        for size in [80.0, 145] {
            let thrust = (1...4).map { cupped(at: CGPoint(x: 700 + Double($0) * size * 0.25, y: 190), size: size) }
            pictures += film(Run(mine(), form: .superSaiyan2), Array(repeating: cupped(size: size), count: 70) + thrust + Array(repeating: thrust[3], count: 12),
                             capture: [69, 85])
        }
        // A smaller face further from the camera: the same poses, scaled.
        var small = SyntheticScene()
        small.scale = 0.6
        small.center = CGPoint(x: 640, y: 470)
        let face = SaiyanBench(scene: small).face!
        let farAway = pointing(at: CGPoint(x: 760, y: 470), heading: 0.05, size: 70, fingers: .peace)
        pictures += film(Run(mine(), form: .superSaiyanBlue, scene: small), Array(repeating: [atForehead(face, size: 70)], count: 60) + Array(repeating: [farAway], count: 25),
                         capture: [59, 84])
        // A tilted head: the cannon from the left hand, pointing left.
        var tilted = SyntheticScene()
        tilted.roll = 0.3
        let tface = SaiyanBench(scene: tilted).face!
        let leftPoint = pointing(at: CGPoint(x: 460, y: 400), heading: .pi - 0.12, fingers: .point, mirrored: true)
        pictures += film(Run(mine(), form: .ultraEgo, scene: tilted), Array(repeating: [atForehead(tface, angle: 0.1, mirrored: true)], count: 60)
                         + Array(repeating: [leftPoint], count: 25), capture: [84])
        // A hand lost mid-charge: the orb stays.
        pictures += film(Run(mine(), form: .superSaiyan3), Array(repeating: cupped(), count: 45) + Array(repeating: [cupped()[0]], count: 6), capture: [50])
        // Ki Blast from the left hand to the left, and a Finger Beam from the left hand.
        let kiAt = CGPoint(x: 400, y: 250)
        let kiPush = growing({ [self.place(.open, palm: kiAt, size: $0, mirrored: true)] }, from: 100, growth: 1.4, frames: 5)
        pictures += film(Run(mine(), form: .blueKaioken), Array(repeating: [place(.open, palm: kiAt, size: 100, mirrored: true)], count: 14) + kiPush
                         + Array(repeating: kiPush[4], count: 8), capture: [25])
        let leftFinger = pointing(at: CGPoint(x: 460, y: 300), heading: .pi - 0.2, fingers: .gun, mirrored: true)
        pictures += film(Run(mine(), form: .ultraInstinctSign), Array(repeating: [leftFinger], count: 36), capture: [35])
        // A head with real proportions.
        let head = HeadwearRealHead()
        let set = SaiyanMoveSet(moves: mine())
        var gestures = HandGestureRecognizer()
        let h = LensHarness()
        var time = 0.0
        let realThrust = (1...4).map { cupped(at: CGPoint(x: 700 + Double($0) * 25, y: 170), size: 100) }
        let frames = Array(repeating: cupped(at: CGPoint(x: 700, y: 170), size: 100), count: 70) + realThrust + Array(repeating: realThrust[3], count: 12)
        for (i, hands) in frames.enumerated() {
            time += 1.0 / 30
            let events = gestures.update(hands, dt: 1.0 / 30)
            set.update(SaiyanMoveContext(hands: hands, gestures: gestures, events: events, face: head.face(), personCenter: head.center, form: .superSaiyanGod,
                                         power: SaiyanForm.superSaiyanGod.power, dt: 1.0 / 30, time: time, rect: CGRect(x: 0, y: 0, width: 1280, height: 720)),
                       blocked: false)
            if i == 69 || i == frames.count - 1 { pictures.append(realHeadPicture(head, hands: hands, set: set, h: h, time: time)) }
        }
        Output.save(SaiyanBench.sheet(pictures, columns: 3, scale: 0.5), as: "beam-sheet-variants.png")
    }

    /// Each move charging and firing in five forms, and the Kamehameha's whole life in Super Saiyan, for looking at.
    func testContactSheets() {
        let face = SaiyanBench().face!
        let thrust = (1...4).map { cupped(at: CGPoint(x: 700 + Double($0) * 28, y: 190)) }
        let push = growing({ self.palmsUp(size: $0) }, from: 110, growth: 1.3, frames: 5)
        let away = pointing(at: CGPoint(x: 800, y: 420), heading: 0.1, fingers: .peace)
        let kiAt = CGPoint(x: 760, y: 260)
        let kiPush = growing({ [self.place(.open, palm: kiAt, size: $0)] }, from: 100, growth: 1.4, frames: 5)
        let fingerHand = pointing(at: CGPoint(x: 820, y: 300), heading: 0.15)
        let scripts: [(String, [[HandState]], Set<Int>)] = [
            ("kamehameha", Array(repeating: cupped(), count: 80) + thrust + Array(repeating: thrust[3], count: 30), [79, 96]),
            ("finalflash", Array(repeating: palmsUp(), count: 75) + push + Array(repeating: push[4], count: 30), [74, 91]),
            ("cannon", Array(repeating: [atForehead(face)], count: 66) + Array(repeating: [away], count: 40), [65, 90]),
            ("kiblast", Array(repeating: [place(.open, palm: kiAt, size: 100)], count: 14) + kiPush + Array(repeating: kiPush[4], count: 12), [18, 22]),
            ("finger", Array(repeating: [fingerHand], count: 40), [16, 36]),
        ]
        for (name, frames, capture) in scripts {
            var pictures: [CIImage] = []
            for form in Self.forms { pictures += film(Run(mine(), form: form), frames, capture: capture) }
            Output.save(SaiyanBench.sheet(pictures, columns: 2, scale: 0.5), as: "beam-sheet-\(name)-forms.png")
        }

        // The Kamehameha's whole life in Super Saiyan: posing, charging, full, the beam flying out, landing, pouring, running out, gone.
        let life = film(Run(mine()), Array(repeating: cupped(), count: 86) + thrust + Array(repeating: thrust[3], count: 100),
                        capture: [9, 40, 85, 89, 91, 99, 129, 161, 167])
        Output.save(SaiyanBench.sheet(life, columns: 3, scale: 0.5), as: "beam-sheet-kamehameha-life.png")
    }

}
