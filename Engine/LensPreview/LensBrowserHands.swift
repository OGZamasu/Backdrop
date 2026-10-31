import CoreGraphics
import Foundation

/// Hands for the mannequin: the 21 joints of a hand in any of the poses the hand lenses look for, placed anywhere, at any size.
/// The same numbers are drawn and reported, so a lens that looks for a fingertip finds the fingertip it sees.
struct LensBrowserHand: Equatable {
    /// Which fingers are held out, and how far the thumb is.
    struct Fingers: Equatable {
        var index = true, middle = true, ring = true, little = true
        /// 0 tucked against the hand, 1 stuck out.
        var thumb = 1.0

        static let open = Fingers()
        static let fist = Fingers(index: false, middle: false, ring: false, little: false, thumb: 0)
        static let point = Fingers(index: true, middle: false, ring: false, little: false, thumb: 0)
        static let peace = Fingers(index: true, middle: true, ring: false, little: false, thumb: 0)
        static let gun = Fingers(index: true, middle: false, ring: false, little: false, thumb: 1)
    }

    var fingers: Fingers
    /// Where the wrist is, in output pixels.
    var wrist: CGPoint
    /// Palm length in pixels: wrist to the middle knuckle.
    var size: Double
    /// Radians counter-clockwise from fingers-up.
    var angle: Double = 0
    /// A left hand (as seen in the picture): the thumb on the other side.
    var mirrored = false
    var id = 1
    /// 0 for a thumb held where it is, 1 for its tip touching the tip of the index finger (an "O" or an OK sign).
    var pinch = 0.0

    // A right hand, palm length 1, wrist at the origin, fingers up (+y), thumb toward +x.
    private static let knuckles: [Finger: (x: Double, y: Double)] = [.index: (0.30, 0.97), .middle: (0.06, 1.0), .ring: (-0.17, 0.95), .little: (-0.38, 0.83)]
    private static let segments: [Finger: (Double, Double, Double)] = [.index: (0.40, 0.24, 0.20), .middle: (0.45, 0.27, 0.21),
                                                                      .ring: (0.42, 0.25, 0.20), .little: (0.32, 0.18, 0.17)]
    private static let spread: [Finger: Double] = [.index: 0.10, .middle: 0, .ring: -0.08, .little: -0.18]

    /// The joints in `HandJoint` order, in output pixels.
    var joints: [CGPoint] {
        var local = [(Double, Double)](repeating: (0, 0), count: HandJoint.count)
        func set(_ joint: HandJoint, _ x: Double, _ y: Double) { local[joint.rawValue] = (x, y) }

        let t = min(1, max(0, fingers.thumb))
        set(.thumbCMC, 0.22, 0.22); set(.thumbMP, 0.40, 0.42)
        set(.thumbIP, 0.30 + 0.32 * t, 0.62 + 0.04 * t)
        set(.thumbTip, 0.20 + 0.60 * t, 0.80 + 0.06 * t)
        let on: [Finger: Bool] = [.index: fingers.index, .middle: fingers.middle, .ring: fingers.ring, .little: fingers.little]
        for finger in Finger.long {
            guard let k = Self.knuckles[finger], let (p, m, d) = Self.segments[finger], let a = Self.spread[finger],
                  let dip = HandJoint(rawValue: finger.middleJoint.rawValue + 1) else { continue }
            set(finger.knuckle, k.x, k.y)
            if on[finger] == true {
                let dx = sin(a), dy = cos(a)
                set(finger.middleJoint, k.x + dx * p, k.y + dy * p)
                set(dip, k.x + dx * (p + m), k.y + dy * (p + m))
                set(finger.tip, k.x + dx * (p + m + d), k.y + dy * (p + m + d))
            } else {
                // Curled into the palm: the middle joint rises a little and the tip folds back below the knuckle.
                set(finger.middleJoint, k.x, k.y + p * 0.2)
                set(dip, k.x, k.y - 0.04)
                set(finger.tip, k.x, k.y - 0.18)
            }
        }
        if pinch > 0 {
            let to = local[HandJoint.indexTip.rawValue], k = min(1, pinch)
            func lerp(_ a: (Double, Double), _ b: (Double, Double), _ t: Double) -> (Double, Double) { (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t) }
            local[HandJoint.thumbTip.rawValue] = lerp(local[HandJoint.thumbTip.rawValue], to, k)
            local[HandJoint.thumbIP.rawValue] = lerp(local[HandJoint.thumbIP.rawValue], lerp(local[HandJoint.thumbMP.rawValue], to, 0.7), k)
        }
        let c = cos(angle), s = sin(angle)
        return local.map { p in
            let x = (mirrored ? -p.0 : p.0) * size, y = p.1 * size
            return CGPoint(x: Double(wrist.x) + x * c - y * s, y: Double(wrist.y) + x * s + y * c)
        }
    }

    /// As the hand tracker would report it, moving at the given speeds.
    func state(velocity: CGVector = .zero, tipVelocity: CGVector = .zero) -> HandState {
        HandState(id: id, joints: joints, velocity: velocity, tipVelocity: tipVelocity)
    }
}
