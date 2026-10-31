import CoreImage
import XCTest

/// Helpers for the tests of the redrawn props and the new costumes.
private enum HeadwearCostumeKit {
    static func frame(_ base: LensInput, face: FaceState?, time: Double, dt: Double = 1.0 / 30) -> LensInput {
        LensInput(time: time, dt: dt, rect: base.rect, camera: base.camera, matte: base.matte, background: base.background,
                  composed: base.composed, matteGrid: base.matteGrid, face: face, services: base.services)
    }

    /// Plays `face` for `frames` frames from frame `start`, and returns the last picture.
    @discardableResult
    static func play(_ lens: Lens, _ base: LensInput, _ face: FaceState?, frames: Int, start: Int = 0) -> CIImage {
        var out = base.composed
        for i in 0..<frames { out = lens.render(frame(base, face: face, time: Double(start + i) / 30)) }
        return out
    }

    /// A point given in face units, in output pixels.
    static func point(_ face: FaceState, _ x: Double, _ y: Double) -> CGPoint {
        let c = cos(face.roll), s = sin(face.roll), io = face.interocular
        return CGPoint(x: face.eyeCenter.x + (x * c - y * s) * io, y: face.eyeCenter.y + (x * s + y * c) * io)
    }

    static func box(_ face: FaceState, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> CGRect {
        let corners = [point(face, x0, y0), point(face, x1, y0), point(face, x0, y1), point(face, x1, y1)]
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    static func brightness(_ p: RGB) -> Int { p.r + p.g + p.b }

    /// How many pixels in `rect` differ from `plain` by more than `threshold`.
    static func changed(_ bits: Bitmap, from plain: Bitmap, in rect: CGRect, threshold: Int = 40) -> Int {
        var n = 0
        for x in Int(max(0, rect.minX))..<Int(min(1280, rect.maxX)) {
            for y in Int(max(0, rect.minY))..<Int(min(720, rect.maxY)) {
                let a = bits.pixel(x, y), b = plain.pixel(x, y)
                if abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) > threshold { n += 1 }
            }
        }
        return n
    }
}

// MARK: - The four classic props, redrawn

final class HeadwearPropTests: XCTestCase {
    private let h = LensHarness()
    private typealias Kit = HeadwearCostumeKit
    private let still = SyntheticScene(center: CGPoint(x: 640, y: 380))
    private lazy var base = h.input(still)
    private lazy var plain = h.bitmap(base.composed)

    private func face(open: Double = 0, brows: Double = 0, smile: Double = 0, blink: Double = 0) -> FaceState {
        var s = still
        s.mouthOpen = open; s.browRaise = brows; s.smile = smile; s.blink = blink
        return s.face()
    }

    func testCatEarsFlickOnABlinkAndSitOnABand() throws {
        let lens = DressUpLens(kind: .catEars)
        let cat = try XCTUnwrap(lens.costume as? HeadwearCatEars)
        let out = h.bitmap(Kit.play(lens, base, face(), frames: 40))
        XCTAssertEqual(cat.flicks, 0)
        XCTAssertGreaterThan(Kit.changed(out, from: plain, in: Kit.box(face(), 0.45, 1.3, 0.9, 1.8)), 200, "an ear on the right")
        XCTAssertGreaterThan(Kit.changed(out, from: plain, in: Kit.box(face(), -0.9, 1.3, -0.45, 1.8)), 200, "and one on the left")
        // A pink nose on the nose.
        let nose = still.face().nose
        let pink = out.pixel(Int(nose.x), Int(nose.y + 2))
        XCTAssertGreaterThan(pink.r, pink.b + 30, "a pink nose, got \(pink)")

        Kit.play(lens, base, face(blink: 1), frames: 2, start: 40)
        XCTAssertEqual(cat.flicks, 1)
        XCTAssertGreaterThan(cat.earTurn.map(abs).max() ?? 0, 0.1, "the ears flick")
        Kit.play(lens, base, face(blink: 1), frames: 20, start: 42)
        XCTAssertEqual(cat.flicks, 1, "holding the eyes shut is one blink")
        Kit.play(lens, base, face(), frames: 10, start: 62)
        Kit.play(lens, base, face(blink: 1), frames: 2, start: 72)
        XCTAssertEqual(cat.flicks, 2)
    }

