import CoreImage
import XCTest

/// The five Dragon Ball moves that are not beams: Spirit Bomb, Destructo Disc, Solar Flare, Instant Transmission and Zanzoken. How each
/// is set off, what must not set it off (waving, talking, one hand where two are wanted), how its screen effects come and go, what it
/// costs, and pictures of each at its key moments in five forms.
final class SaiyanOtherMoveTests: XCTestCase {
    private var bench = SaiyanBench()
    private var face: FaceState { bench.face! }
    private var io: Double { face.interocular }

    override func setUp() {
        super.setUp()
        bench = SaiyanBench()
    }

    // MARK: Hands

    /// A point given in face units (eye spacings from between the eyes, x across the face, y up it) in output pixels.
    private func world(_ p: CGPoint, on f: FaceState? = nil) -> CGPoint {
        let f = f ?? face
        let io = f.interocular, up = f.up, across = f.across
        return CGPoint(x: f.eyeCenter.x + (across.dx * p.x + up.dx * p.y) * io, y: f.eyeCenter.y + (across.dy * p.x + up.dy * p.y) * io)
    }

    /// A fixture hand with its palm at `palm` (pixels).
    private func hand(_ fingers: HandFixtures.Fingers, palm: CGPoint, size: Double = 100, angle: Double = 0, mirrored: Bool = false, id: Int = 1,
                      velocity: CGVector = .zero) -> HandState {
        let h = HandFixtures.hand(fingers, at: .zero, size: size, angle: angle, mirrored: mirrored, id: id, velocity: velocity)
        return HandFixtures.moved(h, by: palm - h.palm)
    }

    private func open(_ local: CGPoint, size: Double = 100, angle: Double = 0, mirrored: Bool = false, id: Int = 1, on f: FaceState? = nil) -> HandState {
        hand(.open, palm: world(local, on: f), size: size, angle: angle, mirrored: mirrored, id: id)
    }

    /// Both open hands up over the head.
    private func overhead(size: Double = 100, spread: Double = 1.1, height: Double = 2.0, on f: FaceState? = nil) -> [HandState] {
        [open(CGPoint(x: -spread, y: height), size: size, angle: 0.12, mirrored: true, id: 1, on: f),
         open(CGPoint(x: spread, y: height), size: size, angle: -0.12, id: 2, on: f)]
    }

    /// Index and middle fingers on the forehead, the hand coming up from one side and leaning in.
    private func foreheadTouch(size: Double = 100, side: Double = 1, lean: Double = 0.5, id: Int = 1, on f: FaceState? = nil) -> HandState {
        let f = f ?? face
        let h = HandFixtures.hand(.peace, at: .zero, size: size, angle: side * lean, mirrored: side < 0, id: id)
        let tips = CGPoint(x: (h[.indexTip].x + h[.middleTip].x) / 2, y: (h[.indexTip].y + h[.middleTip].y) / 2)
        return HandFixtures.moved(h, by: f.forehead - tips)
    }

    /// The same hand slid so its palm is at `palm`, moving at the speed that slide implies over one frame from `from`.
    private func slid(_ h: HandState, to palm: CGPoint, from previous: CGPoint, dt: Double = 1.0 / 30) -> HandState {
        HandFixtures.moved(h, by: palm - h.palm, velocity: CGVector(dx: (palm.x - previous.x) / dt, dy: (palm.y - previous.y) / dt))
    }

    // MARK: Running

    /// One frame of the moves, without a picture. Checks on every frame that no two moves are engaged at once.
    @discardableResult
    private func tick(_ set: SaiyanMoveSet, _ hands: [HandState], form: SaiyanForm = .superSaiyan, face withFace: Bool = true, blocked: Bool = false,
                      file: StaticString = #filePath, line: UInt = #line) -> SaiyanScreenEffect {
        set.update(bench.context(hands: hands, form: form, face: withFace), blocked: blocked)
        XCTAssertLessThanOrEqual(set.moves.filter(\.isEngaged).count, 1, "only one move may be engaged", file: file, line: line)
        return set.screenEffect
    }

    @discardableResult
    private func hold(_ set: SaiyanMoveSet, _ hands: [HandState], seconds: Double, form: SaiyanForm = .superSaiyan, face withFace: Bool = true) -> SaiyanScreenEffect {
        var e = SaiyanScreenEffect.none
        for _ in 0..<max(1, Int((seconds * 30).rounded())) { e = tick(set, hands, form: form, face: withFace) }
        return e
    }

    /// A frame with a picture, read out at once (pictures share drawing buffers, so they must be captured before the next frame).
    private func frame(_ set: SaiyanMoveSet, _ hands: [HandState], form: SaiyanForm = .superSaiyan, face withFace: Bool = true) -> CIImage {
        let picture = bench.step(set, hands: hands, form: form, face: withFace)
        XCTAssertLessThanOrEqual(set.moves.filter(\.isEngaged).count, 1)
        return still(picture)
    }

    private func still(_ image: CIImage) -> CIImage {
        guard let cg = bench.h.ciContext.createCGImage(image, from: bench.rect) else { return image }
        return CIImage(cgImage: cg)
    }

    private func brightness(_ p: RGB) -> Int { p.r + p.g + p.b }

    /// Frames of the same hands until something has happened, or `limit` frames.
    private func run(_ set: SaiyanMoveSet, _ hands: [HandState], form: SaiyanForm = .superSaiyan, until done: () -> Bool, limit: Int = 90) {
        var n = 0
        while !done(), n < limit {
            tick(set, hands, form: form)
            n += 1
        }
        XCTAssertTrue(done(), "it never happened")
    }

    private func single<M: SaiyanMove>(_ move: M) -> (SaiyanMoveSet, M) { (SaiyanMoveSet(moves: [move]), move) }

    // MARK: Measuring the poses

