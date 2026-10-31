import CoreImage
import XCTest

/// The ten hand filters added in round two: how each reacts to the right hand pose, how it lets go, and pictures of each.
final class HandFilterNewTests: XCTestCase {
    private let h = LensHarness()
    private lazy var base = h.input()
    private var frame = 0

    private func brightness(_ p: RGB) -> Int { p.r + p.g + p.b }
    private func plainBrightness(_ x: Int, _ y: Int) -> Int { brightness(h.pixel(base.composed, x, y)) }
    private func changed(_ out: CIImage) -> Int { h.bitmap(out).change(from: h.bitmap(base.composed), in: base.rect) }

    @discardableResult
    private func step(_ lens: Lens, _ hands: [HandState], dt: Double = 1.0 / 30, picture: Bool = false) -> CIImage {
        defer { frame += 1 }
        let time = Double(frame) / 30
        return lens.render(picture ? handPicture(hands, time: time, dt: dt) : h.at(base, time: time, dt: dt, hands: hands))
    }

    @discardableResult
    private func run(_ lens: Lens, _ hands: [HandState], frames: Int, picture: Bool = false) -> CIImage {
        var out = base.composed
        for _ in 0..<frames { out = step(lens, hands, picture: picture) }
        return out
    }

    private func open(at wrist: CGPoint = CGPoint(x: 640, y: 200), size: Double = 120, angle: Double = 0, mirrored: Bool = false, id: Int = 1,
                      velocity: CGVector = .zero) -> HandState {
        HandFixtures.hand(.open, at: wrist, size: size, angle: angle, mirrored: mirrored, id: id, velocity: velocity)
    }

    private func fist(at wrist: CGPoint = CGPoint(x: 640, y: 200), size: Double = 120, angle: Double = 0, mirrored: Bool = false, id: Int = 1) -> HandState {
        HandFixtures.hand(.fist, at: wrist, size: size, angle: angle, mirrored: mirrored, id: id)
    }

    private func make(_ id: String) -> Lens { HandFilters.all.first { $0.id == id }!.make() }

    // MARK: Fire Hands

    func testFireHandsBurnOnAnOpenHandAndGoOutInAFist() {
        let lens = FireHandsLens()
        let palm = open(at: CGPoint(x: 400, y: 160), size: 120)
        var out = run(lens, [palm], frames: 30, picture: true)
        Output.save(out, as: "new-fire-one.png")
        XCTAssertGreaterThan(lens.burn, 0.8, "an open hand burns")
        XCTAssertEqual(lens.ignitions, 1, "it caught once, with a whoosh")
        XCTAssertGreaterThan(lens.particleCount, 40)
        // Flame rises above the fingertips.
        let tip = palm[.middleTip]
        let above = h.average(out, CGRect(x: tip.x - 40, y: tip.y + 10, width: 80, height: 80))
        let plain = h.average(base.composed, CGRect(x: tip.x - 40, y: tip.y + 10, width: 80, height: 80))
        XCTAssertGreaterThan(above.r - plain.r, 0.15, "warm light above the fingers")
        XCTAssertGreaterThan(above.r - plain.r, above.b - plain.b, "and it is orange, not blue")
        XCTAssertEqual(lens.status?.title, "On fire!")

        let closed = HandFixtures.hand(.fist, at: palm.wrist, size: 120)
        out = run(lens, [closed], frames: 8, picture: true)
        Output.save(out, as: "new-fire-snuffed.png")
        run(lens, [closed], frames: 30)
        XCTAssertLessThan(lens.burn, 0.05, "a fist puts it out")
        XCTAssertEqual(lens.status?.title, "Open your hand")

        // Two hands, both burning.
        let two = FireHandsLens()
        out = run(two, [open(at: CGPoint(x: 330, y: 150), id: 1), open(at: CGPoint(x: 960, y: 150), size: 110, mirrored: true, id: 2)], frames: 30, picture: true)
        Output.save(out, as: "new-fire-two.png")
        XCTAssertEqual(two.ignitions, 2)
    }

