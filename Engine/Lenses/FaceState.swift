import CoreGraphics
import Foundation

/// Where a face is and what it is doing, in output pixels (origin lower left, y up).
///
/// "Left" and "right" are as they appear in the picture, so `leftEye.x < rightEye.x`.
struct FaceState: Equatable {
    var leftEye: CGPoint
    var rightEye: CGPoint
    var mouth: CGPoint
    var mouthWidth: Double
    var browCenter: CGPoint
    var rect: CGRect
    /// 0 for a closed mouth to 1 for wide open.
    var mouthOpen: Double
    /// 0 at rest to 1 for eyebrows hoisted high. Relative to how this face looks at rest.
    var browRaise: Double
    /// Eyebrow height above the eyes, in eye-spacings. The raw measurement behind `browRaise`.
    var browDistance: Double
    /// 0 with the eyes open to 1 with them shut. Relative to how wide open this face's eyes are.
    var blink: Double = 0
    /// 0 at rest to 1 for a broad smile. Relative to how wide this face's mouth is at rest.
    var smile: Double = 0

    var eyeCenter: CGPoint { CGPoint(x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2) }
    var interocular: Double { hypot(rightEye.x - leftEye.x, rightEye.y - leftEye.y) }

    /// Head tilt in radians, positive when the head tips counter-clockwise on screen.
    var roll: Double { atan2(rightEye.y - leftEye.y, rightEye.x - leftEye.x) }

    /// Unit vector pointing up the face, from the mouth toward the eyes. Follows a tilted head.
    var up: CGVector {
        let dx = eyeCenter.x - mouth.x, dy = eyeCenter.y - mouth.y
        let length = max(hypot(dx, dy), 1e-9)
        return CGVector(dx: dx / length, dy: dy / length)
    }

    /// Unit vector pointing to the face's right-in-the-picture.
    var across: CGVector { CGVector(dx: up.dy, dy: -up.dx) }

    /// The tip of the nose, a little over halfway from the eyes to the mouth.
    var nose: CGPoint { point(from: eyeCenter, toward: mouth, fraction: 0.62) }

    /// The top of the head, estimated from the eye spacing.
    var headTop: CGPoint { point(along: up, from: eyeCenter, distance: interocular * 1.55) }

    /// Where a hat's brim sits: the forehead.
    var forehead: CGPoint { point(along: up, from: eyeCenter, distance: interocular * 0.95) }

    private func point(from a: CGPoint, toward b: CGPoint, fraction: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
    }

    private func point(along v: CGVector, from a: CGPoint, distance: Double) -> CGPoint {
        CGPoint(x: a.x + v.dx * distance, y: a.y + v.dy * distance)
    }
}