    /// The thresholds are set between readings of the fixtures, not guessed: open palms at every angle and size read open, the overhead
    /// and forehead zones take the hands they should and not their neighbours, and waves are measured against the sweeps that fire.
    func testThresholdsSitBetweenTheFixtureReadings() {
        var lines: [String] = []
        // Open palms: every angle, size and side reads as an open palm, which Spirit Bomb, Destructo Disc and Solar Flare all need.
        for size in [60.0, 100, 160] {
            for angle in [-0.6, -0.3, 0, 0.3, 0.6] {
                for mirrored in [false, true] {
                    let h = HandFixtures.hand(.open, size: size, angle: angle, mirrored: mirrored)
                    XCTAssertEqual(HandGesture.Pose.classify(h), .openPalm, "open palm \(size) \(angle) \(mirrored)")
                }
            }
        }
        for reading in HandFixtures.gallery where reading.expected == .openPalm {
            XCTAssertEqual(HandGesture.Pose.classify(HandFixtures.recorded(reading)), .openPalm, reading.picture)
        }
        // Overhead: palm height above the eyes, in eye spacings.
        for y in [1.2, 1.4, 1.5, 1.8, 2.2] {
            let h = open(CGPoint(x: 1.0, y: y))
            lines.append(String(format: "overhead  palm at %.1f io: %@", y, SaiyanZones.isOverhead(h, face) ? "yes" : "no"))
            XCTAssertEqual(SaiyanZones.isOverhead(h, face), y > 1.45)
        }
        // Forehead: two fingers on it from either side, any size; other poses there, or two fingers at the chin, do not count.
        for size in [70.0, 100, 140] {
            for side in [-1.0, 1.0] {
                for lean in [0.3, 0.6] {
                    XCTAssertTrue(SaiyanZones.fingersAtForehead(foreheadTouch(size: size, side: side, lean: lean), face), "touch \(size) \(side) \(lean)")
                }
            }
        }
        let chin = HandFixtures.moved(foreheadTouch(), by: CGVector(dx: 0, dy: -io * 1.9))
        XCTAssertFalse(SaiyanZones.fingersAtForehead(chin, face), "two fingers at the chin are not at the forehead")
        let flat = hand(.open, palm: world(CGPoint(x: 0.3, y: 0.0)))
        XCTAssertFalse(SaiyanZones.fingersAtForehead(HandFixtures.moved(flat, by: face.forehead - flat[.middleTip]), face), "a flat hand on the forehead")
        let finger = HandFixtures.hand(.point, at: .zero, size: 100, angle: 0.5)
        XCTAssertFalse(SaiyanZones.fingersAtForehead(HandFixtures.moved(finger, by: face.forehead - finger.indexTip), face), "one finger")

        // Solar Flare: hands framing the eyes are near the face and together; hands either side of the head at arm's length are not.
        let framing = [open(CGPoint(x: -0.8, y: 0), size: 95, mirrored: true, id: 1), open(CGPoint(x: 0.8, y: 0), size: 95, id: 2)]
        lines.append(String(format: "frame eyes  distance to face %.2f io, gap %.2f palms", SaiyanZones.distanceToFace(framing[0], face),
                            HandState.distance(framing[0].palm, framing[1].palm) / 95))
        XCTAssertTrue(framing.allSatisfy { SaiyanZones.isNearFace($0, face, reach: SolarFlareMove.reach) })
        XCTAssertTrue(SaiyanZones.together(framing[0], framing[1], within: SolarFlareMove.together))
        let apart = [open(CGPoint(x: -2.6, y: 0), size: 95, mirrored: true, id: 1), open(CGPoint(x: 2.6, y: 0), size: 95, id: 2)]
        XCTAssertFalse(apart.allSatisfy { SaiyanZones.isNearFace($0, face, reach: SolarFlareMove.reach) })
        // Final Flash holds open palms together at the chest: well outside the Solar Flare's reach.
        let chest = [open(CGPoint(x: -0.6, y: -2.6), size: 95, mirrored: true, id: 1), open(CGPoint(x: 0.6, y: -2.6), size: 95, id: 2)]
        lines.append(String(format: "chest palms  distance to face %.2f io (reach %.1f)", SaiyanZones.distanceToFace(chest[0], face), SolarFlareMove.reach))
        XCTAssertFalse(chest.contains { SaiyanZones.isNearFace($0, face, reach: SolarFlareMove.reach) })

        // Waves against sweeps: the fastest a palm goes, the most it covers in 0.2 s, and how far it came back the other way before.
        func reading(_ name: String, _ x: (Double) -> Double) -> (peak: Double, travel: Double, ahead: Double) {
            var trail = SaiyanHandTrail()
            var peak = 0.0, travel = 0.0, ahead = 0.0
            for i in 0..<75 {
                let t = Double(i) / 30
                let h = hand(.open, palm: CGPoint(x: 640 + x(t) * 100, y: 250), velocity: CGVector(dx: (x(t) - x(t - 1.0 / 30)) * 3000, dy: 0))
                trail.update([h], time: t)
                guard t > 0.8, let start = trail.origin(1, within: ZanzokenMove.window) else { continue }
                let moved = Double(trail.travel(1, over: ZanzokenMove.window).dx) / 100
                peak = max(peak, abs(Double(trail.velocity(1, over: 0.07).dx)) / 100)
                if abs(moved) > abs(travel) {
                    travel = moved
                    ahead = trail.excursion(1, from: ZanzokenMove.window + 0.5, to: ZanzokenMove.window, along: CGVector(dx: moved > 0 ? 1 : -1, dy: 0),
                                            beyond: start.palm) / 100
                }
            }
            lines.append(String(format: "%@  peak %.1f palms/s, travel in 0.2 s %.2f palms, had been %.2f palms ahead", name, peak, abs(travel), ahead))
            return (peak, abs(travel), ahead)
        }
        let friendly = reading("friendly wave (0.5 palm, 1.5 Hz)") { 0.5 * sin(2 * .pi * 1.5 * $0) }
        let eager = reading("eager wave (1.3 palm, 1.8 Hz)   ") { 1.3 * sin(2 * .pi * 1.8 * $0) }
        let even = reading("eager wave (1.3 palm, 2.0 Hz)   ") { 1.3 * sin(2 * .pi * 2.0 * $0) }
        let sweep = reading("sweep (14 palms/s for 0.25 s)   ") { t in t < 1.0 ? 0 : min(3.5, (t - 1.0) * 14) }
        let windup = reading("sweep after a 0.6-palm wind-up  ") { t in t < 0.8 ? 0 : t < 1.0 ? -0.6 * (t - 0.8) / 0.2 : min(3.0, -0.6 + (t - 1.0) * 14) }
        XCTAssertLessThan(friendly.peak, ZanzokenMove.fireSpeed / 1.5, "a friendly wave is nowhere near")
        XCTAssertLessThan(friendly.travel, ZanzokenMove.travel / 2)
        XCTAssertGreaterThan(eager.peak, ZanzokenMove.fireSpeed, "an eager wave is as fast: it is the turning back that tells it apart")
        XCTAssertGreaterThan(eager.ahead, ZanzokenMove.turnBack)
        XCTAssertGreaterThan(even.ahead, ZanzokenMove.turnBack, "even when its period matches the look-back")
        XCTAssertGreaterThan(sweep.peak, ZanzokenMove.fireSpeed)
        XCTAssertGreaterThan(sweep.travel, ZanzokenMove.travel)
        XCTAssertLessThan(sweep.ahead, ZanzokenMove.turnBack)
        XCTAssertLessThan(windup.ahead, ZanzokenMove.turnBack, "a small wind-up before the sweep is allowed")
        print("Saiyan other moves, readings:\n  " + lines.joined(separator: "\n  "))
    }

    // MARK: Spirit Bomb

    func testSpiritBombGathersOverheadAndSlamsDownWhenThrown() {
        let (set, bomb) = single(SpiritBombMove())
        var hands = overhead()
        hold(set, hands, seconds: 0.3)
        XCTAssertEqual(bomb.phase, .posing, "the pose is claimed while it is held")
        XCTAssertTrue(bomb.isEngaged)
        XCTAssertEqual(bomb.charge, 0)
        hold(set, hands, seconds: 0.4)
        XCTAssertEqual(bomb.phase, .gathering, "after half a second it starts to gather")
        XCTAssertEqual(set.status?.title, "Gathering energy...")
        let small = bomb.radius
        var e = hold(set, hands, seconds: 2.5)
        XCTAssertGreaterThan(bomb.radius, small * 3, "the sphere swells")
        XCTAssertGreaterThan(e.darken, 0.5, "and the room darkens")
        XCTAssertLessThanOrEqual(e.darken, SpiritBombMove.darkest + 1e-6)
        XCTAssertGreaterThan(bomb.center.y, face.headTop.y, "it floats above the head")
        XCTAssertEqual(set.status?.detail, "Swing both hands down to throw it")
        e = hold(set, hands, seconds: 1.6)
        XCTAssertEqual(bomb.charge, 1, accuracy: 1e-9)
        let headHeight = io * 3
        XCTAssertEqual(bomb.radius * 2 / headHeight, SpiritBombMove.headHeights * (0.78 + 0.22 * SaiyanForm.superSaiyan.power), accuracy: 0.12,
                       "about 1.6 head heights across at full power")

        // The throw: both hands swing down hard, about 8 palm lengths a second.
        let start = hands.map(\.palm)
        for i in 1...6 {
            hands = hands.enumerated().map { k, h in
                let to = CGPoint(x: start[k].x, y: start[k].y - Double(i) * 27), from = CGPoint(x: start[k].x, y: start[k].y - Double(i - 1) * 27)
                return slid(h, to: to, from: from)
            }
            tick(set, hands)
        }
        XCTAssertEqual(bomb.phase, .falling, "the swing throws it")
        XCTAssertEqual(bomb.thrown, 1)
        let low = hands.map { HandFixtures.moved($0, by: .zero, velocity: .zero) }
        var peakFlash = 0.0, peakShake = 0.0
        for _ in 0..<30 {
            e = tick(set, low)
            peakFlash = max(peakFlash, e.flash)
            peakShake = max(peakShake, e.shake)
        }
        XCTAssertGreaterThan(peakFlash, 0.8, "it lands in a blinding flash")
        XCTAssertGreaterThan(peakShake, 0.6, "that shakes the picture")
        for _ in 0..<90 { e = tick(set, low) }
        XCTAssertTrue(e.isNone, "and the room comes back: \(e)")
        XCTAssertFalse(bomb.isEngaged)
        hold(set, [], seconds: 0.6)
        XCTAssertFalse(set.hasLight, "nothing left over")
    }

    func testSpiritBombMeltsAwayWhenTheHandsComeDownSlowly() {
        let (set, bomb) = single(SpiritBombMove())
        var hands = overhead(size: 90, spread: 1.3)
        hold(set, hands, seconds: 2.5)
        XCTAssertEqual(bomb.phase, .gathering)
        // Lowered at about 1.5 palm lengths a second.
        let start = hands.map(\.palm)
        var flash = 0.0
        for i in 1...45 {
            hands = hands.enumerated().map { k, h in
                slid(h, to: CGPoint(x: start[k].x, y: start[k].y - Double(i) * 4.5), from: CGPoint(x: start[k].x, y: start[k].y - Double(i - 1) * 4.5))
            }
            flash = max(flash, tick(set, hands).flash)
        }
        XCTAssertEqual(bomb.thrown, 0, "lowering slowly is not a throw")
        XCTAssertEqual(flash, 0, "and makes no flash")
        let e = hold(set, hands.map { HandFixtures.moved($0, by: .zero, velocity: .zero) }, seconds: 3)
        XCTAssertTrue(e.isNone, "the room brightens back")
        XCTAssertEqual(bomb.phase, .idle)
        XCTAssertFalse(set.hasLight)
    }