    func testFireDiesDownGracefullyWhenTheHandIsLost() {
        let lens = FireHandsLens()
        run(lens, [open()], frames: 30)
        let count = lens.particleCount
        step(lens, [])
        XCTAssertGreaterThan(lens.particleCount, count / 2, "the flames already burning carry on for a moment")
        run(lens, [], frames: 90)
        XCTAssertEqual(lens.particleCount, 0)
        XCTAssertEqual(changed(step(lens, [])), 0, "and then the picture is clean")
    }

    // MARK: Light Blade

    func testAFistHoldsABladeThatSpringsOutAndAnOpenHandPutsItAway() {
        let lens = LightBladeLens()
        let hand = fist(at: CGPoint(x: 500, y: 120), size: 110, angle: -0.35)
        step(lens, [hand])
        run(lens, [hand], frames: 3)
        let early = lens.blades.first.map { HandFXKit.distance($0.base, $0.tip) } ?? 0
        let out = run(lens, [hand], frames: 20, picture: true)
        Output.save(out, as: "new-blade-one.png")
        guard let blade = lens.blades.first else { return XCTFail("no blade") }
        let length = HandFXKit.distance(blade.base, blade.tip)
        XCTAssertEqual(length, LightBladeRig.length(for: hand), accuracy: 12, "full length once it has settled")
        XCTAssertLessThan(early, length, "it grows out rather than appearing")
        // It points the way the fist does: from the wrist through the knuckles.
        let up = HandFXKit.up(of: hand)
        XCTAssertGreaterThan(blade.direction.x * up.x + blade.direction.y * up.y, 0.99)
        let mid = HandFXKit.lerp(blade.base, blade.tip, 0.6)
        XCTAssertGreaterThan(brightness(h.pixel(out, Int(mid.x), Int(mid.y))), 700, "white-hot along the middle")
        XCTAssertEqual(lens.status?.title, "Swing it!")

        let opened = open(at: hand.wrist, size: 110, angle: -0.35)
        run(lens, [opened], frames: 25)
        XCTAssertTrue(lens.blades.isEmpty, "an open hand puts it away")
    }

    func testTwoBladesThatCrossThrowSparksAndAFlickerDoesNotDouseThem() {
        let lens = LightBladeLens()
        let a = fist(at: CGPoint(x: 420, y: 120), size: 110, angle: -0.6, id: 1)
        let b = fist(at: CGPoint(x: 860, y: 120), size: 110, angle: 0.6, mirrored: true, id: 2)
        let out = run(lens, [a, b], frames: 24, picture: true)
        Output.save(out, as: "new-blade-two.png")
        XCTAssertEqual(lens.blades.count, 2)
        XCTAssertNotEqual(lens.blades[0].colour, lens.blades[1].colour, "each has its own colour")
        XCTAssertGreaterThan(lens.clashes, 0, "the crossed blades spark")
        // One frame of a half-open hand does not put the blade away.
        let flicker = HandFixtures.hand(HandFixtures.Fingers(index: true, middle: false, ring: false, little: false, thumb: 0), at: a.wrist, size: 110, angle: -0.6, id: 1)
        step(lens, [flicker, b])
        step(lens, [a, b])
        run(lens, [a, b], frames: 4)
        XCTAssertGreaterThan(lens.blades.first { $0.hand == 1 }?.strength ?? 0, 0.9)
    }

    func testABladeSwungFastLeavesATrailAndALostHandRetractsIt() {
        let lens = LightBladeLens()
        var out = base.composed
        for i in 0..<16 {
            let angle = -0.9 + Double(i) * 0.12
            let hand = fist(at: CGPoint(x: 640, y: 110), size: 110, angle: angle)
            out = step(lens, [hand], picture: true)
        }
        Output.save(out, as: "new-blade-swing.png")
        run(lens, [], frames: 30)
        XCTAssertTrue(lens.blades.isEmpty)
        XCTAssertEqual(changed(step(lens, [])), 0)
    }

