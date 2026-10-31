import CoreGraphics
import Foundation
import simd

/// Turns a noisy 0...1 face reading (an eyebrow lift, a blink) into a steady on/off switch.
///
/// It comes on when the reading reaches `on`. It only goes off again once the reading has stayed under `off` for `offDelay`
/// seconds, so a reading that jitters around one number can't flick it on and off, and a single bad frame can't let go of
/// something the player is holding.
struct FaceGameTrigger: Equatable {
    var on: Double
    var off: Double
    var offDelay: Double
    private(set) var isOn = false
    /// True only for the one update in which it came on.
    private(set) var justTurnedOn = false
    /// How long it has been on, counting the update it came on in.
    private(set) var onFor = 0.0
    private var belowFor = 0.0

    init(on: Double, off: Double, offDelay: Double = 0) {
        self.on = on
        self.off = min(off, on)
        self.offDelay = offDelay
    }

    mutating func update(_ value: Double, dt: Double) {
        justTurnedOn = false
        if isOn {
            if value < off {
                belowFor += dt
                if belowFor >= offDelay {
                    isOn = false
                    onFor = 0
                    belowFor = 0
                    return
                }
            } else {
                belowFor = 0
            }
            onFor += dt
        } else if value >= on {
            isOn = true
            justTurnedOn = true
            onFor = dt
            belowFor = 0
        }
    }

    mutating func reset() {
        isOn = false
        justTurnedOn = false
        onFor = 0
        belowFor = 0
    }
}

/// Turns where the nose is into a spot on the picture, for games steered by moving your head.
///
/// Wherever the nose is when the game first sees it becomes the middle of the picture, so someone sitting off to one side plays
/// as well as someone in the centre, and one eye-spacing of movement reaches `reach` pixels, so the same nod works near the camera
/// and far from it. The spot follows smoothly and stays put while the face is missing.
struct FaceGameSteer {
    var reach: Double
    /// How quickly the spot catches up with the nose, per second.
    var rate: Double = 12
    private(set) var spot: SIMD2<Double>
    private(set) var anchor: SIMD2<Double>?
    private var spacing = 84.0

    init(reach: Double, start: SIMD2<Double>, rate: Double = 12) {
        self.reach = reach
        self.rate = rate
        spot = start
    }

    /// Where the nose says the spot should go, before smoothing.
    func goal(for face: FaceState, middle: SIMD2<Double>) -> SIMD2<Double> {
        let nose = SIMD2(Double(face.nose.x), Double(face.nose.y))
        let gain = reach / max(spacing, 20)
        return middle + (nose - (anchor ?? nose)) * gain
    }

    mutating func update(_ face: FaceState?, middle: SIMD2<Double>, bounds: CGRect, dt: Double) {
        guard let face else { return }
        if anchor == nil {
            anchor = SIMD2(Double(face.nose.x), Double(face.nose.y))
            spacing = max(face.interocular, 20)
        }
        var want = goal(for: face, middle: middle)
        want.x = min(Double(bounds.maxX), max(Double(bounds.minX), want.x))
        want.y = min(Double(bounds.maxY), max(Double(bounds.minY), want.y))
        spot += (want - spot) * (1 - exp(-rate * max(0, dt)))
    }
}