    func testShadesSlideDownOntoTheEyesAndSlipDownWhenTheBrowsGoUp() throws {
        let lens = DressUpLens(kind: .shades)
        let shades = try XCTUnwrap(lens.costume as? HeadwearShades)
        let eyes = Kit.box(face(), -0.9, -0.15, 0.9, 0.15)
        let first = h.bitmap(lens.render(Kit.frame(base, face: face(), time: 0)))
        XCTAssertEqual(first.change(from: plain, in: eyes), 0, "they start out of the picture")
        // On the way down they are somewhere above the eyes.
        let midway = h.bitmap(Kit.play(lens, base, face(), frames: 17, start: 1))
        XCTAssertLessThan(Kit.changed(midway, from: plain, in: eyes), 50)
        let landed = h.bitmap(Kit.play(lens, base, face(), frames: 30, start: 18))
        Output.save(Kit.play(lens, base, face(), frames: 1, start: 48), as: "headwear-shades-landed.png")
        let above = Kit.point(face(), -0.5, 0.1)
        XCTAssertLessThan(Kit.brightness(landed.pixel(Int(above.x), Int(above.y))), 100, "dark glass over the eye")

        let peeking = h.bitmap(Kit.play(lens, base, face(brows: 1), frames: 25, start: 48))
        Output.save(Kit.play(lens, base, face(brows: 1), frames: 1, start: 73), as: "headwear-shades-peek.png")
        XCTAssertGreaterThan(shades.peek, 0.25)
        XCTAssertGreaterThan(Kit.brightness(peeking.pixel(Int(above.x), Int(above.y))), 300, "the eye shows over the top of them")
        Kit.play(lens, base, face(), frames: 40, start: 73)
        XCTAssertLessThan(shades.peek, 0.03, "and they slide back up")
        // The slide in: never below its resting place, and smooth.
        var last = HeadwearShades.height(0, from: 4)
        for i in 1...60 {
            let y = HeadwearShades.height(Double(i) / 60 * 1.6, from: 4)
            XCTAssertGreaterThan(y, -0.06)
            XCTAssertLessThan(abs(y - last), 0.4, "no jumps")
            last = y
        }
    }

    func testTheCrownSparklesWhenYouSmile() throws {
        let lens = DressUpLens(kind: .crown)
        let crown = try XCTUnwrap(lens.costume as? HeadwearCrown)
        let zone = Kit.box(face(), -0.9, 1.1, 0.9, 2.3)
        let calm = Kit.play(lens, base, face(), frames: 45)
        // Read out now: lens pictures share drawing buffers with later frames.
        let a = h.average(calm, zone)
        XCTAssertLessThan(crown.dazzle, 0.05)
        var gold = 0
        let bits = h.bitmap(calm)
        for x in Int(zone.minX)..<Int(zone.maxX) { for y in Int(zone.minY)..<Int(zone.maxY) {
            let p = bits.pixel(x, y); if p.r > 200 && p.g > 140 && p.b < 130 { gold += 1 }
        } }
        XCTAssertGreaterThan(gold, 1500, "plenty of gold on the head")
        let grin = Kit.play(lens, base, face(smile: 1), frames: 40, start: 45)
        Output.save(grin, as: "headwear-crown-smile.png")
        XCTAssertGreaterThan(crown.dazzle, 0.9)
        let b = h.average(grin, zone)
        XCTAssertGreaterThan(b.r + b.g + b.b, a.r + a.g + a.b + 0.02, "the crown is brighter when you smile")
    }

