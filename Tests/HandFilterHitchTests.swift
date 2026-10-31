import CoreImage
import XCTest

/// The hand filters bake their sprites the first time they draw, on the video queue. This checks that no frame of a filter's first second
/// (including the first time its hint, its spell, its shatter or its pop is drawn) takes long enough to be seen as a hitch. Run on its own,
/// so the sprites are not already baked by other tests.
final class HandFilterHitchTests: XCTestCase {
    func testNoHandFilterHitchesWhileItBakesItsArt() {
        let h = LensHarness()
        let base = h.input()
        let buffer = h.compositor.makeOutputBuffer()!
        let open = HandFixtures.hand(.open, at: CGPoint(x: 640, y: 200), size: 120)
        let pair = [HandFixtures.hand(.open, at: CGPoint(x: 360, y: 170), size: 110, id: 1),
                    HandFixtures.hand(.open, at: CGPoint(x: 920, y: 170), size: 110, mirrored: true, id: 2)]
        let point = HandFixtures.gun(from: CGPoint(x: 600, y: 330), toward: CGPoint(x: 800, y: 600), size: 110, thumb: 0)
        let gun = HandFixtures.gun(from: CGPoint(x: 560, y: 330), toward: CGPoint(x: 620, y: 600), size: 120)
        let fist = HandFixtures.hand(.fist, at: CGPoint(x: 640, y: 160), size: 110)
        var ring = open
        func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: 640 + x * 120, y: 200 + y * 120) }
        ring.joints[HandJoint.indexPIP.rawValue] = at(0.34, 1.37)
        ring.joints[HandJoint.indexDIP.rawValue] = at(0.5, 1.42)
        ring.joints[HandJoint.indexTip.rawValue] = at(0.63, 1.31)
        ring.joints[HandJoint.thumbIP.rawValue] = at(0.62, 0.7)
        ring.joints[HandJoint.thumbTip.rawValue] = at(0.64, 1.25)

        /// The hands for frame `i` of a filter's first seconds: nobody (so the hint shows), then the pose that brings its art out, then a
        /// burst of movement to set off whatever moving does (a throw, a spell, a shatter, a clap), then nobody again.
        func hands(for id: String, _ i: Int) -> [HandState] {
            let arrive = 30, move = id == "frost-hands" ? 80 : 56
            guard i >= arrive, i < move + 6 else { return [] }
            let moving = i >= move
            let shove = CGVector(dx: Double(i - move) * 70, dy: Double(i - move) * 20)
            func shoved(_ hand: HandState) -> HandState { moving ? HandFixtures.moved(hand, by: shove, velocity: CGVector(dx: 2400, dy: 300)) : hand }
            switch id {
            case "black-hole", "shockwave":
                return pair.map { HandFixtures.moved($0, by: CGVector(dx: (moving ? Double(i - move + 1) * 45 : 0) * ($0.id == 1 ? 1 : -1), dy: 0)) }
            case "light-blade": return [fist]
            case "magnifier": return [gun]
            case "air-paint", "laser-pointer", "magic-wand", "rainbow-ribbon": return [shoved(point)]
            case "bubble-wand": return [shoved(ring)]
            default: return [shoved(open)]
            }
        }

        var report: [String] = []
        for info in HandFilters.all {
            let made = CFAbsoluteTimeGetCurrent()
            let lens = info.make()
            let build = (CFAbsoluteTimeGetCurrent() - made) * 1000
            var worst = 0.0, worstDrawing = 0.0
            for i in 0..<130 {
                let input = h.at(base, time: Double(i) / 30, hands: hands(for: info.id, i))
                let started = CFAbsoluteTimeGetCurrent()
                let out = lens.render(input)
                let drawn = CFAbsoluteTimeGetCurrent()
                h.compositor.render(out, into: buffer)
                worst = max(worst, (CFAbsoluteTimeGetCurrent() - started) * 1000)
                worstDrawing = max(worstDrawing, (drawn - started) * 1000)
            }
            report.append("\(info.id): make \(String(format: "%.1f", build)) ms, worst drawing \(String(format: "%.1f", worstDrawing)) ms, worst frame \(String(format: "%.1f", worst)) ms")
            XCTAssertLessThan(build, 10, "\(info.name) is quick to make on the main thread")
            // The lens's own work, sprites baked included. The first frame through a new chain of Core Image filters also waits for the
            // graphics chip to compile it, once per run; that is reported but not held against the lens.
            XCTAssertLessThan(worstDrawing, 30, "\(info.name) never hitches while it draws")
        }
        print("HITCH " + report.joined(separator: "\nHITCH "))
    }
}
