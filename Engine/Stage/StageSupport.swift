import CoreGraphics
import Foundation

/// How often to look for hands. Looking costs a Vision request each time, so while no hand has been seen for a couple of seconds
/// it drops to a cheap idle rate (8 looks a second), and goes back to full rate (30) the moment a hand turns up.
///
/// The idle rate still notices a hand within an eighth of a second, which is well inside the time it takes to raise one and pinch.
struct HandLookPacer {
    static let busyInterval = 0.033
    static let idleInterval = 0.125
    /// Seconds without a hand before going idle.
    static let idleAfter = 2.0

    private(set) var lastLook = -Double.infinity
    private(set) var lastHand: Double

    /// `now` starts the clock: the first couple of seconds run at full rate.
    init(now: Double) { lastHand = now }

    func isIdle(at now: Double) -> Bool { now - lastHand > Self.idleAfter }

    func interval(at now: Double) -> Double { isIdle(at: now) ? Self.idleInterval : Self.busyInterval }

    /// Whether it is time for another look; if so, it counts as taken.
    mutating func shouldLook(at now: Double) -> Bool {
        guard now - lastLook >= interval(at: now) - 1e-9 else { return false }
        lastLook = now
        return true
    }

    /// A look finished, and did or did not find a hand.
    mutating func found(_ anyHand: Bool, at now: Double) {
        if anyHand { lastHand = now }
    }

    mutating func reset(now: Double) {
        lastLook = -Double.infinity
        lastHand = now
    }
}

/// A background source that can say whether it is showing, paused, lost or not allowed: the screen and window captures.
protocol StageContentSource: BackgroundSource {
    var status: StageContentStatus { get }
    func setPaused(_ paused: Bool)
}

extension WindowCaptureSource: StageContentSource {}

/// What the pipeline tells the interface about Present, whenever it changes.
struct StageReport: Equatable {
    /// How many hands are in view, or nil while hands are not being looked for.
    var handsSeen: Int?
    var status: StageContentStatus
    /// The shared content's width over height.
    var aspect: Double
    /// Whether hand tracking is at its idle rate.
    var trackingIdle: Bool
}

extension HandState {
    /// The same hand moved by an affine transform: joints moved, speeds scaled.
    func transformed(by t: CGAffineTransform) -> HandState {
        var out = self
        out.joints = joints.map { $0.applying(t) }
        let s = hypot(t.a, t.c)
        out.velocity = CGVector(dx: velocity.dx * s, dy: velocity.dy * s)
        out.tipVelocity = CGVector(dx: tipVelocity.dx * s, dy: tipVelocity.dy * s)
        return out
    }
}