    // MARK: Frost Hands

    func testAStillHandFreezesAndAShakeShattersTheIce() {
        let lens = FrostHandsLens()
        let palm = open(at: CGPoint(x: 420, y: 170), size: 125)
        var out = run(lens, [palm], frames: 40, picture: true)
        Output.save(out, as: "new-frost-half.png")
        XCTAssertGreaterThan(lens.frost, 0.35)
        XCTAssertLessThan(lens.frost, 0.6, "it takes a few seconds to cover the hand")
        out = run(lens, [palm], frames: 60, picture: true)
        Output.save(out, as: "new-frost-full.png")
        XCTAssertGreaterThan(lens.frost, 0.95)
        XCTAssertEqual(lens.status?.title, "Frozen solid")

        // Waving about gently does not shatter it; a hard shake does.
        for i in 0..<10 { step(lens, [HandFixtures.moved(palm, by: CGVector(dx: Double(i) * 4, dy: 0), velocity: CGVector(dx: 120, dy: 0))]) }
        XCTAssertEqual(lens.shatters, 0)
        step(lens, [HandFixtures.moved(palm, by: CGVector(dx: 50, dy: 0), velocity: CGVector(dx: 1800, dy: 200))])
        XCTAssertEqual(lens.shatters, 1)
        XCTAssertGreaterThan(lens.shardCount, 15, "shards fly from every crystal")
        XCTAssertLessThan(lens.frost, 0.01)
        out = run(lens, [palm], frames: 6, picture: true)
        Output.save(out, as: "new-frost-shatter.png")
        step(lens, [HandFixtures.moved(palm, by: .zero, velocity: CGVector(dx: -1800, dy: 0))])
        XCTAssertEqual(lens.shatters, 1, "nothing to shatter straight after")
    }

    // MARK: Magic Wand

    private func pointing(at tip: CGPoint, size: Double = 110, angle: Double = 0, id: Int = 1) -> HandState {
        let hand = HandFixtures.hand(.point, at: CGPoint(x: 640, y: 200), size: size, angle: angle, id: id)
        return HandFixtures.moved(hand, by: CGVector(dx: tip.x - hand.indexTip.x, dy: tip.y - hand.indexTip.y))
    }

    func testAPointedFingerHoldsAWandThatSparklesAndAFlickCastsASpell() {
        let lens = MagicWandLens()
        let hand = pointing(at: CGPoint(x: 560, y: 380), angle: -0.5)
        var out = run(lens, [hand], frames: 20, picture: true)
        Output.save(out, as: "new-wand-still.png")
        guard let wand = lens.wands.first else { return XCTFail("no wand") }
        XCTAssertGreaterThan(wand.strength, 0.95)
        // The star is out beyond the fingertip, along the finger.
        let along = (Double(wand.star.x - hand.indexTip.x) * Double(hand.aim.dx) + Double(wand.star.y - hand.indexTip.y) * Double(hand.aim.dy))
        XCTAssertGreaterThan(along, 100, "the wand reaches out past the finger")
        XCTAssertEqual(lens.casts, 0, "holding still casts nothing")
        XCTAssertEqual(lens.status?.title, "Abracadabra")

        // Sweep it and it sheds sparkles; flick it and a spell goes off.
        let calm = lens.sparkleCount
        for i in 0..<10 { step(lens, [HandFixtures.moved(hand, by: CGVector(dx: Double(i) * 12, dy: 0))]) }
        XCTAssertGreaterThan(lens.sparkleCount, calm, "moving sheds more sparkles")
        XCTAssertEqual(lens.casts, 0, "a gentle sweep is not a flick")
        for i in 0..<4 { out = step(lens, [HandFixtures.moved(hand, by: CGVector(dx: 120 + Double(i) * 70, dy: 40 + Double(i) * 30))], picture: true) }
        XCTAssertEqual(lens.casts, 1, "a quick flick casts once")
        out = run(lens, [HandFixtures.moved(hand, by: CGVector(dx: 330, dy: 130))], frames: 5, picture: true)
        Output.save(out, as: "new-wand-cast.png")

        // An open hand puts the wand away.
        run(lens, [open(at: CGPoint(x: 700, y: 200))], frames: 25)
        XCTAssertTrue(lens.wands.isEmpty)
    }

