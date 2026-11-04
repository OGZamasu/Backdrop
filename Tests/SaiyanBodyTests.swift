import CoreImage
import simd
import XCTest

/// Draws the body half of the Dragon Ball lens the way the lens composes it (the aura behind, the person, the light over them, then the
/// whole-picture effects), for states a test makes up or a real `SaiyanTransformation` drives. Hands can be painted into the picture and the
/// cutout, so a power-up shows its fists.
final class SaiyanBodyBench {
    let h = LensHarness()
    let aura = SaiyanAura()
    let transformation = SaiyanTransformation()
    var gestures = HandGestureRecognizer()
    var scene = SyntheticScene()
    var background = true
    private(set) var time = 0.0

    /// This frame's picture and cutout, with `hands` painted in and the matte grid read from it, as the pipeline would.
    func input(hands: [HandState] = [], face: Bool = true, time: Double? = nil) -> LensInput {
        let plain = h.input(scene, time: time ?? self.time, background: background)
        guard !hands.isEmpty else { return face ? plain : Self.noFace(plain) }
        let painted = SaiyanBodyBench.paint(hands, over: plain)
        if let matte = painted.matte { h.grid.update(from: matte, rect: plain.rect, context: h.ciContext) }
        return face ? painted : Self.noFace(painted)
    }

    /// One frame of the body for `state`, over `frame`.
    func picture(_ state: SaiyanBodyState, _ frame: LensInput) -> CIImage {
        let effect = aura.screenEffect(state)
        let back = aura.backLayer(frame, state)
        var picture = SaiyanCompose.person(frame, over: back, effect: effect)
        if let light = aura.frontLight(frame, state) { picture = WorldKit.adding(light, to: picture) }
        return SaiyanCompose.screen(effect, over: picture, rect: frame.rect, time: state.time)
    }

    /// Holds a made-up state for `seconds` (embers fill the air, lightning crackles) and returns the last picture.
    @discardableResult
    func hold(_ state: SaiyanBodyState, seconds: Double, frame: LensInput? = nil) -> CIImage {
        let base = frame ?? input()
        var out = base.composed
        var s = state
        for _ in 0..<max(1, Int((seconds * 30).rounded())) {
            time += 1.0 / 30
            s.time = time
            out = picture(s, h.at(base, time: time))
        }
        return out
    }

    /// One frame driven by the real transformation: the gesture recogniser and the transformation read `hands`, then the body is drawn.
    @discardableResult
    func drive(_ hands: [HandState], face: Bool = true, draw: Bool = true, frame: LensInput? = nil) -> CIImage? {
        time += 1.0 / 30
        _ = gestures.update(hands, dt: 1.0 / 30)
        let faceState = face ? SyntheticScene().face() : nil
        transformation.update(hands: hands, gestures: gestures, face: faceState, dt: 1.0 / 30, time: time)
        guard draw else { return nil }
        let f = frame.map { h.at($0, time: time) } ?? input(hands: hands, face: face)
        return picture(transformation.state, f)
    }

    /// A picture read out now. Pictures are lazy and share drawing buffers that are reused a frame or two later, so anything kept for a
    /// contact sheet has to be captured first.
    func capture(_ image: CIImage) -> CIImage { SaiyanBodyBench.capture(image, h) }

    static func capture(_ image: CIImage, _ h: LensHarness) -> CIImage {
        guard let cg = h.ciContext.createCGImage(image, from: CGRect(x: 0, y: 0, width: 1280, height: 720), format: .RGBA8, colorSpace: TestSupport.srgb) else { return image }
        return CIImage(cgImage: cg)
    }

    /// What the lens shows with nothing of the body drawn: the person laid over the scenery.
    func plain(_ frame: LensInput) -> CIImage { SaiyanCompose.person(frame, over: frame.scenery, effect: .none) }

    /// A steady form, settled, at full presence.
    static func steady(_ form: SaiyanForm) -> SaiyanBodyState {
        SaiyanBodyState(form: form, previousForm: form, transition: 1, level: form.power, charge: 0, screaming: false, flash: 0, sinceChange: 99,
                        presence: 1, time: 0)
    }

