import CoreImage
import XCTest

/// Real tracking trembles, misreads a finger now and then and loses the hand for a moment. These feed the hand filters hands like that
/// and check that what they show stays steady.
final class HandFilterRobustnessTests: XCTestCase {
    private let h = LensHarness()
    private lazy var base = h.input()
    private var frame = 0
    private var rng = SplitMix64(seed: 0x7E57)

    @discardableResult
    private func step(_ lens: Lens, _ hands: [HandState]) -> CIImage {
        defer { frame += 1 }
        return lens.render(h.at(base, time: Double(frame) / 30, hands: hands))
    }

    /// The hand with every joint nudged by up to `amount` pixels, as Vision's points shiver from look to look.
    private func shaky(_ hand: HandState, _ amount: Double = 4) -> HandState {
        var out = hand
        out.joints = hand.joints.map { CGPoint(x: Double($0.x) + Double.random(in: -amount...amount, using: &rng),
                                               y: Double($0.y) + Double.random(in: -amount...amount, using: &rng)) }
        return out
    }

    func testABladeHeldInATremblingFistStaysLitAndSteady() {
        let lens = LightBladeLens()
        let fist = HandFixtures.hand(.fist, at: CGPoint(x: 600, y: 140), size: 110, angle: -0.3)
        for _ in 0..<15 { step(lens, [shaky(fist)]) }
        var angles: [Double] = []
        for _ in 0..<60 {
            step(lens, [shaky(fist)])
            guard let blade = lens.blades.first else { return XCTFail("the blade went out") }
            XCTAssertGreaterThan(blade.strength, 0.9)
            angles.append(atan2(blade.direction.y, blade.direction.x))
        }
        let jumps = zip(angles, angles.dropFirst()).map { abs($1 - $0) }
        XCTAssertLessThan(jumps.max() ?? 0, 2.5 * .pi / 180, "the blade's far end does not shake")
    }

    func testFireKeepsBurningWhenAFingerIsMisreadNowAndThen() {
        let lens = FireHandsLens()
        let open = HandFixtures.hand(.open, at: CGPoint(x: 640, y: 180), size: 120)
        let misread = HandFixtures.hand(HandFixtures.Fingers(index: true, middle: false, ring: true, little: true, thumb: 1), at: open.wrist, size: 120)
        for i in 0..<90 {
            step(lens, [shaky(i % 5 == 0 ? misread : open)])
            if i > 25 { XCTAssertGreaterThan(lens.burn, 0.7, "frame \(i)") }
        }
    }

    func testLightningArcsDoNotBlinkWithAFingerTheTrackerIsUnsureOf() {
        let lens = FingerLightningLens()
        let open = HandFixtures.hand(.open, at: CGPoint(x: 640, y: 180), size: 120)
        let unsure = HandFixtures.hand(HandFixtures.Fingers(index: true, middle: false, ring: true, little: true, thumb: 1), at: open.wrist, size: 120)
        for _ in 0..<10 { step(lens, [open]) }
        var counts: [Int] = []
        for i in 0..<40 {
            step(lens, [i % 2 == 0 ? unsure : open])
            counts.append(lens.arcs.filter { $0.key % 100 < 50 }.count)
        }
        XCTAssertEqual(Set(counts).count, 1, "the same arcs stay up while one finger flickers frame to frame: \(counts)")
    }

    func testAGlassHeldInATremblingHandStaysPutAndKeepsItsSize() {
        let lens = MagnifierLens()
        let hand = HandFixtures.gun(from: CGPoint(x: 560, y: 330), toward: CGPoint(x: 620, y: 600), size: 120)
        for _ in 0..<15 { step(lens, [shaky(hand)]) }
        var centres: [CGPoint] = [], radii: [Double] = []
        for _ in 0..<45 {
            step(lens, [shaky(hand)])
            guard let glass = lens.glasses.first else { return XCTFail("the glass went away") }
            XCTAssertGreaterThan(glass.show, 0.9)
            centres.append(glass.centre)
            radii.append(glass.radius)
        }
        let moves = zip(centres, centres.dropFirst()).map { HandFXKit.distance($0, $1) }
        XCTAssertLessThan(moves.max() ?? 0, 2.5, "it trembles less than the hand does")
        XCTAssertLessThan((radii.max() ?? 0) - (radii.min() ?? 0), 4)
    }

    func testAHandLostForAMomentAndFoundUnderANewIDCarriesOn() {
        // The tracker loses the hand for longer than it holds on, then finds it again as a new hand nearby.
        let lens = FrostHandsLens()
        let palm = HandFixtures.hand(.open, at: CGPoint(x: 500, y: 180), size: 120, id: 1)
        for _ in 0..<60 { step(lens, [palm]) }
        let frost = lens.frost
        step(lens, [])
        step(lens, [])
        var again = HandFixtures.moved(palm, by: CGVector(dx: 20, dy: 6))
        again.id = 7
        step(lens, [again])
        XCTAssertGreaterThan(lens.frost, frost * 0.9, "the ice is still there: the hand is the same hand")
    }

    func testTheHologramSitsStillOnATremblingHand() {
        let lens = HologramHandLens()
        let palm = HandFixtures.hand(.open, at: CGPoint(x: 500, y: 180), size: 120)
        for _ in 0..<20 { step(lens, [shaky(palm)]) }
        var tips: [CGPoint] = []
        for _ in 0..<40 {
            step(lens, [shaky(palm)])
            tips.append(lens.hands[0].indexTip)
        }
        let moves = zip(tips, tips.dropFirst()).map { HandFXKit.distance($0, $1) }
        XCTAssertLessThan(moves.reduce(0, +) / Double(moves.count), 2.5, "a 4-pixel shiver becomes a small drift")
    }
}