    // MARK: Black Hole

    func testABlackHoleOpensBetweenTwoHandsAndGrowsAsTheySpread() {
        let lens = BlackHoleLens()
        let a = open(at: CGPoint(x: 330, y: 170), size: 115, angle: -0.2, id: 1), b = open(at: CGPoint(x: 950, y: 170), size: 115, angle: 0.2, mirrored: true, id: 2)
        let out = run(lens, [a, b], frames: 40, picture: true)
        Output.save(out, as: "new-blackhole-two.png")
        guard let c = lens.centre else { return XCTFail("no hole") }
        let middle = HandFXKit.lerp(a.palm, b.palm, 0.5)
        XCTAssertEqual(c.x, middle.x, accuracy: 6)
        XCTAssertEqual(c.y, middle.y, accuracy: 6)
        let wide = lens.radius
        XCTAssertEqual(wide, HandFXKit.distance(a.palm, b.palm) * 0.17, accuracy: 6)
        XCTAssertLessThan(brightness(h.pixel(out, Int(c.x), Int(c.y))), 90, "dark at its heart")
        XCTAssertEqual(lens.status?.title, "Spread your hands")

        // Hands closer together: a smaller hole.
        let a2 = open(at: CGPoint(x: 480, y: 170), size: 115, angle: -0.2, id: 1), b2 = open(at: CGPoint(x: 800, y: 170), size: 115, angle: 0.2, mirrored: true, id: 2)
        run(lens, [a2, b2], frames: 30)
        XCTAssertLessThan(lens.radius, wide * 0.7)

        // One hand: a small one over the palm. None: it collapses.
        let one = run(lens, [a2], frames: 30, picture: true)
        Output.save(one, as: "new-blackhole-one.png")
        XCTAssertLessThan(lens.radius, 40)
        XCTAssertEqual(lens.status?.title, "Bring your other hand in")
        run(lens, [], frames: 40)
        XCTAssertLessThan(lens.radius, 1)
        run(lens, [], frames: 30)
        XCTAssertEqual(changed(step(lens, [])), 0)
    }

    // MARK: Shockwave

    func testAClapSendsOneShockwaveAndSlowHandsSendNone() {
        let lens = ShockwaveLens()
        func pair(gap: Double) -> [HandState] {
            [open(at: CGPoint(x: 640 - gap / 2 - 50, y: 170), size: 110, angle: -0.3, id: 1),
             open(at: CGPoint(x: 640 + gap / 2 + 50, y: 170), size: 110, angle: 0.3, mirrored: true, id: 2)]
        }
        // Brought together slowly: no clap.
        for i in 0..<60 { step(lens, pair(gap: 500 - Double(i) * 7)) }
        XCTAssertEqual(lens.claps, 0, "hands drifting together are not a clap")
        run(lens, pair(gap: 600), frames: 20)
        // Brought together fast: one clap.
        var out = base.composed
        for i in 0..<8 { out = step(lens, pair(gap: max(0, 600 - Double(i) * 85)), picture: true) }
        Output.save(out, as: "new-shockwave-gather.png")
        XCTAssertEqual(lens.claps, 1)
        XCTAssertFalse(lens.waves.isEmpty)
        out = run(lens, pair(gap: 0), frames: 9, picture: true)
        Output.save(out, as: "new-shockwave-wave.png")
        XCTAssertEqual(lens.claps, 1, "one clap, one wave")
        XCTAssertEqual(lens.status?.title, "Boom!")
        run(lens, [], frames: 60)
        XCTAssertTrue(lens.waves.isEmpty, "the wave has crossed the picture")
    }