    static func paint(_ hands: [HandState], over plain: LensInput) -> LensInput {
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        let skin = CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)!
        let mask = CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        mask.setFillColor(gray: 0, alpha: 1)
        mask.fill(CGRect(x: 0, y: 0, width: 1280, height: 720))
        for (ctx, colour) in [(skin, CGColor(red: 0.93, green: 0.74, blue: 0.62, alpha: 1)), (mask, CGColor(gray: 1, alpha: 1))] {
            ctx.setFillColor(colour); ctx.setStrokeColor(colour); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            for hand in hands {
                // A forearm down to the bottom of the picture, so the fist belongs to the person.
                ctx.setLineWidth(hand.size * 0.62)
                ctx.move(to: hand.wrist); ctx.addLine(to: CGPoint(x: hand.wrist.x + (hand.wrist.x - 640) * 0.25, y: -40)); ctx.strokePath()
                ctx.setLineWidth(hand.size * 0.26)
                let palm = CGMutablePath()
                palm.move(to: hand.wrist)
                for joint in [HandJoint.thumbCMC, .indexMCP, .middleMCP, .ringMCP, .littleMCP] { palm.addLine(to: hand[joint]) }
                palm.closeSubpath()
                ctx.addPath(palm); ctx.drawPath(using: .fillStroke)
                for finger in Finger.allCases {
                    ctx.setLineWidth(hand.size * (finger == .thumb ? 0.27 : 0.21))
                    ctx.beginPath(); ctx.move(to: hand[finger.knuckle]); ctx.addLine(to: hand[finger.middleJoint])
                    ctx.addLine(to: hand[HandJoint(rawValue: finger.middleJoint.rawValue + 1) ?? finger.tip]); ctx.addLine(to: hand[finger.tip])
                    ctx.strokePath()
                }
            }
        }
        guard let drawn = skin.makeImage(), let cut = mask.makeImage() else { return plain }
        let picture = CIImage(cgImage: drawn).composited(over: plain.composed).cropped(to: plain.rect)
        let camera = CIImage(cgImage: drawn).composited(over: plain.camera).cropped(to: plain.rect)
        let handMatte = CIImage(cgImage: cut)
        let matte = plain.matte.map { handMatte.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: $0]).cropped(to: plain.rect) } ?? handMatte
        return LensInput(time: plain.time, dt: plain.dt, rect: plain.rect, camera: camera, matte: matte, background: plain.background, composed: picture,
                         matteGrid: plain.matteGrid, face: plain.face, services: plain.services, hands: hands)
    }

    static func noFace(_ i: LensInput) -> LensInput {
        LensInput(time: i.time, dt: i.dt, rect: i.rect, camera: i.camera, matte: i.matte, background: i.background, composed: i.composed,
                  matteGrid: i.matteGrid, face: nil, services: i.services, hands: i.hands)
    }

    static func noMatte(_ i: LensInput) -> LensInput {
        LensInput(time: i.time, dt: i.dt, rect: i.rect, camera: i.camera, matte: nil, background: i.background, composed: i.composed,
                  matteGrid: nil, face: i.face, services: i.services, hands: i.hands)
    }

    static func with(_ i: LensInput, grid: MatteGrid) -> LensInput {
        LensInput(time: i.time, dt: i.dt, rect: i.rect, camera: i.camera, matte: i.matte, background: i.background, composed: i.composed,
                  matteGrid: grid, face: i.face, services: i.services, hands: i.hands)
    }
}

/// The body half of the Dragon Ball lens: powering up and down with both hands, and the aura, lightning, embers and level-up of every form.
final class SaiyanBodyTests: XCTestCase {
    /// Both fists up beside the chest, still: the power-up pose. Wrists low, fists at about shoulder height.
    private func fists(size: Double = 100, spread: Double = 190, height: Double = 210, angle: Double = 0.25, mirrored: Bool = false,
                       velocity: CGVector = .zero) -> [HandState] {
        [HandFixtures.hand(.fist, at: CGPoint(x: 640 - spread, y: height), size: size, angle: angle, mirrored: !mirrored, id: 1, velocity: velocity),
         HandFixtures.hand(.fist, at: CGPoint(x: 640 + spread, y: height), size: size, angle: -angle, mirrored: mirrored, id: 2, velocity: velocity)]
    }

    /// Both palms open, low and apart: the calm-down pose.
    private func lowOpenPalms(spread: Double = 260, height: Double = 90, size: Double = 100) -> [HandState] {
        [HandFixtures.hand(.open, at: CGPoint(x: 640 - spread, y: height), size: size, angle: 0.2, mirrored: true, id: 1),
         HandFixtures.hand(.open, at: CGPoint(x: 640 + spread, y: height), size: size, angle: -0.2, id: 2)]
    }

    private func run(_ t: SaiyanTransformation, _ g: inout HandGestureRecognizer, _ hands: [HandState], seconds: Double, face: FaceState? = SyntheticScene().face(),
                     clock: inout Double, until: ((SaiyanTransformation) -> Bool)? = nil) -> Double? {
        let frames = Int((seconds * 30).rounded())
        for i in 0..<frames {
            clock += 1.0 / 30
            _ = g.update(hands, dt: 1.0 / 30)
            t.update(hands: hands, gestures: g, face: face, dt: 1.0 / 30, time: clock)
            if let until, until(t) { return Double(i + 1) / 30 }
        }
        return nil
    }

    // MARK: Powering up

    func testBothFistsHeldStillPowerUpToSuperSaiyanThenSuperSaiyan2() {
        let t = SaiyanTransformation()
        var g = HandGestureRecognizer(), clock = 0.0
        XCTAssertNil(t.status, "nothing to say in base before anything happens (the lens shows the idle line)")
        let first = run(t, &g, fists(), seconds: 2, clock: &clock) { $0.form == .superSaiyan }
        XCTAssertNotNil(first)
        // The fists must be still for a fifth of a second (the recogniser trusts them after 0.15 s meanwhile), then the charge takes 0.8 s.
        XCTAssertEqual(first ?? 0, SaiyanTransformation.stillFor + SaiyanTransformation.firstStep, accuracy: 0.1, "Super Saiyan after about 0.8 s of held fists")
        XCTAssertEqual(t.state.previousForm, .base)
        XCTAssertEqual(t.state.flash, 1, accuracy: 0.06, "a change starts with the flash")
        XCTAssertEqual(t.state.transition, 0, accuracy: 0.06)
        XCTAssertEqual(t.status?.title, "Super Saiyan!")
        XCTAssertTrue(t.isClaiming)

        // Still holding: the next charge starts at once and takes about 1.4 s.
        var midway: LensStatus?
        let second = run(t, &g, fists(), seconds: 3, clock: &clock) {
            if $0.state.charge > 0.75 { midway = $0.status }
            return $0.form == .superSaiyan2
        }
        XCTAssertEqual(second ?? 0, SaiyanTransformation.laterStep, accuracy: 0.1, "Super Saiyan 2 about 1.4 s later")
        XCTAssertEqual(midway?.title, "Powering up... Super Saiyan 2")
        XCTAssertGreaterThan(t.state.level, 0.24, "the strength eases up toward the new form's")
        _ = run(t, &g, fists(), seconds: 0.2, clock: &clock)
        XCTAssertLessThan(t.state.level, SaiyanForm.superSaiyan2.power, "and does not jump")
        _ = run(t, &g, [], seconds: 1.5, clock: &clock)
        XCTAssertEqual(t.state.level, SaiyanForm.superSaiyan2.power, accuracy: 0.01, "settled by now")
        XCTAssertEqual(t.state.transition, 1)
        XCTAssertEqual(t.state.flash, 0)
        XCTAssertEqual(t.state.charge, 0)
        XCTAssertEqual(t.form, .superSaiyan2, "letting go keeps the form")
        XCTAssertFalse(t.isClaiming)
        XCTAssertNil(t.status)
    }