    func testThePartyHornUnrollsWhenYouOpenYourMouthWithConfetti() throws {
        let lens = DressUpLens(kind: .partyHat)
        let hat = try XCTUnwrap(lens.costume as? HeadwearPartyHat)
        Kit.play(lens, base, face(), frames: 40)
        XCTAssertLessThan(hat.hornOut, 0.02)
        XCTAssertEqual(hat.confettiCount, 0)
        let blowing = Kit.play(lens, base, face(open: 0.9), frames: 20, start: 40)
        Output.save(blowing, as: "headwear-party-horn.png")
        XCTAssertGreaterThan(hat.hornOut, 0.8)
        XCTAssertGreaterThan(hat.confettiCount, 5, "a puff of confetti")
        let mouth = still.face().mouth
        XCTAssertGreaterThan(h.bitmap(blowing).change(from: plain, in: CGRect(x: mouth.x + 30, y: mouth.y - 60, width: 100, height: 60)), 150,
                             "the horn sticks out beside the mouth")
        // A wobbling jaw doesn't roll it up; shutting the mouth does.
        Kit.play(lens, base, face(open: 0.3), frames: 15, start: 60)
        XCTAssertGreaterThan(hat.hornOut, 0.7)
        Kit.play(lens, base, face(), frames: 40, start: 75)
        XCTAssertLessThan(hat.hornOut, 0.05)
        Kit.play(lens, base, face(), frames: 90, start: 115)
        XCTAssertEqual(hat.confettiCount, 0, "and the confetti has all fallen away")
    }
}

// MARK: - The new costumes, one reaction each

final class HeadwearNewCostumeTests: XCTestCase {
    private let h = LensHarness()
    private typealias Kit = HeadwearCostumeKit
    private let still = SyntheticScene(center: CGPoint(x: 640, y: 380))
    private lazy var base = h.input(still)
    private lazy var plain = h.bitmap(base.composed)

    private func face(open: Double = 0, brows: Double = 0, smile: Double = 0, blink: Double = 0) -> FaceState {
        var s = still
        s.mouthOpen = open; s.browRaise = brows; s.smile = smile; s.blink = blink
        return s.face()
    }

    private func costume<T>(_ kind: HeadwearKind, as type: T.Type) throws -> (DressUpLens, T) {
        let lens = DressUpLens(kind: kind)
        return (lens, try XCTUnwrap(lens.costume as? T))
    }

    func testHeadphonesPlayMusicWhileYouSmile() throws {
        let (lens, phones) = try costume(.headphones, as: HeadwearHeadphones.self)
        Kit.play(lens, base, face(), frames: 60)
        XCTAssertLessThan(phones.volume, 0.05)
        XCTAssertEqual(phones.noteCount, 0, "no music without a smile")
        let out = Kit.play(lens, base, face(smile: 1), frames: 60, start: 60)
        Output.save(out, as: "headwear-headphones-smile.png")
        XCTAssertGreaterThan(phones.volume, 0.9)
        XCTAssertGreaterThan(phones.noteCount, 1, "notes drift out")
        XCTAssertGreaterThan(phones.beat(0), 0.99)
        XCTAssertLessThan(phones.beat(0.25 / HeadwearHeadphones.tempo), 0.01, "a beat, then quiet")
    }

    func testTheCowboyTipsHisHatWhenTheBrowsGoUp() throws {
        let (lens, cowboy) = try costume(.cowboy, as: HeadwearCowboy.self)
        let column = Kit.box(face(), -0.1, 0.5, 0.1, 3.4)
        func top(_ bits: Bitmap) -> Int? {
            for y in stride(from: Int(column.maxY), to: Int(column.minY), by: -1) where bits.change(from: plain, in: CGRect(x: column.minX, y: Double(y), width: column.width, height: 1)) > 40 { return y }
            return nil
        }
        let sitting = h.bitmap(Kit.play(lens, base, face(), frames: 40))
        XCTAssertLessThan(cowboy.tipped, 0.02)
        Kit.play(lens, base, face(brows: 0.4), frames: 15, start: 40)
        XCTAssertLessThan(cowboy.tipped, 0.05, "a slight raise is not enough")
        let tipped = h.bitmap(Kit.play(lens, base, face(brows: 1), frames: 25, start: 55))
        Output.save(Kit.play(lens, base, face(brows: 1), frames: 1, start: 80), as: "headwear-cowboy-tip.png")
        XCTAssertGreaterThan(cowboy.tipped, 0.8)
        XCTAssertGreaterThan(try XCTUnwrap(top(tipped)), try XCTUnwrap(top(sitting)) + 10, "the hat rises off the head")
        Kit.play(lens, base, face(), frames: 40, start: 81)
        XCTAssertLessThan(cowboy.tipped, 0.05, "and settles back down")
    }