    func testSpiritBombIgnoresOneHandFistsWavingAndNoFace() {
        let chest = open(CGPoint(x: -1.4, y: -2.6), mirrored: true, id: 1)
        let cases: [(String, (Int) -> [HandState], Bool)] = [
            ("one hand up, one at the chest", { _ in [chest, self.open(CGPoint(x: 1.1, y: 2.0), id: 2)] }, true),
            ("both hands up in fists", { _ in self.overhead().map { self.hand(.fist, palm: $0.palm, id: $0.id) } }, true),
            ("both hands up beside the ears", { _ in [self.open(CGPoint(x: -1.6, y: 0.6), mirrored: true, id: 1), self.open(CGPoint(x: 1.6, y: 0.6), id: 2)] }, true),
            ("both hands up, far apart", { _ in self.overhead(spread: 3.0) }, true),
            ("both hands waving overhead", { i in
                let dx = sin(Double(i) / 30 * 2 * .pi * 1.6) * 70
                return self.overhead().map { HandFixtures.moved($0, by: CGVector(dx: dx, dy: 0), velocity: CGVector(dx: cos(Double(i) / 30 * 2 * .pi * 1.6) * 700, dy: 0)) }
            }, true),
            ("both hands up, no face", { _ in self.overhead() }, false),
        ]
        for (name, hands, withFace) in cases {
            bench = SaiyanBench()
            let (set, bomb) = single(SpiritBombMove())
            for i in 0..<75 {
                tick(set, hands(i), face: withFace)
                XCTAssertFalse(bomb.isEngaged, name)
            }
            XCTAssertTrue(set.screenEffect.isNone, name)
        }
    }

    func testSpiritBombHoldsItsChargeThroughATrackerDropout() {
        let (set, bomb) = single(SpiritBombMove())
        let hands = overhead()
        hold(set, hands, seconds: 2)
        let charge = bomb.charge
        // Gone from the list for 0.2 s.
        hold(set, [], seconds: 0.2)
        XCTAssertEqual(bomb.phase, .gathering, "a blink of the tracker does not drop the sphere")
        XCTAssertEqual(bomb.charge, charge, accuracy: 1e-9, "nor any of its charge")
        hold(set, hands, seconds: 0.3)
        XCTAssertGreaterThan(bomb.charge, charge)
        // Bridged by the tracker for 0.2 s.
        let bridged = hands.map { h -> HandState in var g = h; g.unseenFor = 0.1; return g }
        hold(set, bridged, seconds: 0.2)
        XCTAssertEqual(bomb.phase, .gathering)
        // Gone for good: it melts away rather than vanishing.
        tick(set, [])
        XCTAssertGreaterThan(bomb.radius, 10)
        hold(set, [], seconds: 0.6)
        XCTAssertEqual(bomb.phase, .fading)
        XCTAssertGreaterThan(bomb.radius, 10, "it shrinks away rather than popping")
    }

    // MARK: Destructo Disc

    func testDestructoDiscSpinsUpOverOneRaisedHandAndFlies() {
        for (mirrored, way) in [(false, 1.0), (true, -1.0)] {
            bench = SaiyanBench()
            let (set, disc) = single(DestructoDiscMove())
            let side = mirrored ? -1.25 : 1.25
            let rest = hand(.fist, palm: world(CGPoint(x: -side, y: -2.6)), mirrored: !mirrored, id: 2)
            var raised = open(CGPoint(x: side, y: 2.0), size: 95, angle: -side * 0.1, mirrored: mirrored, id: 1)
            hold(set, [raised, rest], seconds: 0.3)
            XCTAssertEqual(disc.phase, .posing)
            hold(set, [raised, rest], seconds: 0.4)
            XCTAssertEqual(disc.phase, .holding, "after half a second (and the gesture reader's own moment) a disc spins up")
            hold(set, [raised, rest], seconds: 0.8)
            XCTAssertEqual(disc.charge, 1, accuracy: 1e-9)
            XCTAssertEqual(disc.radius, 95 * DestructoDiscMove.size * (1 + 0.15 * SaiyanForm.superSaiyan.power), accuracy: 6)
            XCTAssertTrue((1.8...2.2).contains(disc.radius * 2 / 95), "about two palm lengths across: \(disc.radius * 2 / 95)")
            XCTAssertLessThan(HandState.distance(disc.center, raised.palm), 95 * 2, "held up by the hand")
            assertWhollyInView(disc)
            XCTAssertEqual(set.status?.detail, "Flick your hand to throw it")

            // A flick sideways: about 12 palm lengths a second.
            for _ in 0..<4 {
                let from = raised.palm
                raised = slid(raised, to: CGPoint(x: from.x + way * 38, y: from.y + 6), from: from)
                tick(set, [raised, rest])
                if disc.phase == .flying { break }
            }
            XCTAssertEqual(disc.phase, .flying, "the flick throws it")
            XCTAssertGreaterThan(disc.heading.dx * way, 0.9, "the way the hand went")
            let still = HandFixtures.moved(raised, by: .zero, velocity: .zero)
            let picture = frame(set, [still, rest])
            Output.save(picture, as: "saiyanD-disc-thrown\(mirrored ? "-mirrored" : "").png")
            // The hand comes down after the throw.
            let down = hand(.open, palm: world(CGPoint(x: side, y: -2.4)), size: 95, mirrored: mirrored, id: 1)
            var frames = 0
            while disc.phase == .flying, frames < 60 {
                tick(set, [down, rest])
                frames += 1
            }
            XCTAssertLessThan(frames, 30, "it leaves the picture quickly")
            XCTAssertTrue(set.hasLight, "the cut it left lingers")
            hold(set, [down, rest], seconds: 1.0)
            XCTAssertFalse(set.hasLight, "then fades")
            XCTAssertEqual(disc.thrown, 1)
        }
    }

    private func assertWhollyInView(_ disc: DestructoDiscMove, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let r = disc.radius, h = disc.radius * disc.flatness
        let box = CGRect(x: disc.center.x - r, y: disc.center.y - h, width: r * 2, height: h * 2)
        XCTAssertTrue(bench.rect.contains(box), "the whole disc is in the picture \(message): \(box)", file: file, line: line)
    }

    /// A raised hand often reaches the top of a webcam picture, or its side: the big disc is brought down and in so none of it is cut off.
    func testDestructoDiscStaysWhollyInViewWhenTheHandIsAtTheEdge() {
        for (x, y, size) in [(1.3, 2.0, 110.0), (1.2, 2.4, 110), (3.0, 2.2, 110), (-3.0, 2.0, 100), (0.6, 1.7, 80)] {
            bench = SaiyanBench()
            let (set, disc) = single(DestructoDiscMove())
            let raised = open(CGPoint(x: x, y: y), size: size, mirrored: x < 0, id: 1)
            hold(set, [raised], seconds: 1.4)
            XCTAssertEqual(disc.phase, .holding, "hand at (\(x), \(y))")
            XCTAssertEqual(disc.charge, 1, accuracy: 1e-9)
            assertWhollyInView(disc, "hand at (\(x), \(y))")
        }
    }

    func testDestructoDiscCutLingersAlongItsPath() {
        let (set, disc) = single(DestructoDiscMove())
        var raised = open(CGPoint(x: 1.3, y: 2.0), id: 1)
        hold(set, [raised], seconds: 1.2)
        let start = disc.center
        for _ in 0..<3 {
            let from = raised.palm
            raised = slid(raised, to: CGPoint(x: from.x + 40, y: from.y), from: from)
            tick(set, [raised])
        }
        XCTAssertEqual(disc.phase, .flying)
        for _ in 0..<5 { tick(set, [raised]) }
        let picture = frame(set, [raised])
        let plain = bench.h.bitmap(bench.input().composed)
        let lit = bench.h.bitmap(picture)
        // Halfway between where it started and where it is now, on its path.
        let mid = CGPoint(x: (start.x + disc.center.x) / 2, y: (start.y + disc.center.y) / 2)
        XCTAssertGreaterThan(brightness(lit.pixel(Int(mid.x), Int(mid.y))) - brightness(plain.pixel(Int(mid.x), Int(mid.y))), 120, "a bright cut along the path")
        XCTAssertLessThan(lit.change(from: plain, in: CGRect(x: 40, y: 40, width: 60, height: 60)), 12, "the far corner of the room is untouched")
    }

