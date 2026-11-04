import CoreGraphics
import Foundation

/// Where the hands are against the face, in one place, so the moves that share a pose agree about it. Everything is measured in
/// face units (the eye spacing is 1, the origin is between the eyes, y runs up the face), so it reads the same for a near face and a far
/// one and for a tilted head.
///
/// The moves use these to claim their own corner of the picture and keep out of each other's:
///   forehead   two fingers touching the forehead          Special Beam Cannon, Instant Transmission
///   face       both hands in front of the face            Solar Flare
///   overhead   a hand above the top of the head           Spirit Bomb (two hands), Destructo Disc (one)
///   below the chin, hands together                        Kamehameha (fingers pointing sideways), Final Flash (fingers up)
/// A mover may tighten a threshold here if its fixtures need it, but must say so in its report: other moves read the same numbers.
enum SaiyanZones {
    /// A touch of the forehead shorter than this is Instant Transmission; held longer it is Special Beam Cannon charging.
    static let instantTransmissionLimit = 0.6

    /// A point in face units.
    static func local(_ p: CGPoint, _ face: FaceState) -> CGPoint { HeadwearFrame.local(p, of: face) }

    /// A hand's palm in face units.
    static func palm(_ hand: HandState, _ face: FaceState) -> CGPoint { local(hand.palm, face) }

    /// How far the hand is from the face, in eye spacings: the palm to the middle of the face (between the eyes and the mouth).
    static func distanceToFace(_ hand: HandState, _ face: FaceState) -> Double {
        let io = max(face.interocular, 1)
        let middle = CGPoint(x: (face.eyeCenter.x + face.mouth.x) / 2, y: (face.eyeCenter.y + face.mouth.y) / 2)
        return HandState.distance(hand.palm, middle) / io
    }

    /// Index and middle fingers out, ring and little curled, the tips of the two within `reach` eye spacings of the forehead.
    static func fingersAtForehead(_ hand: HandState, _ face: FaceState, reach: Double = 0.8) -> Bool {
        let index = HandFXPose.extended(.index, in: hand), middle = HandFXPose.extended(.middle, in: hand)
        let others = max(HandFXPose.extended(.ring, in: hand), HandFXPose.extended(.little, in: hand))
        guard min(index, middle) > 0.55, others < 0.5 else { return false }
        let tips = CGPoint(x: (hand[.indexTip].x + hand[.middleTip].x) / 2, y: (hand[.indexTip].y + hand[.middleTip].y) / 2)
        return HandState.distance(tips, face.forehead) / max(face.interocular, 1) < reach
    }

    /// The palm above the top of the head and not far to either side of it.
    static func isOverhead(_ hand: HandState, _ face: FaceState) -> Bool {
        let p = palm(hand, face)
        return p.y > 1.45 && abs(p.x) < 3.4
    }

    /// The palm in front of the face: within `reach` eye spacings of the middle of it.
    static func isNearFace(_ hand: HandState, _ face: FaceState, reach: Double = 1.7) -> Bool {
        distanceToFace(hand, face) < reach
    }

    /// Whether the palms of two hands are within `palms` palm lengths of each other.
    static func together(_ a: HandState, _ b: HandState, within palms: Double = 2) -> Bool {
        HandState.distance(a.palm, b.palm) < max(a.size, b.size) * palms
    }

    /// Which way the fingers point, as an angle from sideways: 0 for pointing straight left or right across the picture, 90 for straight up.
    /// (Kamehameha holds its hands pointing sideways, Final Flash holds them up.)
    static func fingerElevation(_ hand: HandState) -> Double {
        let a = hand.axis
        return atan2(abs(Double(a.dy)), abs(Double(a.dx))) * 180 / .pi
    }
}