    func testAPalmPushedAtTheCameraOrHandsThatVanishAsTheyMeetAlsoSendAWave() {
        let push = ShockwaveLens()
        run(push, [open(at: CGPoint(x: 640, y: 200), size: 100)], frames: 15)
        for i in 0..<6 { step(push, [open(at: CGPoint(x: 640, y: 200 - Double(i) * 8), size: 100 + Double(i) * 9)]) }
        XCTAssertEqual(push.pushes, 1)
        // A palm that only wobbles in size a little does nothing.
        let steady = ShockwaveLens()
        for i in 0..<40 { step(steady, [open(at: CGPoint(x: 640, y: 200), size: 100 + (i % 2 == 0 ? 5 : -5))]) }
        XCTAssertEqual(steady.pushes, 0)
        // Two hands closing fast, then one is lost just before they touch: still a clap.
        let lost = ShockwaveLens()
        for i in 0..<7 {
            let gap = 520 - Double(i) * 60
            step(lost, [open(at: CGPoint(x: 590 - gap / 2, y: 170), size: 110, id: 1), open(at: CGPoint(x: 690 + gap / 2, y: 170), size: 110, mirrored: true, id: 2)])
        }
        XCTAssertEqual(lost.claps, 0)
        step(lost, [open(at: CGPoint(x: 500, y: 170), size: 110, id: 1)])
        XCTAssertEqual(lost.claps, 1)
    }

    // MARK: Magnifier

    func testAThumbAndFingerHeldApartHoldAMagnifyingGlass() {
        let lens = MagnifierLens()
        let hand = HandFixtures.gun(from: CGPoint(x: 560, y: 330), toward: CGPoint(x: 620, y: 600), size: 120)
        XCTAssertGreaterThan(MagnifierRig.holding(hand), 0.8)
        XCTAssertLessThan(MagnifierRig.holding(open()), 0.1, "an open hand is not holding a lens")
        XCTAssertLessThan(MagnifierRig.holding(fist()), 0.1)
        XCTAssertLessThan(MagnifierRig.holding(HandFixtures.hand(.point)), 0.1, "nor is a finger pointing with the thumb tucked in")
        let out = run(lens, [hand], frames: 20, picture: true)
        Output.save(out, as: "new-magnifier.png")
        guard let glass = lens.glasses.first else { return XCTFail("no glass") }
        let expected = MagnifierRig.lens(of: hand)
        XCTAssertEqual(glass.centre.x, expected.centre.x, accuracy: 4)
        XCTAssertEqual(glass.centre.y, expected.centre.y, accuracy: 4)
        XCTAssertEqual(glass.radius, expected.radius, accuracy: 4)
        XCTAssertGreaterThan(glass.show, 0.95)
        // The picture inside the glass is not the plain picture: it is enlarged.
        let inside = CGRect(x: glass.centre.x - glass.radius * 0.5, y: glass.centre.y - glass.radius * 0.5, width: glass.radius, height: glass.radius)
        XCTAssertGreaterThan(h.bitmap(out).change(from: h.bitmap(base.composed), in: inside), 40)
        XCTAssertEqual(lens.status?.title, "Looking closer")
        run(lens, [open()], frames: 30)
        XCTAssertTrue(lens.glasses.isEmpty, "opening the hand puts it away")
    }

    // MARK: Hologram Hand