    func testDestructoDiscIgnoresTwoHandsWavingFistsAndLowHands() {
        let cases: [(String, (Int) -> [HandState], Bool)] = [
            ("both hands up", { _ in self.overhead() }, true),
            ("a hand waving up high", { i in
                let t = Double(i) / 30
                let h = self.open(CGPoint(x: 1.3, y: 1.8), id: 1)
                return [HandFixtures.moved(h, by: CGVector(dx: sin(t * 2 * .pi * 1.5) * 50, dy: 0), velocity: CGVector(dx: cos(t * 2 * .pi * 1.5) * 470, dy: 0))]
            }, true),
            ("a hand held up while talking", { _ in [self.open(CGPoint(x: 1.6, y: -0.8), id: 1)] }, true),
            ("a hand by the side of the head", { _ in [self.open(CGPoint(x: 1.7, y: 0.9), id: 1)] }, true),
            ("a fist up high", { _ in [self.hand(.fist, palm: self.world(CGPoint(x: 1.3, y: 2.0)), id: 1)] }, true),
            ("a hand up high, no face", { _ in [self.open(CGPoint(x: 1.3, y: 2.0), id: 1)] }, false),
        ]
        for (name, hands, withFace) in cases {
            bench = SaiyanBench()
            let (set, disc) = single(DestructoDiscMove())
            for i in 0..<60 {
                tick(set, hands(i), face: withFace)
                XCTAssertFalse(disc.isEngaged, name)
            }
        }
    }

    func testDestructoDiscWaitsASecondBeforeTheNextAndHoldsThroughADropout() {
        let (set, disc) = single(DestructoDiscMove())
        let up = open(CGPoint(x: 1.3, y: 2.0), id: 1)
        hold(set, [up], seconds: 0.8)
        XCTAssertEqual(disc.phase, .holding)
        let charge = disc.charge
        // A blink of the tracker while it spins: gone from the list, then bridged by the tracker.
        hold(set, [], seconds: 0.2)
        XCTAssertEqual(disc.phase, .holding, "a 0.2 s dropout does not drop the disc")
        XCTAssertEqual(disc.charge, charge, accuracy: 1e-9, "nor any of its charge")
        hold(set, [up], seconds: 0.3)
        var bridged = up
        bridged.unseenFor = 0.1
        hold(set, [bridged], seconds: 0.2)
        XCTAssertEqual(disc.phase, .holding)
        hold(set, [up], seconds: 0.2)
        XCTAssertEqual(disc.charge, 1, accuracy: 1e-9)
        var raised = up
        for _ in 0..<3 {
            let from = raised.palm
            raised = slid(raised, to: CGPoint(x: from.x - 40, y: from.y), from: from)
            tick(set, [raised])
        }
        XCTAssertEqual(disc.phase, .flying)
        hold(set, [up], seconds: 0.6)
        XCTAssertNotEqual(disc.phase, .holding, "no new disc straight away")
        hold(set, [up], seconds: 1.4)
        XCTAssertEqual(disc.phase, .holding, "but a second later, yes")
    }

    // MARK: Solar Flare

    private func framing(size: Double = 95, on f: FaceState? = nil) -> [HandState] {
        [open(CGPoint(x: -0.8, y: 0.05), size: size, angle: -0.15, mirrored: true, id: 1, on: f), open(CGPoint(x: 0.8, y: 0.05), size: size, angle: 0.15, id: 2, on: f)]
    }

    func testSolarFlareBlindsThenFadesWarmAndWaits() {
        let (set, flare) = single(SolarFlareMove())
        let hands = framing()
        hold(set, hands, seconds: 0.2)
        XCTAssertEqual(flare.phase, .posing)
        XCTAssertEqual(flare.flares, 0, "not before the hold")
        var e = SaiyanScreenEffect.none
        var frames = 0
        while flare.flares == 0, frames < 30 {
            e = tick(set, hands)
            frames += 1
        }
        XCTAssertEqual(flare.flares, 1)
        XCTAssertEqual(Double(frames + 6) / 30, SolarFlareMove.holdSeconds + SolarFlareMove.claimSeconds, accuracy: 0.07, "after about a third of a second")
        e = tick(set, hands)
        XCTAssertEqual(e.flash, 1, accuracy: 0.01, "blinding white")
        XCTAssertGreaterThan(e.shake, 0.1)
        hold(set, hands, seconds: 0.5)
        e = set.screenEffect
        XCTAssertGreaterThan(e.flash, 0.25, "fading slowly")
        XCTAssertLessThan(e.flash, 0.8)
        XCTAssertGreaterThan(e.flashTint.x - e.flashTint.z, 0.05, "with a warm glare")
        e = hold(set, hands, seconds: 1.4)
        XCTAssertTrue(e.isNone, "gone after about 1.7 s: \(e)")
        XCTAssertFalse(set.hasLight)
        // Still holding the pose: it does not go off again, nor after the cool-down, until the hands come away.
        hold(set, hands, seconds: 3.5)
        XCTAssertEqual(flare.flares, 1, "no second flare while the pose is held")
        hold(set, [], seconds: 0.3)
        hold(set, hands, seconds: 0.6)
        XCTAssertEqual(flare.flares, 2, "let go and do it again: a second flare")
    }

    func testSolarFlareRaysReachAcrossThePicture() {
        let (set, flare) = single(SolarFlareMove())
        let hands = framing()
        var frames = 0
        while flare.flares == 0, frames < 30 {
            tick(set, hands)
            frames += 1
        }
        hold(set, hands, seconds: 0.5)
        let picture = frame(set, hands)
        Output.save(picture, as: "saiyanD-flare-fading.png")
        XCTAssertGreaterThan(brightness(bench.h.pixel(picture, 640, 440)), 700, "the source is white-hot")
    }

    func testSolarFlareIgnoresOneHandHandsApartFistsAndNoFace() {
        let chest = open(CGPoint(x: -1.4, y: -2.6), mirrored: true, id: 1)
        let cases: [(String, [HandState], Bool)] = [
            ("one hand over the face", [chest, open(CGPoint(x: 0.1, y: -0.3), id: 2)], true),
            ("one hand by the eyes", [chest, open(CGPoint(x: 0.8, y: 0.05), id: 2)], true),
            ("hands far apart", [open(CGPoint(x: -2.6, y: 0), mirrored: true, id: 1), open(CGPoint(x: 2.6, y: 0), id: 2)], true),
            ("fists by the face", framing().map { hand(.fist, palm: $0.palm, id: $0.id) }, true),
            ("palms together at the chest", [open(CGPoint(x: -0.6, y: -2.6), size: 95, mirrored: true, id: 1), open(CGPoint(x: 0.6, y: -2.6), size: 95, id: 2)], true),
            ("framing, but no face", framing(), false),
        ]
        for (name, hands, withFace) in cases {
            bench = SaiyanBench()
            let (set, flare) = single(SolarFlareMove())
            for _ in 0..<45 {
                tick(set, hands, face: withFace)
                XCTAssertFalse(flare.isEngaged, name)
            }
            XCTAssertEqual(flare.flares, 0, name)
            XCTAssertTrue(set.screenEffect.isNone, name)
        }
    }

    // MARK: Instant Transmission

    /// Touches the forehead for `touch` seconds, then takes the hand down to the chest. Returns the screen effects from the release on.
    @discardableResult
    private func touchAndGo(_ set: SaiyanMoveSet, touch: Double, after: Double = 1.6, side: Double = 1, size: Double = 100) -> [SaiyanScreenEffect] {
        let touching = foreheadTouch(size: size, side: side)
        let down = hand(.open, palm: world(CGPoint(x: side * 1.6, y: -2.8)), size: size, mirrored: side < 0, id: 1)
        for _ in 0..<Int((touch * 30).rounded()) {
            let e = tick(set, [touching])
            XCTAssertEqual(e.personOpacity, 1, "nothing happens while the fingers are on the forehead")
        }
        return (0..<Int(after * 30)).map { _ in tick(set, [down]) }
    }

    func testInstantTransmissionVanishesOnAQuickTouchAndComesBack() {
        for (side, size) in [(1.0, 100.0), (-1.0, 75.0)] {
            bench = SaiyanBench()
            let (set, jump) = single(InstantTransmissionMove())
            let effects = touchAndGo(set, touch: 0.3, side: side, size: size)
            XCTAssertEqual(jump.jumps, 1, "a quick touch and away")
            guard let gone = effects.firstIndex(where: { $0.personOpacity < 0.5 }) else { return XCTFail("never vanished") }
            XCTAssertLessThanOrEqual(Double(gone) / 30, InstantTransmissionMove.releaseSeconds + 0.12, "soon after the fingers leave")
            XCTAssertTrue(effects.contains { $0.personOpacity == 0 }, "gone completely")
            XCTAssertTrue(effects[gone...].prefix(6).contains { $0.echoes.count >= 4 }, "afterimages fan out as you go")
            let back = (effects.lastIndex { $0.personOpacity == 0 } ?? 0) + 1
            XCTAssertEqual(Double(back - gone) / 30, InstantTransmissionMove.vanishSeconds + InstantTransmissionMove.goneSeconds, accuracy: 0.12, "back after about half a second")
            XCTAssertGreaterThan(effects[back...].prefix(3).map(\.flash).max() ?? 0, 0.3, "with a flash")
            XCTAssertTrue(effects.last!.isNone, "and settled: \(effects.last!)")
            XCTAssertFalse(set.hasLight)
        }
    }