    func testFistsPowerUpAtAnySizeTurnedOrMirrored() {
        for (size, angle, mirrored) in [(60.0, 0.0, false), (150.0, 0.5, false), (100.0, -0.4, true), (80.0, 0.9, true)] {
            let t = SaiyanTransformation()
            var g = HandGestureRecognizer(), clock = 0.0
            let hands = fists(size: size, spread: 120 + size, angle: angle, mirrored: mirrored)
            let first = run(t, &g, hands, seconds: 1.5, clock: &clock) { $0.form == .superSaiyan }
            XCTAssertNotNil(first, "size \(size), turned \(angle), mirrored \(mirrored)")
        }
    }

    func testScreamingChargesFaster() {
        let t = SaiyanTransformation()
        var g = HandGestureRecognizer(), clock = 0.0
        var shout = SyntheticScene()
        shout.mouthOpen = 0.8
        _ = run(t, &g, fists(), seconds: 2.5, face: shout.face(), clock: &clock) { $0.form == .superSaiyan }
        XCTAssertEqual(t.form, .superSaiyan)
        var screamed = false
        let second = run(t, &g, fists(), seconds: 2, face: shout.face(), clock: &clock) {
            screamed = screamed || $0.state.screaming
            return $0.form == .superSaiyan2
        }
        XCTAssertTrue(screamed)
        XCTAssertEqual(second ?? 9, SaiyanTransformation.laterStep / SaiyanTransformation.screamBoost, accuracy: 0.1, "about 1.6 times faster")
        // A mouth a little open is talking, not screaming.
        let calm = SaiyanTransformation()
        var g2 = HandGestureRecognizer(), clock2 = 0.0
        var talk = SyntheticScene()
        talk.mouthOpen = 0.35
        let plain = run(calm, &g2, fists(), seconds: 2, face: talk.face(), clock: &clock2) { $0.form == .superSaiyan }
        XCTAssertEqual(plain ?? 0, SaiyanTransformation.stillFor + SaiyanTransformation.firstStep, accuracy: 0.1)
        XCTAssertFalse(calm.state.screaming)
    }

    func testNearMissesNeverCharge() {
        let face = SyntheticScene().face()
        let wrist = CGPoint(x: 450, y: 210)
        // A wave: an open palm swinging side to side.
        let wave: (Int) -> [HandState] = { i in
            let x = 450 + 90 * sin(Double(i) / 30 * 2 * .pi * 2.5)
            return [HandFixtures.hand(.open, at: CGPoint(x: x, y: 250), size: 100, id: 1)]
        }
        // Fists moving: both hands swinging (gesturing, or a hand crossing the picture).
        let moving: (Int) -> [HandState] = { i in
            let dx = 160 * sin(Double(i) / 30 * 2 * .pi * 0.8)
            let v = CGVector(dx: 160 * 2 * .pi * 0.8 * cos(Double(i) / 30 * 2 * .pi * 0.8), dy: 0)
            return self.fists().map { HandFixtures.moved($0, by: CGVector(dx: dx, dy: 0), velocity: v) }
        }
        let crossing: (Int) -> [HandState] = { i in
            let x = 200 + Double(i) * 14
            return [HandFixtures.hand(.fist, at: CGPoint(x: x, y: 200), size: 100, id: 1), HandFixtures.hand(.fist, at: CGPoint(x: x + 300, y: 220), size: 100, id: 2)]
        }
        let cases: [(String, (Int) -> [HandState], FaceState?)] = [
            ("one fist", { _ in [HandFixtures.hand(.fist, at: wrist, size: 100, id: 1)] }, face),
            ("one fist and an open hand", { _ in [HandFixtures.hand(.fist, at: wrist, size: 100, id: 1), HandFixtures.hand(.open, at: CGPoint(x: 830, y: 210), size: 100, id: 2)] }, face),
            ("two peace signs", { _ in [HandFixtures.hand(.peace, at: wrist, size: 100, id: 1), HandFixtures.hand(.peace, at: CGPoint(x: 830, y: 210), size: 100, mirrored: true, id: 2)] }, face),
            ("two pointing hands", { _ in [HandFixtures.hand(.point, at: wrist, size: 100, id: 1), HandFixtures.hand(.point, at: CGPoint(x: 830, y: 210), size: 100, mirrored: true, id: 2)] }, face),
            ("two finger guns", { _ in [HandFixtures.hand(.gun, at: wrist, size: 100, angle: -1.2, id: 1), HandFixtures.hand(.gun, at: CGPoint(x: 830, y: 210), size: 100, angle: 1.2, mirrored: true, id: 2)] }, face),
            ("a wave", wave, face),
            ("fists swinging", moving, face),
            ("fists crossing the picture", crossing, face),
            ("two thumbs up", { _ in [HandFixtures.thumbsUp(at: wrist, id: 1), HandFixtures.thumbsUp(at: CGPoint(x: 830, y: 210), mirrored: true, id: 2)] }, face),
            ("both fists but no face", { _ in self.fists() }, nil),
        ]
        for (name, hands, f) in cases {
            let t = SaiyanTransformation()
            var g = HandGestureRecognizer()
            var clock = 0.0
            var peak = 0.0
            for i in 0..<90 {
                clock += 1.0 / 30
                let now = hands(i)
                _ = g.update(now, dt: 1.0 / 30)
                t.update(hands: now, gestures: g, face: f, dt: 1.0 / 30, time: clock)
                peak = max(peak, t.state.charge)
            }
            XCTAssertEqual(t.form, .base, name)
            XCTAssertLessThan(peak, 0.01, "\(name) must not start a charge")
        }
    }