    func testTheVikingRoarsWhenTheMouthOpensAndTheBraidsSwing() throws {
        let (lens, viking) = try costume(.viking, as: HeadwearViking.self)
        Kit.play(lens, base, face(), frames: 40)
        XCTAssertEqual(viking.hop, 0, accuracy: 0.001)
        var highest = 0.0
        for i in 0..<12 {
            _ = lens.render(Kit.frame(base, face: face(open: 0.9), time: 2 + Double(i) / 30))
            highest = max(highest, viking.hop)
        }
        XCTAssertGreaterThan(highest, 0.04, "the helmet jumps")
        Kit.play(lens, base, face(open: 0.9), frames: 40, start: 80)
        XCTAssertLessThan(viking.hop, 0.01, "once, then settles while you hold it")
        var swing = 0.0
        for i in 0..<40 {
            var s = still; s.center.x = 640 + 100 * sin(Double(i) / 30 * 8)
            _ = lens.render(Kit.frame(base, face: s.face(), time: 5 + Double(i) / 30))
            swing = max(swing, viking.braidSwing.map(abs).max() ?? 0)
        }
        XCTAssertGreaterThan(swing, 0.08, "the braids swing as you move")
    }

    func testThePropellerWhirsUpWhenYouSmile() throws {
        let (lens, cap) = try costume(.propeller, as: HeadwearPropeller.self)
        Kit.play(lens, base, face(), frames: 60)
        XCTAssertLessThan(cap.speed, 2)
        Kit.play(lens, base, face(smile: 1), frames: 60, start: 60)
        Output.save(Kit.play(lens, base, face(smile: 1), frames: 1, start: 120), as: "headwear-propeller-smile.png")
        XCTAssertGreaterThan(cap.speed, 5)
        Kit.play(lens, base, face(), frames: 120, start: 121)
        XCTAssertLessThan(cap.speed, 2, "and winds down again")
    }

    func testTheAstronautsBreathFogsTheGlass() throws {
        let (lens, astronaut) = try costume(.astronaut, as: HeadwearAstronaut.self)
        Kit.play(lens, base, face(), frames: 40)
        XCTAssertLessThan(astronaut.fog, 0.02)
        let mouth = still.face().mouth
        let zone = CGRect(x: mouth.x - 15, y: mouth.y - 5, width: 30, height: 10)
        let before = h.average(Kit.play(lens, base, face(), frames: 1, start: 40), zone)
        let fogged = Kit.play(lens, base, face(open: 0.9), frames: 45, start: 41)
        Output.save(fogged, as: "headwear-astronaut-fog.png")
        XCTAssertGreaterThan(astronaut.fog, 0.6)
        let after = h.average(fogged, zone)
        XCTAssertGreaterThan(after.r + after.g + after.b, before.r + before.g + before.b + 0.15, "the glass beside the mouth goes misty")
        Kit.play(lens, base, face(), frames: 150, start: 86)
        XCTAssertLessThan(astronaut.fog, 0.05, "and clears")
        // Nothing covers the face itself apart from faint glass.
        let eye = still.face().rightEye
        let bits = h.bitmap(Kit.play(lens, base, face(), frames: 1, start: 240))
        XCTAssertLessThan(bits.change(from: plain, in: CGRect(x: eye.x - 3, y: eye.y + 12, width: 6, height: 4)), 90, "you can still see the face")
    }

    func testTheChefsHatPuffsUpWhenTheBrowsGoUp() throws {
        let (lens, chef) = try costume(.chef, as: HeadwearChef.self)
        Kit.play(lens, base, face(), frames: 40)
        XCTAssertLessThan(chef.puffed, 0.02)
        let puffed = Kit.play(lens, base, face(brows: 1), frames: 30, start: 40)
        Output.save(puffed, as: "headwear-chef-puff.png")
        XCTAssertGreaterThan(chef.puffed, 0.8)
        Kit.play(lens, base, face(), frames: 40, start: 70)
        XCTAssertLessThan(chef.puffed, 0.05)
    }