    func testTheHologramDrawsTheBonesAndReadsOutEachFinger() {
        let lens = HologramHandLens()
        let palm = open(at: CGPoint(x: 420, y: 160), size: 130, angle: -0.15)
        let out = run(lens, [palm], frames: 30, picture: true)
        Output.save(out, as: "new-hologram.png")
        for value in lens.readings[0] { XCTAssertGreaterThan(value, 0.9, "every finger reads open") }
        let bone = HandFXKit.lerp(palm[.middleMCP], palm[.middlePIP], 0.5)
        let lit = h.pixel(out, Int(bone.x), Int(bone.y)), plain = h.pixel(base.composed, Int(bone.x), Int(bone.y))
        XCTAssertGreaterThan(lit.b - plain.b, 20, "a cyan line along the bone")
        let closed = fist(at: palm.wrist, size: 130, angle: -0.15)
        let shut = run(lens, [closed], frames: 30, picture: true)
        Output.save(shut, as: "new-hologram-fist.png")
        for value in lens.readings[0].dropFirst() { XCTAssertLessThan(value, 0.1, "a fist reads closed") }

        // Two hands: each readout sits on the outer side, away from the face.
        let two = HologramHandLens()
        let left = open(at: CGPoint(x: 330, y: 170), size: 120, angle: 0.1, id: 1)
        let right = HandFixtures.hand(HandFixtures.Fingers(index: true, middle: true, ring: false, little: false, thumb: 0), at: CGPoint(x: 950, y: 170),
                                      size: 120, angle: -0.1, mirrored: true, id: 2)
        let both = run(two, [left, right], frames: 30, picture: true)
        Output.save(both, as: "new-hologram-two.png")
        let face = CGRect(x: 545, y: 300, width: 190, height: 240)
        XCTAssertLessThan(h.bitmap(both).change(from: h.bitmap(base.composed), in: face.insetBy(dx: 30, dy: 30)), 60, "nothing much over the face")
    }

    // MARK: Rainbow Ribbon

    func testARibbonHangsSwingsWithTheHandAndFallsAwayWhenLetGo() {
        let lens = RainbowRibbonLens()
        let still = pointing(at: CGPoint(x: 640, y: 560))
        run(lens, [still], frames: 60)
        guard let hanging = lens.ribbons.first else { return XCTFail("no ribbon") }
        XCTAssertEqual(hanging.count, RainbowRibbonRig.count)
        XCTAssertLessThan(hanging.last!.y, hanging.first!.y - 300, "a still ribbon hangs down")
        for i in 1..<hanging.count { XCTAssertEqual(HandFXKit.distance(hanging[i], hanging[i - 1]), RainbowRibbonRig.segment, accuracy: 2.5) }
        var out = base.composed
        for i in 0..<70 {
            let a = Double(i) / 30 * 2 * .pi * 0.9
            out = step(lens, [pointing(at: CGPoint(x: 640 + 190 * cos(a), y: 420 + 150 * sin(a)))], picture: true)
        }
        Output.save(out, as: "new-ribbon.png")
        XCTAssertGreaterThan(changed(out), 200)
        // Let go: it falls and fades away.
        func middle() -> Double { (lens.ribbons.first ?? []).reduce(0) { $0 + Double($1.y) } / Double(max(1, lens.ribbons.first?.count ?? 1)) }
        step(lens, [])
        let held = middle()
        run(lens, [], frames: 28)
        XCTAssertLessThan(middle(), held - 50, "a dropped ribbon drifts down")
        run(lens, [], frames: 20)
        XCTAssertTrue(lens.ribbons.isEmpty)
    }

    // MARK: Bubble Wand