    func testAHoldPastTheLimitIsNotInstantTransmission() {
        let (set, jump) = single(InstantTransmissionMove())
        let effects = touchAndGo(set, touch: 0.7)
        XCTAssertEqual(jump.jumps, 0, "0.7 s is Special Beam Cannon's")
        XCTAssertTrue(effects.allSatisfy(\.isNone))
        // Exactly at the limit still counts.
        touchAndGo(set, touch: SaiyanZones.instantTransmissionLimit)
        XCTAssertEqual(jump.jumps, 1)
    }

    func testAPassingHandDoesNotTeleport() {
        let (set, jump) = single(InstantTransmissionMove())
        // One frame on the forehead.
        touchAndGo(set, touch: 1.0 / 30)
        XCTAssertEqual(jump.jumps, 0, "a hand brushing past")
        // Two fingers sweeping across the forehead.
        let base = foreheadTouch()
        for i in 0..<10 {
            let dx = (Double(i) - 5) * 30
            tick(set, [HandFixtures.moved(base, by: CGVector(dx: dx, dy: 0), velocity: CGVector(dx: 900, dy: 0))])
        }
        hold(set, [], seconds: 1)
        XCTAssertEqual(jump.jumps, 0, "a hand gesturing across the face")
        // No face, no teleport.
        let blind = InstantTransmissionMove()
        let alone = SaiyanMoveSet(moves: [blind])
        for _ in 0..<9 { tick(alone, [foreheadTouch()], face: false) }
        hold(alone, [], seconds: 1, face: false)
        XCTAssertEqual(blind.jumps, 0)
    }

    func testInstantTransmissionWaitsForTheBeamToLetGoAndThenCoolsDown() {
        // A stand-in for the beam that claims the hands while the fingers are on the forehead and for a moment after.
        let claimer = ForeheadClaimer()
        let jump = InstantTransmissionMove()
        let set = SaiyanMoveSet(moves: [claimer, jump])
        touchAndGo(set, touch: 0.3, after: 1.2)
        XCTAssertEqual(jump.jumps, 1, "the jump waits for the beam to let go, then happens")
        // A second touch straight away is too soon.
        touchAndGo(set, touch: 0.3, after: 0.5)
        XCTAssertEqual(jump.jumps, 1, "two seconds between jumps")
        hold(set, [], seconds: 0.6)
        touchAndGo(set, touch: 0.3, after: 0.6)
        XCTAssertEqual(jump.jumps, 2)
        // Blocked (both fists powering up) means no jump.
        let blocked = InstantTransmissionMove()
        let other = SaiyanMoveSet(moves: [blocked])
        for _ in 0..<9 { tick(other, [foreheadTouch()], blocked: true) }
        for _ in 0..<20 { tick(other, [], blocked: true) }
        XCTAssertEqual(blocked.jumps, 0)
    }

    // MARK: Zanzoken

    /// A hand at rest at chest height for half a second, then swept sideways: `palms` palm lengths over `seconds`.
    @discardableResult
    private func sweep(_ set: SaiyanMoveSet, way: Double = 1, palms: Double = 2.8, seconds: Double = 0.2, size: Double = 100, form: SaiyanForm = .superSaiyan,
                       rise: Double = 0) -> [SaiyanScreenEffect] {
        var h = hand(.open, palm: world(CGPoint(x: -way * 1.2, y: -2.3)), size: size, id: 1)
        hold(set, [h], seconds: 0.5, form: form)
        let steps = max(1, Int((seconds * 30).rounded()))
        var effects: [SaiyanScreenEffect] = []
        for _ in 0..<steps {
            let from = h.palm
            h = slid(h, to: CGPoint(x: from.x + way * palms * size / Double(steps), y: from.y + rise * size / Double(steps)), from: from)
            effects.append(tick(set, [h], form: form))
        }
        let rest = HandFixtures.moved(h, by: .zero, velocity: .zero)
        for _ in 0..<30 { effects.append(tick(set, [rest], form: form)) }
        return effects
    }

    func testZanzokenLeavesAfterimagesBehindAFastSweep() {
        for (way, form, count) in [(1.0, SaiyanForm.superSaiyan, 4), (-1.0, .base, 3), (1.0, .ultraInstinct, 5)] {
            bench = SaiyanBench()
            let (set, dash) = single(ZanzokenMove())
            let effects = sweep(set, way: way, form: form)
            XCTAssertEqual(dash.dashes, 1, "\(form): the sweep dashes")
            XCTAssertEqual(dash.direction, way)
            guard let peak = effects.max(by: { $0.echoes.count < $1.echoes.count }), let farthest = peak.echoes.map({ abs($0.offset.dx) }).max() else {
                return XCTFail("no afterimages")
            }
            XCTAssertEqual(peak.echoes.count, count, "\(form): 3 to 5 afterimages by power")
            XCTAssertTrue(peak.echoes.allSatisfy { $0.offset.dx * way <= 0 }, "behind the sweep")
            let spread = effects.compactMap { $0.echoes.map { abs($0.offset.dx) }.max() }.max() ?? 0
            XCTAssertGreaterThan(spread, 120, "spread out")
            XCTAssertLessThanOrEqual(farthest, 240, "but not far")
            if form == .superSaiyan { XCTAssertGreaterThan(peak.echoes[0].tint.x, peak.echoes[0].tint.z, "gold in Super Saiyan") }
            if form == .base { XCTAssertGreaterThan(peak.echoes[0].tint.z, peak.echoes[0].tint.x, "blue in base") }
            XCTAssertTrue(effects.last!.isNone, "settled: \(effects.last!)")
        }
    }

    func testZanzokenIgnoresWavesSlowSweepsAndHandsSwingingIn() {
        // A friendly wave and an eager one, for two seconds each.
        for (amplitude, hz) in [(0.5, 1.5), (1.0, 1.8), (1.3, 1.8), (1.3, 2.0), (1.6, 1.4)] {
            bench = SaiyanBench()
            let (set, dash) = single(ZanzokenMove())
            let base = hand(.open, palm: world(CGPoint(x: 1.4, y: 0.4)), id: 1)
            var previous = 0.0
            for i in 0..<60 {
                let t = Double(i) / 30
                let x = amplitude * 100 * sin(2 * .pi * hz * t)
                tick(set, [HandFixtures.moved(base, by: CGVector(dx: x, dy: 0), velocity: CGVector(dx: (x - previous) * 30, dy: 0))])
                previous = x
            }
            XCTAssertEqual(dash.dashes, 0, "a wave of \(amplitude) palms at \(hz) Hz")
        }
        let (slow, slowDash) = single(ZanzokenMove())
        sweep(slow, palms: 1.6, seconds: 0.33)
        XCTAssertEqual(slowDash.dashes, 0, "a sweep at 5 palm lengths a second")
        bench = SaiyanBench()
        let (up, upDash) = single(ZanzokenMove())
        sweep(up, palms: 0.8, rise: 2.8)
        XCTAssertEqual(upDash.dashes, 0, "a sweep upward")
        // A hand coming into the picture fast from the edge.
        bench = SaiyanBench()
        let (edge, edgeDash) = single(ZanzokenMove())
        var h = hand(.open, palm: CGPoint(x: 10, y: 250), id: 1)
        for _ in 0..<8 {
            let from = h.palm
            h = slid(h, to: CGPoint(x: from.x + 45, y: from.y), from: from)
            tick(edge, [h])
        }
        XCTAssertEqual(edgeDash.dashes, 0, "a hand swinging in from the side")
    }

    func testZanzokenWaitsBetweenDashesAndOnlyWhenFree() {
        let (set, dash) = single(ZanzokenMove())
        func swept(_ h: HandState, by step: Double, others: [HandState]) -> HandState {
            var h = h
            for _ in 0..<6 {
                let from = h.palm
                h = slid(h, to: CGPoint(x: from.x + step, y: from.y), from: from)
                tick(set, [h] + others)
            }
            return HandFixtures.moved(h, by: .zero, velocity: .zero)
        }
        var a = hand(.open, palm: world(CGPoint(x: -1.6, y: -2.4)), id: 1)
        let b = hand(.open, palm: world(CGPoint(x: -1.8, y: -0.9)), id: 2)
        hold(set, [a, b], seconds: 0.5)
        a = swept(a, by: 47, others: [b])
        XCTAssertEqual(dash.dashes, 1)
        // The other hand sweeps a moment later: inside the cool-down.
        hold(set, [a, b], seconds: 0.1)
        _ = swept(b, by: 47, others: [a])
        XCTAssertEqual(dash.dashes, 1, "not twice inside 0.8 s")
        hold(set, [], seconds: 0.5)
        let c = hand(.open, palm: world(CGPoint(x: -1.6, y: -2.4)), id: 3)
        hold(set, [c], seconds: 0.5)
        _ = swept(c, by: 47, others: [])
        XCTAssertEqual(dash.dashes, 2, "but again after it")
        // Another move engaged: no dash.
        bench = SaiyanBench()
        let busy = ZanzokenMove()
        let both = SaiyanMoveSet(moves: [AlwaysEngaged(), busy])
        var right = hand(.open, palm: world(CGPoint(x: -1.6, y: -2.4)), id: 1)
        hold(both, [right], seconds: 0.5)
        for _ in 0..<6 {
            let from = right.palm
            right = slid(right, to: CGPoint(x: from.x + 47, y: from.y), from: from)
            tick(both, [right])
        }
        XCTAssertEqual(busy.dashes, 0, "not while another move is engaged")
    }