    func testAShortDropoutKeepsTheChargeAndLettingGoDrainsIt() {
        let t = SaiyanTransformation()
        var g = HandGestureRecognizer(), clock = 0.0
        _ = run(t, &g, fists(), seconds: 0.55, clock: &clock)
        let before = t.state.charge
        XCTAssertGreaterThan(before, 0.3)
        // The tracker loses both hands for a fifth of a second, then finds them again (the recogniser has to re-read the fists).
        _ = run(t, &g, [], seconds: 0.2, clock: &clock)
        XCTAssertEqual(t.state.charge, before, accuracy: 0.001, "a dropout of 0.2 s holds the charge")
        XCTAssertTrue(t.isClaiming)
        _ = run(t, &g, fists(), seconds: 0.2, clock: &clock)
        XCTAssertGreaterThanOrEqual(t.state.charge, before - 0.001, "and the hands coming back do not drain it")
        // The same with the tracker carrying the hands through the gap (as `HandSmoother` does).
        let held = fists().map { h -> HandState in var c = h; c.unseenFor = 0.1; return c }
        let carried = t.state.charge
        _ = run(t, &g, held, seconds: 0.2, clock: &clock)
        XCTAssertEqual(t.state.charge, carried, accuracy: 0.001, "a hand the tracker is guessing at neither fills nor drains it")

        // Letting go for good drains it over about half a second, after the grace.
        let level = t.state.charge
        _ = run(t, &g, [], seconds: 0.2, clock: &clock)
        XCTAssertEqual(t.state.charge, level, accuracy: 0.001)
        _ = run(t, &g, [], seconds: SaiyanTransformation.grace - 0.2 + SaiyanTransformation.drainSeconds * level + 0.1, clock: &clock)
        XCTAssertEqual(t.state.charge, 0)
        XCTAssertEqual(t.form, .base)
        _ = run(t, &g, [], seconds: 0.1, clock: &clock)
        XCTAssertFalse(t.isClaiming)
    }

    func testTheTopFormHoldsAtFullPower() {
        let t = SaiyanTransformation()
        var g = HandGestureRecognizer(), clock = 0.0
        _ = run(t, &g, fists(), seconds: 0.95 + 1.4 * 9 + 1, clock: &clock)
        XCTAssertEqual(t.form, .ultraInstinct)
        XCTAssertEqual(t.changes, 9, "one step at a time, no skipping")
        _ = run(t, &g, fists(), seconds: 3, clock: &clock)
        XCTAssertEqual(t.form, .ultraInstinct, "it does not wrap round")
        XCTAssertEqual(t.state.charge, 0)
        XCTAssertEqual(t.status?.title, "Full power")
        XCTAssertTrue(t.isClaiming, "held fists still block the moves")
    }

    func testCalmingDownWorksOnlyWithOpenPalmsLowAndApart() {
        func poweredUp() -> (SaiyanTransformation, HandGestureRecognizer, Double) {
            let t = SaiyanTransformation()
            var g = HandGestureRecognizer(), clock = 0.0
            _ = run(t, &g, fists(), seconds: 1.2, clock: &clock)
            _ = run(t, &g, [], seconds: 1, clock: &clock)
            return (t, g, clock)
        }
        var (t, g, clock) = poweredUp()
        XCTAssertEqual(t.form, .superSaiyan)
        var said: LensStatus?
        let took = run(t, &g, lowOpenPalms(), seconds: 2, clock: &clock) {
            if $0.calming > 0.4 { said = said ?? $0.status }
            return $0.form == .base
        }
        XCTAssertNotNil(took)
        XCTAssertEqual(took ?? 0, 0.12 + SaiyanTransformation.calmSeconds, accuracy: 0.12)
        XCTAssertEqual(said?.title, "Calming down")
        XCTAssertEqual(t.state.previousForm, .superSaiyan)
        XCTAssertEqual(t.state.flash, SaiyanTransformation.calmFlash, accuracy: 0.05, "a little flash, not a big one")
        XCTAssertEqual(t.status?.title, "Calming down")

        // Near misses: Final Flash's palms together at chest height, palms apart but up by the face, one palm, palms waving.
        let face = SyntheticScene().face()
        let together = [HandFixtures.hand(.open, at: CGPoint(x: 590, y: 170), size: 100, id: 1), HandFixtures.hand(.open, at: CGPoint(x: 690, y: 170), size: 100, mirrored: true, id: 2)]
        let high = [HandFixtures.hand(.open, at: CGPoint(x: 380, y: 380), size: 100, id: 1), HandFixtures.hand(.open, at: CGPoint(x: 900, y: 380), size: 100, mirrored: true, id: 2)]
        let one = [lowOpenPalms()[0]]
        XCTAssertFalse(t.inCalmZone(together[0], together[1], face))
        XCTAssertFalse(t.inCalmZone(high[0], high[1], face))
        XCTAssertTrue(t.inCalmZone(lowOpenPalms()[0], lowOpenPalms()[1], face))
        for (name, hands) in [("palms together at the chest", together), ("palms up by the face", high), ("one palm", one)] {
            (t, g, clock) = poweredUp()
            _ = run(t, &g, hands, seconds: 2.5, clock: &clock)
            XCTAssertEqual(t.form, .superSaiyan, "\(name) must not calm you down")
        }
        (t, g, clock) = poweredUp()
        for i in 0..<75 {
            let swing = 120 * sin(Double(i) / 30 * 2 * .pi * 2)
            let hands = lowOpenPalms().map { HandFixtures.moved($0, by: CGVector(dx: swing, dy: 0)) }
            clock += 1.0 / 30
            _ = g.update(hands, dt: 1.0 / 30)
            t.update(hands: hands, gestures: g, face: face, dt: 1.0 / 30, time: clock)
        }
        XCTAssertEqual(t.form, .superSaiyan, "waving both hands low does not calm you down")
    }