    func testTheFoxFlicksItsEarsOnABlink() throws {
        let (lens, fox) = try costume(.fox, as: HeadwearFox.self)
        Kit.play(lens, base, face(), frames: 40)
        XCTAssertLessThan(fox.earTurn.map(abs).max() ?? 1, 0.05, "still ears to begin with")
        Kit.play(lens, base, face(blink: 1), frames: 2, start: 40)
        XCTAssertGreaterThan(fox.earTurn.map(abs).max() ?? 0, 0.1, "a blink flicks them")
    }

    func testThePandaBlushesWhenYouSmileAndLeavesTheEyesClear() throws {
        let (lens, panda) = try costume(.panda, as: HeadwearPanda.self)
        let calm = h.bitmap(Kit.play(lens, base, face(), frames: 40))
        XCTAssertLessThan(panda.blush, 0.05)
        // Dark round the eye, but the eye itself is left showing.
        let eye = still.face().rightEye
        XCTAssertLessThan(Kit.brightness(calm.pixel(Int(eye.x + 28), Int(eye.y - 16))), 150, "a dark patch below and outside the eye")
        XCTAssertEqual(Kit.brightness(calm.pixel(Int(eye.x + 12), Int(eye.y))), Kit.brightness(plain.pixel(Int(eye.x + 12), Int(eye.y))), accuracy: 20,
                       "the white of the eye shows through")
        Kit.play(lens, base, face(smile: 1), frames: 40, start: 40)
        XCTAssertGreaterThan(panda.blush, 0.8)
    }

    func testTheTabbysWhiskersLiftWhenYouSmile() throws {
        let (lens, tabby) = try costume(.tabby, as: HeadwearTabby.self)
        Kit.play(lens, base, face(), frames: 40)
        XCTAssertLessThan(tabby.whiskerLift, 0.05)
        Output.save(Kit.play(lens, base, face(smile: 1), frames: 30, start: 40), as: "headwear-tabby-smile.png")
        XCTAssertGreaterThan(tabby.whiskerLift, 0.8)
    }

    func testTheUnicornsHornGlowsAndSparklesWhenYouSmile() throws {
        let (lens, unicorn) = try costume(.unicorn, as: HeadwearUnicorn.self)
        Kit.play(lens, base, face(), frames: 60)
        XCTAssertLessThan(unicorn.hornGlow, 0.05)
        XCTAssertEqual(unicorn.sparkleCount, 0)
        Output.save(Kit.play(lens, base, face(smile: 1), frames: 45, start: 60), as: "headwear-unicorn-smile.png")
        XCTAssertGreaterThan(unicorn.hornGlow, 0.8)
        XCTAssertGreaterThan(unicorn.sparkleCount, 5)
    }

    func testTheMermaidBlowsBubblesWhenYouSmile() throws {
        let (lens, mermaid) = try costume(.mermaid, as: HeadwearMermaid.self)
        Kit.play(lens, base, face(), frames: 60)
        XCTAssertEqual(mermaid.bubbleCount, 0)
        Output.save(Kit.play(lens, base, face(smile: 1), frames: 45, start: 60), as: "headwear-mermaid-smile.png")
        XCTAssertGreaterThan(mermaid.bubbleCount, 3)
        Kit.play(lens, base, face(), frames: 120, start: 105)
        XCTAssertEqual(mermaid.bubbleCount, 0, "they all float away")
    }

    func testTheRobotsLightsFollowYourVoice() throws {
        let (lens, robot) = try costume(.robot, as: HeadwearRobot.self)
        Kit.play(lens, base, face(), frames: 40)
        XCTAssertLessThan(robot.talking, 0.05)
        Output.save(Kit.play(lens, base, face(open: 0.8), frames: 20, start: 40), as: "headwear-robot-talk.png")
        XCTAssertGreaterThan(robot.talking, 0.9)
        Kit.play(lens, base, face(), frames: 40, start: 60)
        XCTAssertLessThan(robot.talking, 0.05)
    }