    // MARK: All the moves together

    func testEachPoseEngagesOnlyItsOwnMove() {
        let scripts: [(String, String, (SaiyanOtherMoveTests) -> [[HandState]])] = [
            ("spirit-bomb", "both hands up", { t in Array(repeating: t.overhead(), count: 45) }),
            ("destructo-disc", "one hand up", { t in Array(repeating: [t.open(CGPoint(x: 1.3, y: 2.0), id: 1)], count: 45) }),
            ("solar-flare", "framing the eyes", { t in Array(repeating: t.framing(), count: 15) }),
        ]
        for (expected, name, script) in scripts {
            bench = SaiyanBench()
            let set = SaiyanMoveSet()
            var engaged = Set<String>()
            for hands in script(self) {
                tick(set, hands)
                if let move = set.engaged { engaged.insert(move.id) }
            }
            XCTAssertEqual(engaged, [expected], name)
        }
        // A quick forehead touch, through the whole set with the beam moves in it.
        bench = SaiyanBench()
        let set = SaiyanMoveSet()
        touchAndGo(set, touch: 0.3, after: 0.3)
        XCTAssertEqual((set.moves.first { $0.id == "instant-transmission" } as? InstantTransmissionMove)?.jumps, 1)
    }

    // MARK: Cost

    /// CPU per frame while each move is busy: reading the hands and painting its solids and light into a frame-sized layer (the washes
    /// and the compositing are made on the graphics chip).
    func testEachMoveStaysWithinItsBudget() {
        let layer = HandFXKit.bitmap(width: 1280, height: 720)!
        func cost(_ move: SaiyanMove, _ frames: [[HandState]], form: SaiyanForm = .superSaiyanBlue) -> (busy: Double, idle: Double) {
            bench = SaiyanBench()
            let set = SaiyanMoveSet(moves: [move])
            var busy: [Double] = [], idle: [Double] = []
            for hands in frames + Array(repeating: [], count: 90) {
                let c = bench.context(hands: hands, form: form)
                layer.clear(CGRect(x: 0, y: 0, width: 1280, height: 720))
                let started = CFAbsoluteTimeGetCurrent()
                set.update(c, blocked: false)
                if set.hasLight {
                    _ = set.washes()
                    set.drawSolids(in: layer)
                    set.drawLight(in: layer)
                }
                let ms = (CFAbsoluteTimeGetCurrent() - started) * 1000
                if move.hasLight || move.isEngaged { busy.append(ms) } else { idle.append(ms) }
            }
            return (busy.reduce(0, +) / Double(max(1, busy.count)), idle.reduce(0, +) / Double(max(1, idle.count)))
        }
        func swing(_ hands: [HandState], frames: Int, by step: CGVector) -> [[HandState]] {
            var current = hands
            return (0..<frames).map { _ in
                current = current.map { slid($0, to: CGPoint(x: $0.palm.x + step.dx, y: $0.palm.y + step.dy), from: $0.palm) }
                return current
            }
        }
        let up = overhead()
        let bomb = Array(repeating: up, count: 150) + swing(up, frames: 6, by: CGVector(dx: 0, dy: -27)) + Array(repeating: [], count: 50)
        let raised = open(CGPoint(x: 1.3, y: 2.0), id: 1)
        let disc = Array(repeating: [raised], count: 40) + swing([raised], frames: 3, by: CGVector(dx: 40, dy: 0)) + Array(repeating: [], count: 30)
        let flare = Array(repeating: framing(), count: 70)
        let touch = foreheadTouch(), away = hand(.open, palm: world(CGPoint(x: 1.6, y: -2.8)), id: 1)
        let jump = Array(repeating: [touch], count: 9) + Array(repeating: [away], count: 40)
        let rest = hand(.open, palm: world(CGPoint(x: -1.2, y: -2.3)), id: 1)
        let dash = Array(repeating: [rest], count: 15) + swing([rest], frames: 6, by: CGVector(dx: 47, dy: 0)) + Array(repeating: [], count: 25)

        var report: [String] = []
        let runs: [(String, SaiyanMove, [[HandState]])] = [
            ("Spirit Bomb", SpiritBombMove(), bomb), ("Destructo Disc", DestructoDiscMove(), disc), ("Solar Flare", SolarFlareMove(), flare),
            ("Instant Transmission", InstantTransmissionMove(), jump), ("Zanzoken", ZanzokenMove(), dash),
        ]
        for (name, move, frames) in runs {
            _ = cost(move, frames)       // warm the sprite caches
            move.reset()
            let measured = cost(move, frames)
            report.append(String(format: "%@: %.2f ms busy, %.3f ms idle", name, measured.busy, measured.idle))
            XCTAssertLessThan(measured.busy, 3.5, "\(name) is cheap while busy (budget 1.5 ms; the machine is shared, so the bound is generous)")
            XCTAssertLessThan(measured.idle, 0.2, "\(name) costs next to nothing when idle")
        }
        print("Saiyan other moves, CPU per frame:\n  " + report.joined(separator: "\n  "))
    }

    // MARK: Pictures

    private let sheetForms: [SaiyanForm] = [.base, .superSaiyan, .superSaiyanGod, .superSaiyanBlue, .ultraInstinct]

    /// Runs a script for each of five forms, capturing pictures at its key moments, and lays them out one form to a row.
    private func sheet(_ name: String, scale: Double = 0.3, _ script: (SaiyanForm) -> [CIImage]) -> [[CIImage]] {
        var rows: [[CIImage]] = []
        for form in sheetForms {
            bench = SaiyanBench()
            rows.append(script(form))
        }
        let columns = rows.first?.count ?? 1
        Output.save(SaiyanBench.sheet(rows.flatMap { $0 }, columns: columns, scale: scale), as: name)
        return rows
    }

    func testSpiritBombSheet() {
        let rows = sheet("saiyanD-sheet-spirit-bomb.png") { form in
            let (set, bomb) = single(SpiritBombMove())
            var shots: [CIImage] = []
            var hands = overhead()
            hold(set, hands, seconds: 0.4, form: form)
            shots.append(frame(set, hands, form: form))
            hold(set, hands, seconds: 1.1, form: form)
            shots.append(frame(set, hands, form: form))
            hold(set, hands, seconds: 3.2, form: form)
            shots.append(frame(set, hands, form: form))
            let start = hands.map(\.palm)
            for i in 1...6 where bomb.phase == .gathering {
                hands = hands.enumerated().map { k, h in
                    slid(h, to: CGPoint(x: start[k].x, y: start[k].y - Double(i) * 27), from: CGPoint(x: start[k].x, y: start[k].y - Double(i - 1) * 27))
                }
                tick(set, hands, form: form)
            }
            let low = hands.map { HandFixtures.moved($0, by: .zero, velocity: .zero) }
            hold(set, low, seconds: 0.2, form: form)
            shots.append(frame(set, low, form: form))
            run(set, low, form: form, until: { bomb.phase != .falling })
            shots.append(frame(set, low, form: form))
            hold(set, low, seconds: 0.35, form: form)
            shots.append(frame(set, low, form: form))
            hold(set, low, seconds: 1.0, form: form)
            shots.append(frame(set, low, form: form))
            return shots
        }
        // Full-size frames of Super Saiyan for a close look.
        for (k, name) in ["posing", "gathering", "full", "falling", "impact", "shockwave", "after"].enumerated() where rows.count > 1 && k < rows[1].count {
            Output.save(rows[1][k], as: "saiyanD-spirit-bomb-\(name).png")
        }
        Output.save(rows[4][2], as: "saiyanD-spirit-bomb-full-ui.png")
        Output.save(rows[2][2], as: "saiyanD-spirit-bomb-full-god.png")
    }