    /// A hand making an "O" with the thumb and index tips together.
    private func ring(at wrist: CGPoint = CGPoint(x: 640, y: 200), size: Double = 120, id: Int = 1) -> HandState {
        var hand = open(at: wrist, size: size, id: id)
        func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: Double(wrist.x) + x * size, y: Double(wrist.y) + y * size) }
        hand.joints[HandJoint.indexPIP.rawValue] = at(0.34, 1.37)
        hand.joints[HandJoint.indexDIP.rawValue] = at(0.5, 1.42)
        hand.joints[HandJoint.indexTip.rawValue] = at(0.63, 1.31)
        hand.joints[HandJoint.thumbIP.rawValue] = at(0.62, 0.7)
        hand.joints[HandJoint.thumbTip.rawValue] = at(0.64, 1.25)
        return hand
    }

    func testARingOfFingerAndThumbBlowsBubblesThatPopWhenPoked() {
        XCTAssertGreaterThan(BubbleWandRig.ringness(of: ring()), 0.8)
        XCTAssertLessThan(BubbleWandRig.ringness(of: fist()), 0.1, "a fist is not a ring")
        XCTAssertLessThan(BubbleWandRig.ringness(of: open()), 0.1)
        let lens = BubbleWandLens()
        run(lens, [ring()], frames: 15)
        XCTAssertGreaterThan(lens.film, 0.9, "a soap film fills the ring")
        var out = base.composed
        for i in 0..<40 {
            let t = Double(i) / 30
            out = step(lens, [HandFixtures.moved(ring(), by: CGVector(dx: 260 * sin(t * 3), dy: 60 * sin(t * 6)))], picture: true)
        }
        Output.save(out, as: "new-bubbles.png")
        XCTAssertGreaterThan(lens.blown, 6, "waving the ring blows bubbles")
        XCTAssertEqual(lens.status?.title, "Wave the ring")
        // A fingertip pokes a bubble and it pops.
        let poke = pointing(at: CGPoint(x: 1000, y: 500), id: 3)
        lens.addBubble(at: CGPoint(x: 1000, y: 500), radius: 40)
        let before = lens.popped
        step(lens, [poke])
        XCTAssertEqual(lens.popped, before + 1)
        // They float off and pop on their own in the end.
        run(lens, [], frames: 330)
        XCTAssertTrue(lens.bubbles.isEmpty)
        XCTAssertEqual(changed(step(lens, [])), 0)
    }

    // MARK: Every new filter

    func testTheNewFiltersAreRegisteredAndDrawNothingWithNoHands() {
        let ids = ["fire-hands", "frost-hands", "light-blade", "magic-wand", "black-hole", "shockwave", "magnifier", "hologram-hand", "rainbow-ribbon", "bubble-wand"]
        XCTAssertEqual(HandFilters.all.count, 15)
        XCTAssertEqual(Array(HandFilters.all.map(\.id).suffix(10)), ids)
        for id in ids {
            guard let info = HandFilters.all.first(where: { $0.id == id }) else { XCTFail("\(id) is missing"); continue }
            XCTAssertTrue(info.needsHands)
            XCTAssertTrue(info.make().needs.contains(.hands))
            let lens = info.make()
            let out = run(lens, [], frames: 10)
            XCTAssertEqual(changed(out), 0, "\(id) leaves the picture alone with no hand")
            XCTAssertTrue(lens.status?.title.hasPrefix("Hold up your hand") ?? false, id)
            XCTAssertEqual(out.extent, base.rect)
            // Odd input never breaks it.
            let odd = [HandFixtures.hand(.open, at: CGPoint(x: 1275, y: 715), size: 400), HandFixtures.hand(.fist, at: CGPoint(x: -50, y: -50), size: 8, id: 2)]
            for dt in [1.0 / 30, 5.0, 0.0, 1.0 / 30] { XCTAssertEqual(step(lens, odd, dt: dt).extent, base.rect, id) }
            lens.restart()
            XCTAssertEqual(step(lens, odd).extent, base.rect, "\(id) after a restart")
            // And with nobody in the picture at all.
            let lonely = LensInput(time: 0, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: nil, background: nil, composed: base.camera,
                                   matteGrid: nil, face: nil, services: base.services, hands: [open()])
            XCTAssertEqual(lens.render(lonely).extent, base.rect, id)
        }
    }

    // MARK: Pictures

    /// A frame with cartoon hands painted into the picture, so the saved pictures show where the effect sits on a hand.
    private func handPicture(_ hands: [HandState], time: Double, dt: Double = 1.0 / 30) -> LensInput {
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
                ctx.addLine(to: hand[HandJoint(rawValue: finger.middleJoint.rawValue + 1) ?? finger.tip])
                ctx.addLine(to: hand[finger.tip])
                ctx.strokePath()
            }
        }
        let picture = ctx.makeImage().map { CIImage(cgImage: $0).composited(over: base.composed) } ?? base.composed
        return LensInput(time: time, dt: dt, rect: base.rect, camera: picture, matte: base.matte, background: base.background, composed: picture,
                         matteGrid: base.matteGrid, face: nil, services: base.services, hands: hands)
    }
}