    func testTheReindeersNoseLightsUpWhenYouSmile() throws {
        let (lens, reindeer) = try costume(.reindeer, as: HeadwearReindeer.self)
        let nose = still.face().nose
        let zone = CGRect(x: nose.x - 50, y: nose.y - 40, width: 100, height: 90)
        let calm = h.average(Kit.play(lens, base, face(), frames: 40), zone)
        XCTAssertEqual(reindeer.glow, 0.2, accuracy: 0.03)
        let lit = Kit.play(lens, base, face(smile: 1), frames: 40, start: 40)
        let bright = h.average(lit, zone)
        Output.save(lit, as: "headwear-reindeer-smile.png")
        XCTAssertGreaterThan(reindeer.glow, 0.9)
        func redness(_ c: (r: Double, g: Double, b: Double)) -> Double { c.r - (c.g + c.b) / 2 }
        XCTAssertGreaterThan(redness(bright), redness(calm) + 0.03, "a red glow spreads round the nose")
    }

    func testTheWitchsSpiderDropsWhenYouOpenYourMouth() throws {
        let (lens, witch) = try costume(.witch, as: HeadwearWitch.self)
        Kit.play(lens, base, face(), frames: 50)
        XCTAssertEqual(witch.drop, HeadwearWitch.shortThread, accuracy: 0.1)
        Output.save(Kit.play(lens, base, face(open: 0.9), frames: 40, start: 50), as: "headwear-witch-spider.png")
        XCTAssertGreaterThan(witch.drop, 1.5, "down to about the mouth")
        Kit.play(lens, base, face(), frames: 90, start: 90)
        XCTAssertEqual(witch.drop, HeadwearWitch.shortThread, accuracy: 0.12, "and climbs back up")
    }
}

// MARK: - Real faces

/// Real faces are longer and wider than the cartoon test face; these check the costumes fit one, and survive every size and tilt.
final class HeadwearRealFaceTests: XCTestCase {
    private let h = LensHarness()
    private typealias Kit = HeadwearCostumeKit

    func testTheHeadIsMeasuredFromTheLandmarks() {
        let rig = HeadwearRig()
        let real = HeadwearRealHead().face()
        for _ in 0..<60 { _ = rig.update(real, dt: 1.0 / 30) }
        XCTAssertEqual(rig.head.tall, HeadwearRealHead.mouthDrop / 0.95, accuracy: 0.03, "a real face is longer")
        XCTAssertEqual(rig.head.wide, 1.2 / 1.13, accuracy: 0.03, "and a little wider")
        XCTAssertEqual(rig.head.brow, 0.4, accuracy: 0.03)
        // A yawn doesn't stretch it, and a raised brow isn't the resting brow.
        var yawn = HeadwearRealHead(); yawn.mouthOpen = 1; yawn.browRaise = 1
        for _ in 0..<90 { _ = rig.update(yawn.face(), dt: 1.0 / 30) }
        XCTAssertEqual(rig.head.tall, HeadwearRealHead.mouthDrop / 0.95, accuracy: 0.03)
        XCTAssertEqual(rig.head.brow, 0.4, accuracy: 0.06)
        // The cartoon face reads as the reference, so the costumes sit where they were drawn.
        let cartoon = HeadwearRig()
        for _ in 0..<30 { _ = cartoon.update(SyntheticScene().face(), dt: 1.0 / 30) }
        XCTAssertEqual(cartoon.head.tall, 1, accuracy: 0.01)
        XCTAssertEqual(cartoon.head.wide, 1, accuracy: 0.01)
    }

    /// Hats and headpieces sit on top of a real head: nothing comes down over the eyebrows, and something covers the top of the head.
    func testHatsSitOnARealHeadAndLeaveTheBrowsClear() {
        let person = HeadwearRealHead()
        let base = person.input(services: h.services)
        let plain = h.bitmap(base.composed)
        let face = person.face()
        let hats: [HeadwearKind] = [.crown, .partyHat, .cowboy, .viking, .propeller, .chef, .witch, .wizard, .santa, .robot,
                                    .mermaid, .catEars, .headphones, .bunny, .fox, .reindeer, .tabby]
        for kind in hats {
            let bits = h.bitmap(Kit.play(DressUpLens(kind: kind), base, face, frames: 50))
            let brows = Kit.box(face, -0.15, 0.05, 0.15, 0.5)
            XCTAssertLessThan(bits.change(from: plain, in: brows), 40, "\(kind): the brows and forehead are left clear")
            XCTAssertGreaterThan(Kit.changed(bits, from: plain, in: Kit.box(face, -1.0, 1.4, 1.0, 2.1)), 150, "\(kind): something up on the head")
        }
    }