    func testLosingTheFaceFadesTheEffectAndForgetsTheFormAfterFiveSeconds() {
        let t = SaiyanTransformation()
        var g = HandGestureRecognizer(), clock = 0.0
        _ = run(t, &g, fists(), seconds: 1.2, clock: &clock)
        _ = run(t, &g, [], seconds: 0.5, clock: &clock)
        XCTAssertEqual(t.form, .superSaiyan)
        XCTAssertEqual(t.state.presence, 1)
        _ = run(t, &g, [], seconds: 0.2, face: nil, clock: &clock)
        XCTAssertEqual(t.state.presence, 0.5, accuracy: 0.1, "it fades rather than vanishing")
        _ = run(t, &g, [], seconds: 0.3, face: nil, clock: &clock)
        XCTAssertEqual(t.state.presence, 0)
        XCTAssertEqual(t.form, .superSaiyan, "a face lost for a moment keeps the form")
        _ = run(t, &g, [], seconds: 0.3, clock: &clock)
        XCTAssertEqual(t.state.presence, 1, "and comes back with it")
        _ = run(t, &g, [], seconds: 6, face: nil, clock: &clock)
        XCTAssertEqual(t.form, .base, "gone six seconds: back to base")
        XCTAssertEqual(t.state.flash, 0, "silently")
        XCTAssertEqual(t.state.level, 0)
        XCTAssertGreaterThan(t.state.sinceChange, 5, "no shockwave either")
    }

    func testClaimingCoversHeldFistsTheChargeAndAMomentAfterAChange() {
        let t = SaiyanTransformation()
        var g = HandGestureRecognizer(), clock = 0.0
        XCTAssertFalse(t.isClaiming)
        _ = run(t, &g, fists(), seconds: 0.1, clock: &clock)
        XCTAssertTrue(t.isClaiming, "held fists claim at once, before any charge")
        XCTAssertEqual(t.state.charge, 0)
        _ = run(t, &g, fists(), seconds: 0.4, clock: &clock)
        XCTAssertTrue(t.isClaiming)
        _ = run(t, &g, fists(), seconds: 1.6, clock: &clock) { $0.form == .superSaiyan }
        _ = run(t, &g, [], seconds: 1.5, clock: &clock)
        XCTAssertFalse(t.isClaiming, "nothing held, nothing charging, change long past")
        // Calm down, then just after the change the same hands may not start a move.
        _ = run(t, &g, lowOpenPalms(), seconds: 2, clock: &clock) { $0.form == .base }
        XCTAssertTrue(t.isClaiming)
        _ = run(t, &g, [], seconds: 0.4, clock: &clock)
        XCTAssertFalse(t.isClaiming)
        // A single fist claims nothing.
        _ = run(t, &g, [HandFixtures.hand(.fist, at: CGPoint(x: 450, y: 210), size: 100, id: 1)], seconds: 0.6, clock: &clock)
        XCTAssertFalse(t.isClaiming)
    }

    // MARK: The aura