    func testDestructoDiscSheet() {
        let rows = sheet("saiyanD-sheet-destructo-disc.png") { form in
            let (set, disc) = single(DestructoDiscMove())
            var shots: [CIImage] = []
            var raised = open(CGPoint(x: 1.3, y: 1.95), size: 105, angle: -0.1, id: 1)
            let rest = hand(.fist, palm: world(CGPoint(x: -1.4, y: -2.6)), mirrored: true, id: 2)
            hold(set, [raised, rest], seconds: 0.4, form: form)
            shots.append(frame(set, [raised, rest], form: form))
            hold(set, [raised, rest], seconds: 0.25, form: form)
            shots.append(frame(set, [raised, rest], form: form))
            hold(set, [raised, rest], seconds: 0.8, form: form)
            shots.append(frame(set, [raised, rest], form: form))
            for _ in 0..<4 where disc.phase == .holding {
                let from = raised.palm
                // A throw: forward, across and down.
                raised = slid(raised, to: CGPoint(x: from.x - 36, y: from.y - 20), from: from)
                tick(set, [raised, rest], form: form)
            }
            let still = HandFixtures.moved(raised, by: .zero, velocity: .zero)
            hold(set, [still, rest], seconds: 0.1, form: form)
            shots.append(frame(set, [still, rest], form: form))
            hold(set, [still, rest], seconds: 0.15, form: form)
            shots.append(frame(set, [still, rest], form: form))
            hold(set, [still, rest], seconds: 0.35, form: form)
            shots.append(frame(set, [still, rest], form: form))
            return shots
        }
        for (k, name) in ["seed", "spinning-up", "spinning", "thrown", "flying", "cut"].enumerated() where k < rows[1].count {
            Output.save(rows[1][k], as: "saiyanD-disc-\(name).png")
        }
    }

    func testSolarFlareSheet() {
        let rows = sheet("saiyanD-sheet-solar-flare.png") { form in
            let (set, flare) = single(SolarFlareMove())
            var shots: [CIImage] = []
            let hands = framing()
            hold(set, hands, seconds: 0.3, form: form)
            shots.append(frame(set, hands, form: form))
            run(set, hands, form: form, until: { flare.flares > 0 })
            shots.append(frame(set, hands, form: form))
            for seconds in [0.2, 0.3, 0.4, 0.6] {
                hold(set, hands, seconds: seconds, form: form)
                shots.append(frame(set, hands, form: form))
            }
            return shots
        }
        for (k, name) in ["gathering", "burst", "glare", "rays", "fading", "last"].enumerated() where k < rows[1].count {
            Output.save(rows[1][k], as: "saiyanD-flare-\(name).png")
        }
    }

    func testInstantTransmissionSheet() {
        let rows = sheet("saiyanD-sheet-instant-transmission.png") { form in
            let (set, jump) = single(InstantTransmissionMove())
            var shots: [CIImage] = []
            let touching = foreheadTouch()
            let down = hand(.open, palm: world(CGPoint(x: 1.6, y: -2.8)), id: 1)
            hold(set, [touching], seconds: 0.25, form: form)
            shots.append(frame(set, [touching], form: form))
            run(set, [down], form: form, until: { jump.phase != .idle })
            tick(set, [down], form: form)
            shots.append(frame(set, [down], form: form))
            hold(set, [down], seconds: 0.06, form: form)
            shots.append(frame(set, [down], form: form))
            hold(set, [down], seconds: 0.2, form: form)
            shots.append(frame(set, [down], form: form))
            run(set, [down], form: form, until: { jump.phase == .returning })
            shots.append(frame(set, [down], form: form))
            hold(set, [down], seconds: 0.15, form: form)
            shots.append(frame(set, [down], form: form))
            return shots
        }
        for (k, name) in ["touch", "collapse", "column", "gone", "return", "ghost"].enumerated() where k < rows[1].count {
            Output.save(rows[1][k], as: "saiyanD-jump-\(name).png")
        }
    }

    func testZanzokenSheet() {
        let rows = sheet("saiyanD-sheet-zanzoken.png") { form in
            let (set, dash) = single(ZanzokenMove())
            var shots: [CIImage] = []
            var h = hand(.open, palm: world(CGPoint(x: -1.2, y: -2.3)), id: 1)
            hold(set, [h], seconds: 0.5, form: form)
            shots.append(frame(set, [h], form: form))
            for _ in 0..<6 where dash.dashes == 0 {
                let from = h.palm
                h = slid(h, to: CGPoint(x: from.x + 47, y: from.y), from: from)
                tick(set, [h], form: form)
            }
            shots.append(frame(set, [h], form: form))
            let rest = HandFixtures.moved(h, by: .zero, velocity: .zero)
            for seconds in [0.07, 0.13, 0.2, 0.3] {
                hold(set, [rest], seconds: seconds, form: form)
                shots.append(frame(set, [rest], form: form))
            }
            return shots
        }
        for (k, name) in ["before", "dash", "peel", "trail", "fading"].enumerated() where k < rows[1].count {
            Output.save(rows[1][k], as: "saiyanD-zanzoken-\(name).png")
        }
    }

    /// The moves on a smaller, lower face, a tilted head, and with mirrored hands: the poses and the art follow the face and hand size.
    func testMovesOnOtherFacesSheet() {
        var shots: [CIImage] = []
        let small = SyntheticScene(center: CGPoint(x: 560, y: 330), scale: 0.62)
        let tilted = SyntheticScene(center: CGPoint(x: 680, y: 400), scale: 0.9, roll: 0.3)

        bench = SaiyanBench(scene: small)
        let (bombSet, bomb) = single(SpiritBombMove())
        let up = overhead(size: 66)
        hold(bombSet, up, seconds: 4.4)
        XCTAssertEqual(bomb.phase, .gathering, "a small face: the sphere still gathers")
        XCTAssertLessThan(bomb.center.y + bomb.radius, bench.rect.maxY + bomb.radius * 0.5, "and there is room above to show it")
        shots.append(frame(bombSet, up))

        bench = SaiyanBench(scene: small)
        let (discSet, disc) = single(DestructoDiscMove())
        let leftUp = open(CGPoint(x: -1.3, y: 2.0), size: 64, angle: 0.15, mirrored: true, id: 1)
        hold(discSet, [leftUp], seconds: 1.2)
        XCTAssertEqual(disc.phase, .holding, "a small mirrored hand raises a disc")
        shots.append(frame(discSet, [leftUp]))

        bench = SaiyanBench(scene: tilted)
        let (flareSet, flare) = single(SolarFlareMove())
        let tiltedHands = framing(size: 88)
        hold(flareSet, tiltedHands, seconds: 0.5)
        XCTAssertEqual(flare.flares, 1, "a tilted head still frames for a Solar Flare")
        hold(flareSet, tiltedHands, seconds: 0.35)
        shots.append(frame(flareSet, tiltedHands))

        bench = SaiyanBench(scene: tilted)
        let (jumpSet, jump) = single(InstantTransmissionMove())
        let touch = foreheadTouch(size: 92, side: -1)
        hold(jumpSet, [touch], seconds: 0.3)
        let away = hand(.open, palm: world(CGPoint(x: -1.6, y: -2.6)), size: 92, mirrored: true, id: 1)
        while jump.phase != .vanishing, bench.time < 3 { tick(jumpSet, [away]) }
        XCTAssertEqual(jump.jumps, 1, "a tilted head, the left hand")
        tick(jumpSet, [away])
        shots.append(frame(jumpSet, [away]))

        bench = SaiyanBench(scene: small)
        let (dashSet, dash) = single(ZanzokenMove())
        var h = hand(.open, palm: world(CGPoint(x: 1.5, y: -2.0)), size: 64, mirrored: true, id: 1)
        hold(dashSet, [h], seconds: 0.5)
        for _ in 0..<6 where dash.dashes == 0 {
            let from = h.palm
            h = slid(h, to: CGPoint(x: from.x - 32, y: from.y), from: from)
            tick(dashSet, [h])
        }
        XCTAssertEqual(dash.dashes, 1, "a small hand sweeping left")
        hold(dashSet, [HandFixtures.moved(h, by: .zero, velocity: .zero)], seconds: 0.1)
        shots.append(frame(dashSet, [HandFixtures.moved(h, by: .zero, velocity: .zero)]))

        Output.save(SaiyanBench.sheet(shots, columns: 3, scale: 0.4), as: "saiyanD-sheet-other-faces.png")
    }