    /// Every costume, at every size from half to double, tilted either way and off to the side, stays fixed to the head.
    func testEveryCostumeFollowsAnySizeTiltAndPlace() {
        let cases: [(scale: Double, roll: Double, centre: CGPoint)] = [(0.5, 0.6, CGPoint(x: 260, y: 300)), (0.5, -0.6, CGPoint(x: 1010, y: 420)),
                                                                       (1.0, -0.45, CGPoint(x: 420, y: 330)), (2.0, 0.35, CGPoint(x: 700, y: 220))]
        for (scale, roll, centre) in cases {
            var scene = SyntheticScene(center: centre); scene.scale = scale; scene.roll = roll
            let base = h.input(scene)
            let plain = h.bitmap(base.composed)
            let face = scene.face()
            for kind in HeadwearKind.allCases {
                let out = Kit.play(DressUpLens(kind: kind), base, face, frames: 45)
                XCTAssertEqual(out.extent, base.rect)
                let bits = h.bitmap(out)
                // Within a few eye-spacings of the head, never off in the far corner of the picture.
                let near = Kit.box(face, -4.2, -4.2, 4.2, 4.0).insetBy(dx: -10, dy: -10)
                var stray = 0
                for x in stride(from: 0, to: 1280, by: 8) { for y in stride(from: 0, to: 720, by: 8) where !near.contains(CGPoint(x: x, y: y)) {
                    let a = bits.pixel(x, y), b = plain.pixel(x, y)
                    if abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) > 40 { stray += 1 }
                } }
                XCTAssertEqual(stray, 0, "\(kind) at scale \(scale), roll \(roll): nothing far from the head")
                XCTAssertGreaterThan(Kit.changed(bits, from: plain, in: near), 20, "\(kind) at scale \(scale), roll \(roll): it is on")
                if scale == 2.0 { Output.save(out, as: "headwear-sweep-\(kind.rawValue)-near.png") }
            }
        }
    }

    func testTheCostumeFadesOutWhenTheFaceIsLostAndBackInAfterABlip() {
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let base = h.input(scene)
        let lens = DressUpLens(kind: .crown)
        Kit.play(lens, base, scene.face(), frames: 40)
        XCTAssertEqual(lens.presence, 1, accuracy: 1e-9)
        var last = 1.0
        for i in 0..<12 {
            _ = lens.render(Kit.frame(base, face: nil, time: 2 + Double(i) / 30))
            XCTAssertLessThanOrEqual(lens.presence, last)
            last = lens.presence
        }
        XCTAssertEqual(lens.presence, 0, "gone after a third of a second")
        _ = lens.render(Kit.frame(base, face: scene.face(), time: 3))
        XCTAssertGreaterThan(lens.presence, 0.1)
        XCTAssertLessThan(lens.presence, 0.5, "fading back in, not popping")
        Kit.play(lens, base, scene.face(), frames: 6, start: 91)
        XCTAssertEqual(lens.presence, 1, accuracy: 1e-9)
    }

    func testBakedArtIsKeptAndReusedAtAFewSizes() {
        var made = 0
        let paint: (HeadwearPen) -> Void = { pen in made += 1; pen.fill(HeadwearShape.ellipse(.zero, rx: 0.5, ry: 0.5), .white) }
        let window = CGRect(x: -0.5, y: -0.5, width: 1, height: 1)
        let a = HeadwearSprites.image("test-disc", window: window, density: HeadwearSprites.density(for: 80), paint)
        let b = HeadwearSprites.image("test-disc", window: window, density: HeadwearSprites.density(for: 84), paint)
        XCTAssertNotNil(a)
        XCTAssertTrue(a === b, "the same size step is drawn once")
        XCTAssertEqual(made, 1)
        let big = HeadwearSprites.image("test-disc", window: window, density: HeadwearSprites.density(for: 250), paint)
        XCTAssertEqual(made, 2)
        XCTAssertGreaterThan(big?.width ?? 0, a?.width ?? 0, "a nearer face gets a sharper copy")
        XCTAssertEqual(HeadwearSprites.density(for: 5000), HeadwearSprites.densities.last, "and there is a limit")
    }
}