    private func brightness(_ p: RGB) -> Int { p.r + p.g + p.b }
    private func diff(_ a: RGB, _ b: RGB) -> Int { abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) }

    func testBaseDrawsNothingAndCostsNothing() {
        let bench = SaiyanBodyBench()
        let frame = bench.input()
        let state = SaiyanBodyBench.steady(.base)
        let back = bench.aura.backLayer(frame, state)
        XCTAssertTrue(back === frame.scenery || back.extent == frame.scenery.extent)
        XCTAssertEqual(bench.h.bitmap(back).change(from: bench.h.bitmap(frame.scenery), in: frame.rect), 0, "base: the room as it is")
        XCTAssertNil(bench.aura.frontLight(frame, state))
        XCTAssertTrue(bench.aura.screenEffect(state).isNone)
        XCTAssertEqual(bench.aura.emberCount, 0)
        // After calming down, once it has all settled and the last ember is gone, base is free again.
        var calm = SaiyanBodyBench.steady(.superSaiyan)
        bench.hold(calm, seconds: 1)
        calm.form = .base; calm.transition = 0; calm.sinceChange = 0; calm.flash = 0.35
        for i in 0..<120 {
            calm.transition = min(1, calm.transition + 1.0 / 21)
            calm.flash = max(0, calm.flash - 1.0 / 18 * 0.35)
            calm.sinceChange += 1.0 / 30
            _ = i
            bench.hold(calm, seconds: 1.0 / 30, frame: frame)
        }
        XCTAssertEqual(bench.aura.emberCount, 0)
        XCTAssertNil(bench.aura.frontLight(frame, calm))
        XCTAssertEqual(bench.h.bitmap(bench.aura.backLayer(frame, calm)).change(from: bench.h.bitmap(frame.scenery), in: frame.rect), 0)
    }

    func testEveryFormGlowsAroundTheOutlineInItsOwnColourAndLeavesTheRoomAlone() {
        let bench = SaiyanBodyBench()
        let frame = bench.input()
        let plain = bench.h.bitmap(bench.plain(frame))
        for form in SaiyanForm.allCases where !form.isBase {
            let out = bench.h.bitmap(bench.hold(SaiyanBodyBench.steady(form), seconds: 1, frame: frame))
            // Just outside the side of the head (the head spans 540...740 at y 420): the glow.
            let near = out.pixel(770, 430), was = plain.pixel(770, 430)
            XCTAssertGreaterThan(diff(near, was), 90, "\(form): a glow just outside you, got \(near) over \(was)")
            // Far away, in the corner: the room is untouched.
            XCTAssertLessThan(out.change(from: plain, in: CGRect(x: 0, y: 650, width: 120, height: 70)), 12, "\(form): the far corner is left alone")
            // The face is not covered by the aura (only the light over the edges touches the person).
            XCTAssertLessThan(diff(out.pixel(640, 430), plain.pixel(640, 430)), 40, "\(form): the middle of the face stays clear")
            // The glow's colour leans the way the palette does.
            var added = SIMD3<Double>(0, 0, 0)
            // Blue Kaioken is a blue body inside a red rim: look further out, at the rim.
            let kaioken = form.auraStyle == .kaioken
            let points = kaioken ? [(850, 380), (860, 450), (430, 380), (420, 450)] : [(790, 400), (800, 470), (490, 400), (480, 470), (760, 330), (520, 330)]
            for (x, y) in points {
                let a = out.pixel(x, y), b = plain.pixel(x, y)
                added += SIMD3(Double(a.r - b.r), Double(a.g - b.g), Double(a.b - b.b))
            }
            let mid = kaioken ? form.palette.auraRim : form.palette.auraMid
            let chroma = added - SIMD3(repeating: (added.x + added.y + added.z) / 3)
            func leaning(_ c: SIMD3<Double>) -> Double {
                let want = c - SIMD3(repeating: (c.x + c.y + c.z) / 3)
                return simd_dot(chroma, want) / max(1e-6, simd_length(chroma) * simd_length(want))
            }
            if simd_length(mid - SIMD3(repeating: (mid.x + mid.y + mid.z) / 3)) > 0.15 {
                let cosine = leaning(mid)
                XCTAssertGreaterThan(cosine, 0.6, "\(form): the glow should be the palette's colour, added \(added)")
            } else {
                XCTAssertLessThan(simd_length(chroma) / max(1, (added.x + added.y + added.z) / 3), 0.6, "\(form): a pale glow, added \(added)")
            }
        }
    }

    func testEmbersRiseFromTheHeadAndShouldersAndLightningFollowsTheForm() {
        let bench = SaiyanBodyBench()
        let frame = bench.input()
        bench.hold(SaiyanBodyBench.steady(.superSaiyan), seconds: 1.5, frame: frame)
        XCTAssertGreaterThan(bench.aura.emberCount, 40, "embers fill the air")
        XCTAssertGreaterThan(bench.aura.emberDrift.y, 40, "and rise")
        let outline = bench.aura.lastOutline
        XCTAssertGreaterThan(outline.rim.count, 30)
        XCTAssertFalse(outline.crown.isEmpty)
        XCTAssertGreaterThan(outline.crown.map(\.y).min() ?? 0, 80, "embers start from the head and shoulders, not the bottom edge")

        // Super Saiyan 2 crackles nearly all the time; God never does.
        var crackling = 0
        for _ in 0..<60 {
            bench.hold(SaiyanBodyBench.steady(.superSaiyan2), seconds: 1.0 / 30, frame: frame)
            if bench.aura.boltCount > 0 { crackling += 1 }
        }
        XCTAssertGreaterThan(crackling, 45, "Super Saiyan 2's lightning is constant")
        bench.hold(SaiyanBodyBench.steady(.superSaiyanGod), seconds: 0.5, frame: frame)
        var god = 0
        for _ in 0..<60 {
            bench.hold(SaiyanBodyBench.steady(.superSaiyanGod), seconds: 1.0 / 30, frame: frame)
            god += bench.aura.boltCount
        }
        XCTAssertEqual(god, 0, "God's aura is calm")

        // Super Saiyan 3's heavy lightning never crosses the face: the middle of it stays as it was over many frames.
        let plain = bench.h.bitmap(bench.plain(frame))
        var worst = 0
        for _ in 0..<45 {
            let out = bench.h.bitmap(bench.hold(SaiyanBodyBench.steady(.superSaiyan3), seconds: 1.0 / 30, frame: frame))
            // The middle of the face: its edge is meant to catch the wrap light.
            let change = out.change(from: plain, in: CGRect(x: 600, y: 350, width: 80, height: 130))
            worst = max(worst, change)
        }
        XCTAssertLessThan(worst, 60, "no lightning across the eyes and mouth")
    }

    func testALevelUpFlashesShakesAndSettles() {
        let bench = SaiyanBodyBench()
        let t = bench.transformation
        let hands = fists()
        let frame = bench.input(hands: hands)
        var flashes: [Double] = [], shakes: [Double] = []
        var debris = 0
        for _ in 0..<60 {
            bench.drive(hands, frame: frame)
            debris = max(debris, bench.aura.rockCount)
            let e = bench.aura.screenEffect(t.state)
            flashes.append(e.flash)
            shakes.append(e.shake)
            if t.form == .superSaiyan { break }
        }
        XCTAssertEqual(t.form, .superSaiyan)
        XCTAssertGreaterThan(flashes.last ?? 0, 0.4, "a flash on the change")
        XCTAssertGreaterThan(shakes.last ?? 0, 0.2, "and a small shake")
        XCTAssertGreaterThan(shakes.dropLast().max() ?? 0, 0.05, "trembling while it charged")
        XCTAssertLessThan(shakes.dropLast().max() ?? 1, 0.2, "but only a little")
        XCTAssertGreaterThan(debris, 0, "debris lifts off the floor while it charges")
        // The shockwave runs out across the room, far from the person, then the room settles back to the steady aura.
        let corner = CGRect(x: 60, y: 480, width: 220, height: 200)
        let steadyRoom = bench.h.bitmap(bench.plain(frame))
        var swept = 0
        for _ in 0..<12 { swept = max(swept, bench.h.bitmap(bench.drive([], frame: frame)!).change(from: steadyRoom, in: corner)) }
        XCTAssertGreaterThan(swept, 40, "the rings and rays reach the far corner")
        // Let go: the flash and shake settle to nothing.
        for _ in 0..<30 { bench.drive([], frame: frame) }
        XCTAssertTrue(bench.aura.screenEffect(t.state).isNone, "settled a second later")
        XCTAssertLessThan(bench.h.bitmap(bench.drive([], frame: frame)!).change(from: steadyRoom, in: corner), 16, "and the far corner is quiet again")
    }

    func testNoCutoutMeansNoGlowAndPresenceFadesIt() {
        let bench = SaiyanBodyBench()
        let frame = SaiyanBodyBench.noMatte(bench.input())
        let state = SaiyanBodyBench.steady(.superSaiyan3)
        let back = bench.aura.backLayer(frame, state)
        XCTAssertEqual(bench.h.bitmap(back).change(from: bench.h.bitmap(frame.scenery), in: frame.rect), 0, "nothing to glow round: nothing drawn")
        XCTAssertNil(bench.aura.frontLight(frame, state))

        let full = bench.input()
        let plain = bench.h.bitmap(bench.plain(full))
        var faded = SaiyanBodyBench.steady(.superSaiyan)
        faded.presence = 0
        bench.hold(faded, seconds: 1, frame: full)
        let out = bench.h.bitmap(bench.hold(faded, seconds: 1.0 / 30, frame: full))
        XCTAssertLessThan(out.change(from: plain, in: CGRect(x: 700, y: 300, width: 200, height: 250)), 8, "presence 0: nothing showing")
        faded.presence = 0.5
        let half = bench.h.bitmap(bench.hold(faded, seconds: 0.5, frame: full))
        let fullOut = bench.h.bitmap(bench.hold(SaiyanBodyBench.steady(.superSaiyan), seconds: 0.5, frame: full))
        XCTAssertLessThan(diff(half.pixel(770, 430), plain.pixel(770, 430)), diff(fullOut.pixel(770, 430), plain.pixel(770, 430)), "half presence, less glow")
    }

    func testTrackerDropoutsNeverPopTheAura() {
        let bench = SaiyanBodyBench()
        let frame = bench.input()
        let plain = bench.h.bitmap(bench.plain(frame))
        let state = SaiyanBodyBench.steady(.superSaiyan2)
        bench.hold(state, seconds: 1, frame: frame)
        let before = bench.h.bitmap(bench.hold(state, seconds: 1.0 / 30, frame: frame))
        let glow = { (b: Bitmap) in self.diff(b.pixel(770, 430), plain.pixel(770, 430)) }
        // The matte grid missing for a few frames (the CPU copy of the cutout is late), and the face lost for a moment: the glow carries on.
        let noGrid = LensInput(time: frame.time, dt: frame.dt, rect: frame.rect, camera: frame.camera, matte: frame.matte, background: frame.background,
                               composed: frame.composed, matteGrid: nil, face: nil, services: frame.services, hands: [])
        var weakest = Int.max
        for _ in 0..<4 { weakest = min(weakest, glow(bench.h.bitmap(bench.hold(state, seconds: 1.0 / 30, frame: noGrid)))) }
        XCTAssertGreaterThan(weakest, glow(before) / 2, "a late matte grid does not drop the glow")
        let after = bench.h.bitmap(bench.hold(state, seconds: 1.0 / 30, frame: frame))
        XCTAssertGreaterThan(glow(after), glow(before) / 2)
        XCTAssertGreaterThan(bench.aura.lastOutline.rim.count, 30, "and the outline is read again as soon as it is back")
        // A cutout that suddenly empties (nobody there): nothing glows over the room.
        let empty = CIImage(color: .black).cropped(to: frame.rect)
        let nobody = LensInput(time: frame.time, dt: frame.dt, rect: frame.rect, camera: frame.camera, matte: empty, background: frame.background,
                               composed: frame.composed, matteGrid: nil, face: nil, services: frame.services, hands: [])
        let out = bench.h.bitmap(bench.hold(state, seconds: 1.5, frame: nobody))
        XCTAssertLessThan(out.change(from: bench.h.bitmap(nobody.scenery), in: CGRect(x: 0, y: 0, width: 1280, height: 720)), 40,
                          "with nobody in the cutout there is nothing to glow round")
    }

    func testTheBodyStaysWithinBudget() {
        let bench = SaiyanBodyBench()
        let frame = bench.input()
        let buffer = bench.h.compositor.makeOutputBuffer()!
        var report: [String] = []
        // What rendering the person over the room costs with no body at all, to compare the rendering times against.
        var baseline: [Double] = []
        for i in 0..<30 {
            let started = CFAbsoluteTimeGetCurrent()
            bench.h.compositor.render(bench.plain(bench.h.at(frame, time: Double(i) / 30)), into: buffer)
            baseline.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
        }
        report.append(String(format: "no body %.2f ms rendering", baseline.reduce(0, +) / Double(baseline.count)))
        for form in [SaiyanForm.superSaiyan, .superSaiyan3, .ultraInstinct, .blueKaioken] {
            bench.hold(SaiyanBodyBench.steady(form), seconds: 1.5, frame: frame)
            var cpu: [Double] = [], whole: [Double] = [], renderCPU: [Double] = []
            var s = SaiyanBodyBench.steady(form)
            for _ in 0..<60 {
                s.time += 1.0 / 30
                let f = bench.h.at(frame, time: 10 + s.time)
                var started = CFAbsoluteTimeGetCurrent()
                let back = bench.aura.backLayer(f, s)
                let light = bench.aura.frontLight(f, s)
                _ = bench.aura.screenEffect(s)
                cpu.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
                var picture = SaiyanCompose.person(f, over: back, effect: .none)
                if let light { picture = WorldKit.adding(light, to: picture) }
                started = CFAbsoluteTimeGetCurrent()
                let threadStarted = Self.threadCPU()
                bench.h.compositor.render(picture, into: buffer)
                renderCPU.append((Self.threadCPU() - threadStarted) * 1000)
                whole.append((CFAbsoluteTimeGetCurrent() - started) * 1000 + cpu.last!)
            }
            let mean = cpu.reduce(0, +) / Double(cpu.count), wholeMean = whole.reduce(0, +) / Double(whole.count)
            let prep = renderCPU.reduce(0, +) / Double(renderCPU.count)
            report.append(String(format: "%@ cpu %.2f ms (worst %.2f) + Core Image's own cpu while rendering %.2f ms, wall with rendering %.2f ms",
                                 form.shortTitle, mean, cpu.max() ?? 0, prep, wholeMean))
            // The budget is 4 ms of CPU; the machine is shared with other builds, so the bound here is generous.
            XCTAssertLessThan(mean, 8, "\(form): \(mean) ms")
        }
        print("SaiyanBody cost: " + report.joined(separator: "; "))
    }

    /// CPU time this thread has used, in seconds.
    private static func threadCPU() -> Double {
        var t = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
        return Double(t.tv_sec) + Double(t.tv_nsec) / 1e9
    }

    // MARK: Pictures

    func testContactSheetOfEveryForm() {
        for withBackdrop in [true, false] {
            let bench = SaiyanBodyBench()
            bench.background = withBackdrop
            let frame = bench.input()
            var pictures: [CIImage] = []
            for form in SaiyanForm.allCases {
                let out = bench.hold(SaiyanBodyBench.steady(form), seconds: 1.2, frame: frame)
                if form != .base { Output.save(out, as: "body-\(form.shortTitle)\(withBackdrop ? "" : "-room").png") }
                pictures.append(bench.capture(out))
            }
            Output.save(SaiyanBench.sheet(pictures, columns: 4, scale: 0.5), as: withBackdrop ? "body-sheet-forms.png" : "body-sheet-forms-room.png")
        }
    }

    func testContactSheetOfAPowerUpAndALevelUp() {
        let bench = SaiyanBodyBench()
        let hands = fists()
        let frame = bench.input(hands: hands)
        var pictures: [CIImage] = []
        var taken = Set<Int>()
        // Charging from base, the change to Super Saiyan, the burst settling, then charging on toward Super Saiyan 2 and its change.
        for i in 0..<120 {
            guard let out = bench.drive(hands, frame: frame) else { continue }
            let marks = [6, 14, 20, 26, 28, 29, 30, 32, 35, 40, 50, 60, 70, 76, 77, 79]
            if marks.contains(i), !taken.contains(i) {
                taken.insert(i)
                pictures.append(bench.capture(out))
                if i == 20 || i == 29 || i == 32 || i == 70 { Output.save(out, as: "body-powerup-\(i).png") }
            }
        }
        Output.save(SaiyanBench.sheet(pictures, columns: 4, scale: 0.5), as: "body-sheet-powerup.png")
    }

    func testContactSheetOnARealHeadAtThreeSizes() {
        let h = LensHarness()
        let grid = MatteGrid(outputSize: SyntheticScene.size)
        var pictures: [CIImage] = []
        for form in [SaiyanForm.superSaiyan, .superSaiyan3, .superSaiyanGod, .blueKaioken, .ultraEgo, .ultraInstinct] {
            for (io, centre, roll) in [(72.0, CGPoint(x: 640, y: 380), 0.0), (40.0, CGPoint(x: 900, y: 300), 0.3), (110.0, CGPoint(x: 600, y: 330), -0.25)] {
                let head = HeadwearRealHead(center: centre, io: io, roll: roll)
                var frame = head.input(services: h.services)
                if let matte = frame.matte { grid.update(from: matte, rect: frame.rect, context: h.ciContext) }
                frame = SaiyanBodyBench.with(frame, grid: grid)
                let aura = SaiyanAura()
                var s = SaiyanBodyBench.steady(form)
                var out = frame.composed
                for i in 0..<36 {
                    s.time = Double(i) / 30
                    let f = h.at(frame, time: s.time)
                    var picture = SaiyanCompose.person(f, over: aura.backLayer(f, s), effect: .none)
                    if let light = aura.frontLight(f, s) { picture = WorldKit.adding(light, to: picture) }
                    out = picture
                }
                pictures.append(SaiyanBodyBench.capture(out, h))
            }
        }
        Output.save(SaiyanBench.sheet(pictures, columns: 3, scale: 0.5), as: "body-sheet-realhead.png")
    }

    func testContactSheetOfTransitionsAndCalmingDown() {
        let bench = SaiyanBodyBench()
        let frame = bench.input()
        var pictures: [CIImage] = []
        for (from, to) in [(SaiyanForm.superSaiyan3, SaiyanForm.superSaiyanGod), (.superSaiyanBlue, .blueKaioken), (.ultraEgo, .base)] {
            bench.hold(SaiyanBodyBench.steady(from), seconds: 1, frame: frame)
            var s = SaiyanBodyBench.steady(to)
            s.previousForm = from
            s.level = from.power
            for k in [0.0, 0.2, 0.5, 1.0] {
                s.transition = k
                s.sinceChange = k * 0.7
                s.flash = to > from ? max(0, 1 - s.sinceChange / 0.6) : 0.35 * max(0, 1 - s.sinceChange / 0.6)
                pictures.append(bench.capture(bench.hold(s, seconds: 1.0 / 30, frame: frame)))
            }
        }
        Output.save(SaiyanBench.sheet(pictures, columns: 4, scale: 0.5), as: "body-sheet-transitions.png")
    }
}