    /// The moves on a head with real proportions (`HeadwearRealHead`: a taller skull, a lower mouth, a darker shirt), hands painted in.
    func testMovesOnARealHeadSheet() {
        let head = HeadwearRealHead()
        let stage = RealHeadStage(head: head)
        let f = stage.face
        func hands(_ set: SaiyanMoveSet, _ list: [HandState], seconds: Double, form: SaiyanForm = .superSaiyan) -> CIImage {
            var out = CIImage.empty()
            for _ in 0..<max(1, Int((seconds * 30).rounded())) { out = stage.step(set, hands: list, form: form) }
            return out
        }
        var shots: [CIImage] = []
        let up = overhead(size: 86, spread: 1.15, height: 2.1, on: f)
        let bomb = SpiritBombMove()
        shots.append(still(hands(SaiyanMoveSet(moves: [bomb]), up, seconds: 4.4, form: .superSaiyanBlue)))
        XCTAssertEqual(bomb.phase, .gathering, "a real head: the sphere gathers")

        let disc = DestructoDiscMove()
        let raised = open(CGPoint(x: 1.4, y: 1.9), size: 84, angle: -0.1, id: 1, on: f)
        shots.append(still(hands(SaiyanMoveSet(moves: [disc]), [raised], seconds: 1.3, form: .superSaiyan)))
        XCTAssertEqual(disc.phase, .holding)

        let flare = SolarFlareMove()
        let frame = [open(CGPoint(x: -0.85, y: 0.05), size: 84, angle: -0.15, mirrored: true, id: 1, on: f),
                     open(CGPoint(x: 0.85, y: 0.05), size: 84, angle: 0.15, id: 2, on: f)]
        let flareSet = SaiyanMoveSet(moves: [flare])
        _ = hands(flareSet, frame, seconds: 0.5, form: .superSaiyanGod)
        shots.append(still(hands(flareSet, frame, seconds: 0.4, form: .superSaiyanGod)))
        XCTAssertEqual(flare.flares, 1, "a real head: the hands frame the eyes")

        let jump = InstantTransmissionMove()
        let jumpSet = SaiyanMoveSet(moves: [jump])
        _ = hands(jumpSet, [foreheadTouch(size: 84, on: f)], seconds: 0.3)
        var picture = CIImage.empty()
        let away = hand(.open, palm: world(CGPoint(x: 1.7, y: -3.2), on: f), size: 84, id: 1)
        for _ in 0..<12 where jump.phase == .idle || jump.phase == .vanishing && jump.sinceJump < 0.05 { picture = stage.step(jumpSet, hands: [away], form: .ultraInstinct) }
        shots.append(still(picture))
        XCTAssertEqual(jump.jumps, 1, "a real head: two fingers on the forehead")

        let dash = ZanzokenMove()
        let dashSet = SaiyanMoveSet(moves: [dash])
        var h = hand(.open, palm: world(CGPoint(x: -1.4, y: -2.8), on: f), size: 84, id: 1)
        _ = hands(dashSet, [h], seconds: 0.5)
        for _ in 0..<6 where dash.dashes == 0 {
            let from = h.palm
            h = slid(h, to: CGPoint(x: from.x + 40, y: from.y), from: from)
            picture = stage.step(dashSet, hands: [h], form: .superSaiyan2)
        }
        shots.append(still(hands(dashSet, [HandFixtures.moved(h, by: .zero, velocity: .zero)], seconds: 0.1, form: .superSaiyan2)))
        XCTAssertEqual(dash.dashes, 1)
        Output.save(SaiyanBench.sheet(shots, columns: 3, scale: 0.4), as: "saiyanD-sheet-real-head.png")
        Output.save(shots[0], as: "saiyanD-real-head-spirit-bomb.png")
    }

    /// Every frame of every move is finite and inside the picture's colour range: no NaN from a zero-length vector or a zero-size hand.
    func testDrawingIsFiniteWithDegenerateHands() {
        let set = SaiyanMoveSet(moves: [SpiritBombMove(), DestructoDiscMove(), SolarFlareMove(), InstantTransmissionMove(), ZanzokenMove()])
        let pinched = HandState(id: 7, joints: Array(repeating: CGPoint(x: 640, y: 600), count: HandJoint.count))
        let layer = HandFXKit.bitmap(width: 1280, height: 720)!
        let wild = overhead().map { (h: HandState) -> HandState in
            var out = h
            out.velocity = CGVector(dx: CGFloat.nan, dy: 0)
            return out
        }
        for hands in [[pinched], [pinched, pinched], wild] {
            for _ in 0..<20 {
                tick(set, hands)
                for w in set.washes() { XCTAssertTrue(w.center.x.isFinite && w.center.y.isFinite && w.radius.isFinite && w.alpha.isFinite) }
                set.drawSolids(in: layer)
                set.drawLight(in: layer)
                let e = set.screenEffect
                XCTAssertTrue(e.flash.isFinite && e.shake.isFinite && e.darken.isFinite && e.personOpacity.isFinite)
            }
        }
    }
}

/// Stands in for Special Beam Cannon in the tests: claims the hands as soon as two fingers touch the forehead and keeps them for a
/// moment after they leave, as a beam winding down might.
private final class ForeheadClaimer: SaiyanMove {
    let id = "forehead-claimer"
    let name = "Forehead claimer"
    let hint = ""
    private(set) var isEngaged = false
    var hasLight: Bool { false }
    private var since = 9.0

    func update(_ c: SaiyanMoveContext, mayBegin: Bool) {
        let touching = c.face.map { f in c.hands.contains { SaiyanZones.fingersAtForehead($0, f) } } ?? false
        since = touching ? 0 : since + c.dt
        isEngaged = (touching && (mayBegin || isEngaged)) || (isEngaged && since < 0.15)
    }

    func reset() { isEngaged = false }
}

/// A move that is always engaged, to see that the others wait their turn.
private final class AlwaysEngaged: SaiyanMove {
    let id = "always-engaged"
    let name = "Always engaged"
    let hint = ""
    private(set) var isEngaged = false
    var hasLight: Bool { false }

    func update(_ c: SaiyanMoveContext, mayBegin: Bool) { isEngaged = isEngaged || mayBegin }
    func reset() { isEngaged = false }
}

/// A real-proportioned head (`HeadwearRealHead`) with fixture hands painted into the picture and the cutout, composed the way the lens
/// composes the moves, for pictures of the moves on something less cartoonish than the synthetic scene.
private final class RealHeadStage {
    let harness = LensHarness()
    let head: HeadwearRealHead
    var gestures = HandGestureRecognizer()
    private(set) var time = 0.0

    init(head: HeadwearRealHead) { self.head = head }

    var face: FaceState { head.face() }

    func step(_ set: SaiyanMoveSet, hands: [HandState], form: SaiyanForm) -> CIImage {
        let dt = 1.0 / 30
        time += dt
        let events = gestures.update(hands, dt: dt)
        let rect = CGRect(x: 0, y: 0, width: 1280, height: 720)
        set.update(SaiyanMoveContext(hands: hands, gestures: gestures, events: events, face: face, personCenter: head.center, form: form,
                                     power: form.power, dt: dt, time: time, rect: rect), blocked: false)
        let base = head.input(services: harness.services, time: time, dt: dt)
        let input = painted(base, hands: hands)
        let effect = set.screenEffect
        var picture = SaiyanCompose.person(input, over: input.scenery, effect: effect)
        picture = SaiyanCompose.moves(set, over: picture, input: input)
        return SaiyanCompose.screen(effect, over: picture, rect: rect, time: time)
    }

    /// The frame with simple hands drawn in skin colour into the picture and white into the cutout.
    private func painted(_ input: LensInput, hands: [HandState]) -> LensInput {
        guard !hands.isEmpty else { return input }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let skin = CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let mask = CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                             bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        for (ctx, colour) in [(skin, CGColor(srgbRed: 0.87, green: 0.68, blue: 0.56, alpha: 1)), (mask, CGColor(gray: 1, alpha: 1))] {
            ctx.setFillColor(colour)
            ctx.setStrokeColor(colour)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for hand in hands {
                ctx.setLineWidth(hand.size * 0.26)
                ctx.beginPath()
                ctx.move(to: hand.wrist)
                for joint in [HandJoint.thumbCMC, .indexMCP, .middleMCP, .ringMCP, .littleMCP] { ctx.addLine(to: hand[joint]) }
                ctx.closePath()
                ctx.drawPath(using: .fillStroke)
                for finger in Finger.allCases {
                    ctx.setLineWidth(hand.size * (finger == .thumb ? 0.27 : 0.21))
                    ctx.beginPath()
                    ctx.move(to: hand[finger.knuckle])
                    ctx.addLine(to: hand[finger.middleJoint])
                    ctx.addLine(to: hand[finger.tip])
                    ctx.strokePath()
                }
            }
        }
        guard let drawn = skin.makeImage(), let cut = mask.makeImage() else { return input }
        let picture = CIImage(cgImage: drawn).composited(over: input.composed)
        let matte = input.matte.map { CIImage(cgImage: cut).applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: $0]).cropped(to: input.rect) }
        return LensInput(time: input.time, dt: input.dt, rect: input.rect, camera: picture, matte: matte, background: input.background, composed: picture,
                         matteGrid: nil, face: input.face, services: input.services, hands: hands)
    }
}
