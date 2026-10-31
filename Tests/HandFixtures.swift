import CoreGraphics
import Foundation

/// Hands to test with: made-up ones for any pose, anywhere, at any size, and a few that Vision actually reported.
enum HandFixtures {
    /// Which fingers are held out.
    struct Fingers {
        var index = true, middle = true, ring = true, little = true
        /// 0 for a thumb tucked against the hand, 1 for one stuck out.
        var thumb = 1.0

        static let open = Fingers()
        static let fist = Fingers(index: false, middle: false, ring: false, little: false, thumb: 0)
        static let point = Fingers(index: true, middle: false, ring: false, little: false, thumb: 0)
        static let peace = Fingers(index: true, middle: true, ring: false, little: false, thumb: 0)
        static let gun = Fingers(index: true, middle: false, ring: false, little: false, thumb: 1)
        /// A finger gun with its hammer down: the thumb folded in.
        static let gunFired = Fingers(index: true, middle: false, ring: false, little: false, thumb: 0)

        /// 0 for fingertips apart, 1 for the thumb tip and index tip pressed together (the index bends over to meet the thumb).
        var pinch = 0.0
        /// The thumb sticks straight out from the side of the hand, as in a thumbs up, instead of up alongside the fingers.
        var thumbStraightOut = false

        /// A fist with the thumb straight out from its side. Turn it so the thumb points up (`HandFixtures.thumbsUp`) for a thumbs up.
        static let thumbsUp = Fingers(index: false, middle: false, ring: false, little: false, thumb: 1, thumbStraightOut: true)
        /// Thumb and index tips together, the other three folded.
        static let pinch = Fingers(index: true, middle: false, ring: false, little: false, thumb: 1, pinch: 1)
        /// Thumb and index tips together in a ring, the other three out.
        static let okSign = Fingers(index: true, middle: true, ring: true, little: true, thumb: 1, pinch: 1)
    }

    // A right hand, palm length 1, wrist at the origin and fingers pointing up (+y), thumb on the +x side.
    private static let knuckles: [Finger: (x: Double, y: Double)] = [.index: (0.30, 0.97), .middle: (0.06, 1.0), .ring: (-0.17, 0.95), .little: (-0.38, 0.83)]
    private static let segments: [Finger: (Double, Double, Double)] = [.index: (0.40, 0.24, 0.20), .middle: (0.45, 0.27, 0.21),
                                                                      .ring: (0.42, 0.25, 0.20), .little: (0.32, 0.18, 0.17)]
    private static let spread: [Finger: Double] = [.index: 0.09, .middle: 0, .ring: -0.07, .little: -0.16]

    /// A hand with its wrist at `wrist`. `angle` turns it counter-clockwise from fingers-up; `size` is the palm length in pixels.
    static func hand(_ fingers: Fingers, at wrist: CGPoint = CGPoint(x: 640, y: 300), size: Double = 100, angle: Double = 0,
                     mirrored: Bool = false, id: Int = 1, velocity: CGVector = .zero, tipVelocity: CGVector = .zero) -> HandState {
        var local = [(Double, Double)](repeating: (0, 0), count: HandJoint.count)
        func set(_ joint: HandJoint, _ x: Double, _ y: Double) { local[joint.rawValue] = (x, y) }

        let t = min(1, max(0, fingers.thumb))
        set(.thumbCMC, 0.22, 0.22); set(.thumbMP, 0.40, 0.42)
        if fingers.thumbStraightOut {
            set(.thumbMP, 0.45, 0.40)
            set(.thumbIP, 0.45 + 0.40 * t, 0.40 + 0.12 * t)
            set(.thumbTip, 0.45 + 0.85 * t, 0.40 + 0.22 * t)
        } else {
            set(.thumbIP, 0.30 + 0.32 * t, 0.62 + 0.04 * t)
            set(.thumbTip, 0.20 + 0.60 * t, 0.80 + 0.06 * t)
        }

        let on: [Finger: Bool] = [.index: fingers.index, .middle: fingers.middle, .ring: fingers.ring, .little: fingers.little]
        for finger in Finger.long {
            let k = knuckles[finger]!, (p, m, d) = segments[finger]!, a = spread[finger]!
            let (mcp, pip, dip, tip) = (finger.knuckle, finger.middleJoint, HandJoint(rawValue: finger.middleJoint.rawValue + 1)!, finger.tip)
            set(mcp, k.x, k.y)
            if on[finger]! {
                let dx = sin(a), dy = cos(a)
                set(pip, k.x + dx * p, k.y + dy * p)
                set(dip, k.x + dx * (p + m), k.y + dy * (p + m))
                set(tip, k.x + dx * (p + m + d), k.y + dy * (p + m + d))
            } else {
                // Curled into the palm: the middle joint sticks up a little and the tip folds back down below the knuckle.
                set(pip, k.x, k.y + p * 0.2)
                set(dip, k.x, k.y - 0.04)
                set(tip, k.x, k.y - 0.18)
            }
        }
        if fingers.pinch > 0 {
            // The index bends over and the thumb comes up to meet it in front of the knuckles.
            let k = min(1, fingers.pinch)
            let meet: [(HandJoint, Double, Double)] = [(.indexPIP, 0.38, 1.25), (.indexDIP, 0.52, 1.42), (.indexTip, 0.60, 1.38),
                                                       (.thumbMP, 0.42, 0.45), (.thumbIP, 0.56, 0.86), (.thumbTip, 0.60, 1.31)]
            for (joint, x, y) in meet {
                let p = local[joint.rawValue]
                set(joint, p.0 + (x - p.0) * k, p.1 + (y - p.1) * k)
            }
        }
        return place(local, at: wrist, size: size, angle: angle, mirrored: mirrored, id: id, velocity: velocity, tipVelocity: tipVelocity)
    }

    /// A thumbs up (or, with `down`, a thumbs down) with its wrist at `wrist`: the fist turned on its side so the thumb points up.
    static func thumbsUp(at wrist: CGPoint = CGPoint(x: 640, y: 300), size: Double = 100, down: Bool = false, mirrored: Bool = false,
                         id: Int = 1) -> HandState {
        let turn = (down ? -1.0 : 1.0) * (mirrored ? -1.0 : 1.0) * Double.pi / 2
        return hand(.thumbsUp, at: wrist, size: size, angle: turn, mirrored: mirrored, id: id)
    }

    static func openPalm(at wrist: CGPoint = CGPoint(x: 640, y: 300), size: Double = 100, angle: Double = 0, id: Int = 1) -> HandState {
        hand(.open, at: wrist, size: size, angle: angle, id: id)
    }

    /// A finger gun whose index finger runs from `base` toward `target`.
    static func gun(from base: CGPoint, toward target: CGPoint, size: Double = 100, thumb: Double = 1, id: Int = 1) -> HandState {
        let heading = atan2(Double(target.y - base.y), Double(target.x - base.x))
        var fingers = Fingers.gun
        fingers.thumb = thumb
        // The wrist sits one palm and a bit behind the knuckle, so put it back along the heading.
        let wrist = CGPoint(x: base.x - cos(heading) * size, y: base.y - sin(heading) * size)
        return hand(fingers, at: wrist, size: size, angle: heading - .pi / 2, id: id)
    }

    /// The same hand with its whole shape slid to a new place and given a speed.
    static func moved(_ h: HandState, by offset: CGVector, velocity: CGVector? = nil, tipVelocity: CGVector? = nil) -> HandState {
        var out = h
        out.joints = h.joints.map { CGPoint(x: $0.x + offset.dx, y: $0.y + offset.dy) }
        if let velocity { out.velocity = velocity }
        if let tipVelocity { out.tipVelocity = tipVelocity }
        return out
    }

    private static func place(_ local: [(Double, Double)], at wrist: CGPoint, size: Double, angle: Double, mirrored: Bool, id: Int,
                              velocity: CGVector, tipVelocity: CGVector) -> HandState {
        let c = cos(angle), s = sin(angle)
        let joints = local.map { p -> CGPoint in
            let x = (mirrored ? -p.0 : p.0) * size, y = p.1 * size
            return CGPoint(x: Double(wrist.x) + x * c - y * s, y: Double(wrist.y) + x * s + y * c)
        }
        return HandState(id: id, joints: joints, velocity: velocity, tipVelocity: tipVelocity)
    }

    // MARK: What Vision reported

    /// Joints Vision gave for emoji hands, in palm lengths from the wrist, in `HandJoint` order. They are the only real measurements
    /// the gesture rules were checked against.
    enum Recorded {
        /// ✋
        static let openPalm: [(Double, Double)] = [(0, 0), (0.43, 0.20), (0.68, 0.54), (0.92, 0.80), (1.27, 0.92), (0.37, 1.01), (0.41, 1.39), (0.40, 1.68), (0.43, 2.03),
                                                   (0.08, 1.00), (0.05, 1.44), (0.04, 1.78), (0.04, 2.17), (-0.21, 0.91), (-0.28, 1.30), (-0.30, 1.59), (-0.33, 1.96),
                                                   (-0.52, 0.75), (-0.59, 1.02), (-0.61, 1.23), (-0.64, 1.50)]
        /// 👆: the index finger up and the thumb out to the side
        static let pointUp: [(Double, Double)] = [(0, 0), (-0.47, 0.11), (-0.74, 0.42), (-0.85, 0.85), (-1.06, 1.14), (-0.49, 0.91), (-0.51, 1.39), (-0.48, 1.71), (-0.49, 2.02),
                                                  (-0.15, 0.99), (-0.17, 1.06), (-0.18, 0.91), (-0.18, 0.78), (0.13, 0.97), (0.09, 1.01), (0.04, 0.88), (0.04, 0.77),
                                                  (0.41, 0.88), (0.32, 0.92), (0.27, 0.82), (0.27, 0.71)]
        /// 👉: the index finger out to the right, the thumb up, the rest curled. As near to a finger gun as there is.
        static let pointRight: [(Double, Double)] = [(0, 0), (0.09, 0.43), (0.39, 0.70), (0.81, 0.82), (1.09, 1.02), (0.90, 0.47), (1.36, 0.46), (1.65, 0.46), (1.92, 0.49),
                                                     (0.99, 0.13), (0.94, 0.17), (0.78, 0.20), (0.65, 0.19), (0.94, -0.13), (0.88, -0.06), (0.75, -0.01), (0.63, -0.01),
                                                     (0.85, -0.39), (0.81, -0.28), (0.70, -0.23), (0.58, -0.22)]
    }

    /// One hand as Vision read it from a rendered picture, kept to test the gesture rules against: what the picture was, what it
    /// should read as, the joints in palm lengths from the wrist (in `HandJoint` order) and Vision's confidence in each.
    struct Reading {
        let picture: String
        let expected: HandGesture.Pose
        let joints: [(Double, Double)]
        let confidence: [Double]
    }

    /// Readings from the probe in out/handlab: 32 hand emoji in four skin tones, turned up to 180 degrees, 150 to 460 points tall on a
    /// 1280x720 picture of a room, clean, blurred, smeared by motion, noisy and dark (2,184 pictures; Vision found a hand in 943).
    /// A few of each pose the games use, picked across the conditions. The finger pointed at the camera (🫵) reads as a fist, which
    /// is why `HandGestureRecognizer` holds a point through a fist for a moment rather than trusting one frame.
    static let gallery: [Reading] = [
            Reading(picture: "✋🏿 dark skin, upright, turned 0°, 150 pt, clean", expected: .openPalm,
                    joints: [(0.00, 0.00), (0.45, 0.23), (0.74, 0.61), (1.00, 0.88), (1.32, 0.95), (0.38, 1.01), (0.43, 1.47), (0.43, 1.79), (0.46, 2.15), (0.08, 1.00), (0.06, 1.51), (0.04, 1.91), (0.04, 2.30), (-0.20, 0.93), (-0.28, 1.36), (-0.31, 1.70), (-0.34, 2.08), (-0.51, 0.76), (-0.59, 1.06), (-0.63, 1.29), (-0.68, 1.59)],
                    confidence: [0.68, 0.64, 0.78, 0.82, 0.91, 0.79, 0.87, 0.88, 0.91, 0.83, 0.88, 0.90, 0.89, 0.82, 0.88, 0.86, 0.88, 0.83, 0.85, 0.84, 0.90]),
            Reading(picture: "✋🏻 light skin, blurred, turned 0°, 150 pt, blur", expected: .openPalm,
                    joints: [(0.00, 0.00), (0.43, 0.21), (0.68, 0.58), (0.93, 0.82), (1.25, 0.95), (0.33, 1.00), (0.39, 1.42), (0.40, 1.73), (0.42, 2.11), (0.04, 1.00), (0.03, 1.48), (0.02, 1.84), (0.01, 2.24), (-0.25, 0.92), (-0.31, 1.33), (-0.33, 1.66), (-0.35, 2.03), (-0.53, 0.74), (-0.62, 1.07), (-0.64, 1.29), (-0.68, 1.56)],
                    confidence: [0.65, 0.70, 0.80, 0.85, 0.90, 0.85, 0.89, 0.90, 0.91, 0.87, 0.90, 0.90, 0.89, 0.83, 0.90, 0.87, 0.91, 0.83, 0.84, 0.89, 0.90]),
            Reading(picture: "✋🏽 medium skin, smeared by motion, turned 0°, 260 pt, motion", expected: .openPalm,
                    joints: [(0.00, 0.00), (0.42, 0.14), (0.66, 0.49), (0.90, 0.74), (1.21, 0.83), (0.35, 1.02), (0.40, 1.31), (0.44, 1.56), (0.52, 1.84), (0.05, 1.00), (0.06, 1.37), (0.09, 1.68), (0.15, 1.96), (-0.22, 0.95), (-0.21, 1.27), (-0.21, 1.53), (-0.22, 1.77), (-0.45, 0.80), (-0.49, 1.01), (-0.50, 1.17), (-0.53, 1.34)],
                    confidence: [0.67, 0.74, 0.81, 0.85, 0.81, 0.75, 0.74, 0.80, 0.77, 0.59, 0.79, 0.76, 0.74, 0.54, 0.64, 0.73, 0.67, 0.73, 0.61, 0.68, 0.66]),
            Reading(picture: "✋🏻 turned, turned 50°, 150 pt, clean", expected: .openPalm,
                    joints: [(0.00, 0.00), (0.11, 0.51), (-0.00, 0.97), (0.00, 1.38), (0.16, 1.65), (-0.54, 0.94), (-0.86, 1.27), (-1.11, 1.50), (-1.39, 1.75), (-0.72, 0.69), (-1.15, 1.02), (-1.47, 1.27), (-1.79, 1.53), (-0.84, 0.39), (-1.25, 0.61), (-1.55, 0.83), (-1.85, 1.06), (-0.89, 0.04), (-1.23, 0.17), (-1.44, 0.29), (-1.71, 0.47)],
                    confidence: [0.56, 0.64, 0.80, 0.83, 0.85, 0.83, 0.91, 0.93, 0.92, 0.87, 0.91, 0.92, 0.89, 0.87, 0.88, 0.88, 0.91, 0.81, 0.86, 0.89, 0.92]),
            Reading(picture: "✋🏻 upright, turned 0°, 150 pt, clean", expected: .openPalm,
                    joints: [(0.00, 0.00), (0.47, 0.21), (0.76, 0.60), (1.04, 0.86), (1.35, 0.97), (0.40, 1.00), (0.45, 1.46), (0.46, 1.78), (0.49, 2.18), (0.10, 1.00), (0.09, 1.52), (0.07, 1.90), (0.06, 2.30), (-0.19, 0.92), (-0.27, 1.36), (-0.29, 1.69), (-0.32, 2.10), (-0.48, 0.76), (-0.57, 1.09), (-0.61, 1.31), (-0.65, 1.60)],
                    confidence: [0.61, 0.63, 0.80, 0.83, 0.90, 0.84, 0.91, 0.92, 0.94, 0.85, 0.92, 0.91, 0.91, 0.84, 0.92, 0.89, 0.93, 0.82, 0.85, 0.88, 0.91]),
            Reading(picture: "✊🏻 light skin, blurred, turned 50°, 460 pt, blur", expected: .fist,
                    joints: [(0.00, 0.00), (0.19, 0.42), (0.05, 0.85), (-0.31, 0.88), (-0.69, 0.53), (-0.23, 0.99), (-0.62, 1.30), (-0.49, 1.21), (-0.37, 1.03), (-0.58, 0.81), (-0.88, 1.06), (-0.78, 0.99), (-0.55, 0.79), (-0.77, 0.54), (-1.07, 0.75), (-0.91, 0.68), (-0.66, 0.51), (-0.95, 0.24), (-1.21, 0.43), (-1.06, 0.35), (-0.84, 0.22)],
                    confidence: [0.27, 0.43, 0.47, 0.37, 0.66, 0.59, 0.76, 0.57, 0.52, 0.36, 0.81, 0.57, 0.52, 0.45, 0.83, 0.50, 0.46, 0.64, 0.77, 0.72, 0.61]),
            Reading(picture: "✊🏽 medium skin, smeared by motion, turned 50°, 460 pt, motion", expected: .fist,
                    joints: [(0.00, 0.00), (0.15, 0.42), (-0.03, 0.88), (-0.37, 0.90), (-0.75, 0.59), (-0.33, 0.98), (-0.67, 1.31), (-0.49, 1.16), (-0.35, 1.00), (-0.63, 0.78), (-0.91, 1.06), (-0.70, 0.91), (-0.55, 0.75), (-0.79, 0.54), (-1.09, 0.77), (-0.86, 0.64), (-0.65, 0.49), (-0.97, 0.24), (-1.24, 0.46), (-1.03, 0.36), (-0.86, 0.24)],
                    confidence: [0.54, 0.60, 0.60, 0.53, 0.56, 0.59, 0.83, 0.71, 0.47, 0.35, 0.85, 0.65, 0.57, 0.43, 0.85, 0.70, 0.62, 0.71, 0.83, 0.75, 0.64]),
            Reading(picture: "✊🏻 turned, turned 50°, 460 pt, clean", expected: .fist,
                    joints: [(0.00, 0.00), (0.16, 0.42), (0.03, 0.86), (-0.31, 0.89), (-0.70, 0.55), (-0.24, 1.00), (-0.63, 1.31), (-0.47, 1.19), (-0.35, 1.02), (-0.58, 0.81), (-0.90, 1.07), (-0.78, 0.99), (-0.55, 0.79), (-0.77, 0.56), (-1.08, 0.76), (-0.91, 0.67), (-0.67, 0.50), (-0.96, 0.25), (-1.22, 0.45), (-1.06, 0.34), (-0.84, 0.21)],
                    confidence: [0.31, 0.40, 0.43, 0.33, 0.67, 0.56, 0.76, 0.62, 0.42, 0.34, 0.79, 0.56, 0.52, 0.45, 0.84, 0.51, 0.41, 0.65, 0.77, 0.75, 0.54]),
            Reading(picture: "👊 upright, turned 0°, 300 pt, clean", expected: .fist,
                    joints: [(0.00, 0.00), (1.08, -0.08), (1.43, -0.65), (1.04, -1.19), (0.08, -1.20), (0.92, 0.91), (1.00, -0.65), (0.93, -0.71), (0.85, -0.32), (0.16, 0.99), (0.22, -0.78), (0.23, -0.69), (0.22, -0.40), (-0.51, 0.73), (-0.44, -0.84), (-0.32, -0.76), (-0.31, -0.49), (-1.05, 0.46), (-1.04, -0.68), (-0.89, -0.71), (-0.84, -0.47)],
                    confidence: [0.43, 0.37, 0.54, 0.75, 0.79, 0.81, 0.71, 0.44, 0.58, 0.81, 0.74, 0.51, 0.58, 0.82, 0.76, 0.62, 0.67, 0.82, 0.84, 0.72, 0.63]),
            Reading(picture: "👉🏿 dark skin, upright, turned 0°, 260 pt, clean", expected: .fingerGun,
                    joints: [(0.00, 0.00), (0.13, 0.43), (0.43, 0.68), (0.83, 0.82), (1.11, 1.01), (0.91, 0.44), (1.40, 0.46), (1.69, 0.46), (1.97, 0.49), (0.99, 0.11), (0.98, 0.21), (0.86, 0.28), (0.72, 0.28), (0.97, -0.14), (0.88, -0.04), (0.76, 0.04), (0.64, 0.07), (0.88, -0.40), (0.83, -0.27), (0.69, -0.17), (0.59, -0.15)],
                    confidence: [0.65, 0.68, 0.75, 0.77, 0.89, 0.72, 0.84, 0.80, 0.86, 0.73, 0.66, 0.68, 0.59, 0.85, 0.63, 0.72, 0.55, 0.83, 0.52, 0.55, 0.49]),
            Reading(picture: "☝🏻 light skin, blurred, turned 0°, 460 pt, blur", expected: .point,
                    joints: [(0.00, 0.00), (0.38, 0.17), (0.60, 0.56), (0.32, 0.84), (-0.19, 0.88), (0.48, 0.95), (0.47, 1.41), (0.46, 1.74), (0.46, 2.10), (0.14, 0.99), (0.13, 1.39), (0.12, 1.02), (0.10, 0.80), (-0.18, 1.00), (-0.20, 1.36), (-0.19, 1.00), (-0.15, 0.82), (-0.51, 0.93), (-0.51, 1.29), (-0.47, 1.03), (-0.43, 0.85)],
                    confidence: [0.71, 0.72, 0.71, 0.83, 0.83, 0.79, 0.86, 0.87, 0.87, 0.69, 0.88, 0.84, 0.69, 0.65, 0.93, 0.83, 0.72, 0.68, 0.90, 0.81, 0.81]),
            Reading(picture: "☝🏽 medium skin, smeared by motion, turned 0°, 460 pt, motion", expected: .point,
                    joints: [(0.00, 0.00), (0.39, 0.18), (0.57, 0.54), (0.35, 0.80), (-0.20, 0.82), (0.43, 0.96), (0.45, 1.39), (0.44, 1.72), (0.45, 2.03), (0.10, 0.99), (0.12, 1.33), (0.10, 0.98), (0.06, 0.80), (-0.20, 0.98), (-0.20, 1.30), (-0.18, 0.96), (-0.16, 0.78), (-0.51, 0.89), (-0.51, 1.20), (-0.44, 0.94), (-0.42, 0.77)],
                    confidence: [0.72, 0.70, 0.72, 0.76, 0.67, 0.78, 0.86, 0.87, 0.84, 0.75, 0.87, 0.81, 0.61, 0.68, 0.93, 0.84, 0.66, 0.68, 0.86, 0.85, 0.81]),
            Reading(picture: "☝🏻 turned, turned 50°, 260 pt, clean", expected: .point,
                    joints: [(0.00, 0.00), (0.10, 0.45), (-0.05, 0.82), (-0.41, 0.79), (-0.71, 0.42), (-0.41, 0.95), (-0.73, 1.23), (-0.98, 1.42), (-1.21, 1.62), (-0.67, 0.75), (-0.91, 0.98), (-0.65, 0.78), (-0.53, 0.64), (-0.86, 0.52), (-1.09, 0.71), (-0.84, 0.54), (-0.68, 0.43), (-0.97, 0.21), (-1.23, 0.42), (-1.03, 0.32), (-0.86, 0.22)],
                    confidence: [0.69, 0.71, 0.75, 0.80, 0.84, 0.71, 0.82, 0.80, 0.85, 0.72, 0.90, 0.84, 0.71, 0.64, 0.93, 0.81, 0.71, 0.68, 0.90, 0.85, 0.87]),
            Reading(picture: "👉🏻 upright, turned 0°, 260 pt, clean", expected: .fingerGun,
                    joints: [(0.00, 0.00), (0.09, 0.41), (0.37, 0.68), (0.78, 0.81), (1.09, 1.01), (0.90, 0.48), (1.37, 0.48), (1.65, 0.48), (1.93, 0.50), (0.99, 0.14), (0.93, 0.20), (0.79, 0.25), (0.65, 0.25), (0.94, -0.10), (0.86, -0.02), (0.75, 0.04), (0.65, 0.05), (0.86, -0.37), (0.82, -0.24), (0.72, -0.18), (0.62, -0.17)],
                    confidence: [0.72, 0.69, 0.76, 0.77, 0.91, 0.76, 0.88, 0.83, 0.85, 0.84, 0.68, 0.61, 0.53, 0.89, 0.65, 0.69, 0.58, 0.81, 0.64, 0.68, 0.56]),
            Reading(picture: "🫵🏿 dark skin, upright, turned 0°, 260 pt, clean", expected: .fist,
                    joints: [(0.00, 0.00), (0.68, 0.02), (0.85, -0.21), (0.61, -0.59), (-0.13, -0.77), (0.60, 0.38), (0.56, 0.91), (0.40, 0.62), (0.45, 0.22), (-0.27, 0.96), (-0.16, 0.32), (-0.02, -0.37), (0.06, -0.27), (-0.79, 0.72), (-0.71, -0.14), (-0.44, -0.49), (-0.45, -0.25), (-1.14, 0.50), (-1.12, -0.35), (-0.99, -0.40), (-0.93, -0.24)],
                    confidence: [0.29, 0.23, 0.30, 0.67, 0.84, 0.49, 0.55, 0.28, 0.14, 0.41, 0.51, 0.48, 0.24, 0.54, 0.71, 0.62, 0.62, 0.76, 0.77, 0.38, 0.52]),
            Reading(picture: "🫵🏻 light skin, blurred, turned 0°, 150 pt, blur", expected: .fist,
                    joints: [(0.00, 0.00), (0.52, 0.05), (0.79, -0.14), (0.53, -0.55), (-0.18, -0.72), (0.60, 0.44), (0.49, 0.97), (0.32, 0.82), (0.27, 0.49), (-0.23, 0.97), (-0.30, 0.56), (-0.11, -0.33), (-0.03, -0.21), (-0.88, 0.72), (-0.79, -0.03), (-0.51, -0.44), (-0.51, -0.22), (-1.21, 0.49), (-1.19, -0.34), (-1.05, -0.35), (-0.92, -0.20)],
                    confidence: [0.41, 0.39, 0.28, 0.67, 0.91, 0.51, 0.44, 0.46, 0.26, 0.23, 0.66, 0.70, 0.24, 0.40, 0.89, 0.64, 0.61, 0.78, 0.83, 0.50, 0.56]),
            Reading(picture: "🫵🏽 medium skin, smeared by motion, turned 50°, 260 pt, motion", expected: .fist,
                    joints: [(0.00, 0.00), (0.35, 0.50), (0.74, 0.52), (0.83, 0.05), (0.45, -0.49), (-0.55, 0.81), (-0.45, 0.97), (-0.22, 0.79), (0.00, 0.60), (-0.90, 0.43), (0.05, -0.31), (0.39, -0.13), (0.24, 0.06), (-1.02, -0.15), (-0.04, -0.80), (0.12, -0.49), (-0.01, -0.32), (-1.06, -0.53), (-0.39, -1.06), (-0.16, -0.81), (-0.23, -0.63)],
                    confidence: [0.29, 0.14, 0.46, 0.65, 0.73, 0.26, 0.67, 0.45, 0.39, 0.67, 0.68, 0.72, 0.48, 0.79, 0.85, 0.75, 0.75, 0.82, 0.79, 0.49, 0.64]),
            Reading(picture: "🫵🏻 turned, turned 50°, 150 pt, clean", expected: .fist,
                    joints: [(0.00, 0.00), (0.37, 0.49), (0.77, 0.58), (1.08, -0.00), (0.63, -0.79), (0.12, 0.87), (-0.30, 1.02), (-0.23, 0.73), (0.14, 0.58), (-0.89, 0.47), (-0.77, 0.19), (0.27, -0.26), (0.24, -0.04), (-1.10, -0.38), (-0.47, -0.75), (0.22, -0.72), (0.08, -0.55), (-1.17, -0.81), (-0.53, -1.22), (-0.05, -1.03), (-0.09, -0.84)],
                    confidence: [0.33, 0.45, 0.54, 0.74, 0.87, 0.37, 0.40, 0.37, 0.30, 0.16, 0.64, 0.37, 0.25, 0.14, 0.84, 0.80, 0.61, 0.59, 0.78, 0.23, 0.41]),
            Reading(picture: "🫵🏻 upright, turned 0°, 150 pt, clean", expected: .fist,
                    joints: [(0.00, 0.00), (0.50, 0.08), (0.85, -0.05), (0.64, -0.49), (-0.06, -0.63), (0.69, 0.45), (0.59, 0.97), (0.43, 0.82), (0.41, 0.59), (-0.17, 0.99), (-0.19, 0.70), (-0.01, -0.29), (0.07, -0.16), (-0.71, 0.76), (-0.64, -0.20), (-0.35, -0.39), (-0.33, -0.21), (-1.04, 0.51), (-1.01, -0.28), (-0.83, -0.32), (-0.68, -0.20)],
                    confidence: [0.31, 0.42, 0.52, 0.76, 0.91, 0.53, 0.41, 0.43, 0.25, 0.32, 0.59, 0.73, 0.33, 0.49, 0.86, 0.77, 0.62, 0.79, 0.85, 0.44, 0.51]),
            Reading(picture: "✌🏻 light skin, blurred, turned 0°, 260 pt, blur", expected: .peace,
                    joints: [(0.00, 0.00), (0.33, 0.16), (0.55, 0.53), (0.26, 0.79), (-0.15, 0.75), (0.41, 0.98), (0.47, 1.35), (0.52, 1.61), (0.58, 1.89), (0.10, 1.00), (0.04, 1.32), (-0.01, 1.57), (-0.08, 1.87), (-0.17, 0.95), (-0.19, 1.21), (-0.16, 0.86), (-0.10, 0.73), (-0.45, 0.85), (-0.46, 1.14), (-0.40, 0.92), (-0.38, 0.78)],
                    confidence: [0.71, 0.74, 0.75, 0.86, 0.84, 0.80, 0.87, 0.83, 0.87, 0.84, 0.79, 0.80, 0.87, 0.71, 0.93, 0.79, 0.69, 0.72, 0.91, 0.79, 0.71]),
            Reading(picture: "✌🏽 medium skin, smeared by motion, turned 0°, 460 pt, motion", expected: .peace,
                    joints: [(0.00, 0.00), (0.36, 0.19), (0.52, 0.50), (0.27, 0.71), (-0.13, 0.74), (0.41, 0.98), (0.46, 1.31), (0.51, 1.56), (0.55, 1.78), (0.11, 0.99), (0.05, 1.30), (-0.01, 1.53), (-0.08, 1.76), (-0.14, 0.93), (-0.18, 1.14), (-0.15, 0.84), (-0.10, 0.69), (-0.42, 0.82), (-0.44, 1.07), (-0.37, 0.81), (-0.35, 0.67)],
                    confidence: [0.71, 0.71, 0.75, 0.79, 0.81, 0.84, 0.86, 0.78, 0.84, 0.82, 0.78, 0.83, 0.86, 0.66, 0.91, 0.79, 0.67, 0.64, 0.85, 0.83, 0.75]),
            Reading(picture: "✌🏻 turned, turned 50°, 260 pt, clean", expected: .peace,
                    joints: [(0.00, 0.00), (0.08, 0.40), (-0.08, 0.78), (-0.43, 0.72), (-0.65, 0.38), (-0.48, 0.94), (-0.72, 1.20), (-0.87, 1.39), (-1.03, 1.59), (-0.69, 0.72), (-0.97, 0.89), (-1.18, 1.00), (-1.42, 1.12), (-0.82, 0.49), (-1.02, 0.63), (-0.74, 0.48), (-0.58, 0.39), (-0.90, 0.20), (-1.13, 0.38), (-0.91, 0.31), (-0.76, 0.22)],
                    confidence: [0.70, 0.71, 0.80, 0.85, 0.86, 0.77, 0.86, 0.81, 0.84, 0.84, 0.82, 0.83, 0.87, 0.73, 0.93, 0.85, 0.71, 0.74, 0.89, 0.83, 0.84]),
            Reading(picture: "👍🏿 dark skin, upright, turned 0°, 150 pt, clean", expected: .thumbsUp,
                    joints: [(0.00, 0.00), (0.27, 0.46), (0.61, 0.85), (0.71, 1.32), (0.45, 1.59), (0.96, 0.52), (1.59, 0.47), (1.06, 0.37), (0.75, 0.38), (0.99, 0.12), (1.62, 0.09), (1.05, 0.03), (0.76, 0.08), (1.02, -0.22), (1.57, -0.29), (1.03, -0.30), (0.77, -0.21), (1.01, -0.58), (1.41, -0.64), (1.03, -0.61), (0.82, -0.49)],
                    confidence: [0.66, 0.65, 0.75, 0.63, 0.71, 0.65, 0.88, 0.81, 0.87, 0.67, 0.90, 0.78, 0.90, 0.58, 0.89, 0.80, 0.90, 0.61, 0.87, 0.80, 0.79]),
            Reading(picture: "👍🏻 light skin, blurred, turned 0°, 150 pt, blur", expected: .thumbsUp,
                    joints: [(0.00, 0.00), (0.22, 0.46), (0.52, 0.84), (0.65, 1.35), (0.36, 1.59), (0.94, 0.50), (1.49, 0.49), (0.98, 0.37), (0.67, 0.37), (0.99, 0.11), (1.50, 0.10), (0.92, 0.04), (0.68, 0.09), (1.04, -0.24), (1.46, -0.27), (0.92, -0.28), (0.68, -0.20), (1.01, -0.58), (1.33, -0.62), (0.94, -0.58), (0.74, -0.48)],
                    confidence: [0.68, 0.65, 0.75, 0.70, 0.82, 0.69, 0.90, 0.73, 0.86, 0.60, 0.90, 0.77, 0.89, 0.56, 0.91, 0.77, 0.85, 0.64, 0.85, 0.73, 0.80]),
            Reading(picture: "👍🏻 turned, turned 50°, 150 pt, clean", expected: .thumbsUp,
                    joints: [(0.00, 0.00), (-0.12, 0.44), (-0.23, 0.91), (-0.52, 1.25), (-0.90, 1.37), (0.19, 1.02), (0.59, 1.48), (0.34, 1.04), (0.13, 0.82), (0.52, 0.85), (0.89, 1.24), (0.54, 0.76), (0.35, 0.64), (0.79, 0.66), (1.14, 0.98), (0.79, 0.57), (0.59, 0.48), (1.03, 0.45), (1.30, 0.68), (1.03, 0.38), (0.84, 0.32)],
                    confidence: [0.58, 0.55, 0.69, 0.70, 0.80, 0.70, 0.89, 0.76, 0.88, 0.69, 0.87, 0.76, 0.82, 0.66, 0.86, 0.76, 0.78, 0.66, 0.87, 0.75, 0.76]),
            Reading(picture: "👍🏻 upright, turned 0°, 150 pt, clean", expected: .thumbsUp,
                    joints: [(0.00, 0.00), (0.25, 0.48), (0.58, 0.87), (0.69, 1.36), (0.44, 1.69), (0.98, 0.54), (1.63, 0.51), (1.09, 0.39), (0.75, 0.41), (0.99, 0.15), (1.63, 0.10), (1.02, 0.04), (0.76, 0.11), (1.02, -0.20), (1.58, -0.29), (1.00, -0.30), (0.77, -0.19), (1.05, -0.58), (1.44, -0.64), (1.00, -0.61), (0.81, -0.49)],
                    confidence: [0.67, 0.64, 0.71, 0.73, 0.78, 0.71, 0.86, 0.80, 0.90, 0.69, 0.87, 0.79, 0.90, 0.60, 0.91, 0.77, 0.86, 0.63, 0.80, 0.78, 0.79]),
            Reading(picture: "👎 turned, turned 35°, 300 pt, clean", expected: .thumbsDown,
                    joints: [(0.00, 0.00), (0.44, -0.28), (0.92, -0.40), (1.24, -0.69), (1.29, -1.01), (1.06, 0.04), (1.50, 0.38), (1.05, 0.16), (0.83, 0.02), (0.92, 0.39), (1.30, 0.68), (0.86, 0.40), (0.68, 0.24), (0.78, 0.70), (1.08, 0.93), (0.71, 0.67), (0.53, 0.47), (0.59, 0.95), (0.79, 1.11), (0.52, 0.86), (0.40, 0.70)],
                    confidence: [0.67, 0.72, 0.79, 0.69, 0.84, 0.70, 0.89, 0.79, 0.87, 0.58, 0.90, 0.88, 0.91, 0.68, 0.92, 0.83, 0.86, 0.60, 0.85, 0.74, 0.82]),
            Reading(picture: "👎 upright, turned 0°, 300 pt, clean", expected: .thumbsDown,
                    joints: [(0.00, 0.00), (0.20, -0.43), (0.52, -0.81), (0.63, -1.22), (0.43, -1.50), (0.92, -0.51), (1.46, -0.49), (0.97, -0.41), (0.70, -0.40), (0.99, -0.14), (1.47, -0.13), (0.94, -0.11), (0.71, -0.14), (1.03, 0.19), (1.42, 0.21), (0.96, 0.19), (0.72, 0.12), (0.94, 0.51), (1.31, 0.55), (0.97, 0.50), (0.75, 0.41)],
                    confidence: [0.73, 0.70, 0.77, 0.71, 0.79, 0.65, 0.88, 0.79, 0.89, 0.63, 0.89, 0.89, 0.86, 0.63, 0.90, 0.83, 0.88, 0.57, 0.85, 0.76, 0.73]),
            Reading(picture: "🤏🏿 dark skin, upright, turned 0°, 260 pt, clean", expected: .pinch,
                    joints: [(0.00, 0.00), (-0.42, -0.02), (-0.86, 0.15), (-1.29, 0.34), (-1.64, 0.51), (-0.61, 0.83), (-1.21, 0.83), (-1.50, 0.83), (-1.75, 0.87), (-0.54, 0.84), (-1.15, 0.64), (-0.97, 0.44), (-0.71, 0.42), (-0.47, 0.74), (-0.95, 0.66), (-0.87, 0.47), (-0.66, 0.43), (-0.43, 0.66), (-0.77, 0.65), (-0.73, 0.51), (-0.57, 0.46)],
                    confidence: [0.61, 0.58, 0.76, 0.82, 0.90, 0.74, 0.78, 0.86, 0.91, 0.60, 0.77, 0.69, 0.73, 0.60, 0.60, 0.65, 0.63, 0.52, 0.50, 0.48, 0.60]),
            Reading(picture: "🤏🏻 light skin, blurred, turned 0°, 260 pt, blur", expected: .pinch,
                    joints: [(0.00, 0.00), (-0.34, 0.02), (-0.73, 0.13), (-1.18, 0.32), (-1.51, 0.50), (-0.59, 0.80), (-1.12, 0.78), (-1.38, 0.78), (-1.62, 0.82), (-0.57, 0.82), (-1.03, 0.61), (-0.84, 0.42), (-0.64, 0.42), (-0.54, 0.75), (-0.87, 0.67), (-0.77, 0.49), (-0.60, 0.48), (-0.53, 0.69), (-0.75, 0.68), (-0.69, 0.58), (-0.57, 0.54)],
                    confidence: [0.46, 0.50, 0.69, 0.81, 0.88, 0.75, 0.84, 0.87, 0.90, 0.68, 0.70, 0.71, 0.76, 0.49, 0.47, 0.50, 0.66, 0.41, 0.50, 0.46, 0.57]),
            Reading(picture: "🤏🏽 medium skin, smeared by motion, turned 0°, 460 pt, motion", expected: .pinch,
                    joints: [(0.00, 0.00), (-0.38, -0.00), (-0.82, 0.16), (-1.27, 0.35), (-1.60, 0.53), (-0.58, 0.84), (-1.16, 0.83), (-1.46, 0.83), (-1.73, 0.85), (-0.55, 0.84), (-1.09, 0.58), (-0.88, 0.41), (-0.64, 0.45), (-0.51, 0.74), (-0.91, 0.63), (-0.80, 0.47), (-0.59, 0.48), (-0.48, 0.66), (-0.77, 0.67), (-0.71, 0.55), (-0.55, 0.53)],
                    confidence: [0.60, 0.59, 0.73, 0.81, 0.86, 0.69, 0.82, 0.84, 0.90, 0.61, 0.71, 0.74, 0.62, 0.52, 0.47, 0.57, 0.68, 0.43, 0.44, 0.39, 0.59]),
            Reading(picture: "🤏🏻 turned, turned 50°, 260 pt, clean", expected: .pinch,
                    joints: [(0.00, 0.00), (-0.23, -0.23), (-0.64, -0.49), (-1.06, -0.73), (-1.44, -0.87), (-1.06, 0.08), (-1.39, -0.36), (-1.59, -0.58), (-1.77, -0.76), (-1.00, -0.03), (-1.21, -0.48), (-0.94, -0.44), (-0.82, -0.23), (-0.94, -0.08), (-1.11, -0.39), (-0.89, -0.38), (-0.79, -0.22), (-0.87, -0.09), (-1.03, -0.31), (-0.84, -0.32), (-0.76, -0.19)],
                    confidence: [0.59, 0.50, 0.69, 0.76, 0.88, 0.77, 0.85, 0.86, 0.90, 0.59, 0.79, 0.65, 0.79, 0.47, 0.42, 0.41, 0.58, 0.32, 0.36, 0.26, 0.47]),
            Reading(picture: "🤏🏻 upright, turned 0°, 150 pt, clean", expected: .pinch,
                    joints: [(0.00, 0.00), (-0.33, 0.00), (-0.75, 0.13), (-1.18, 0.32), (-1.52, 0.50), (-0.60, 0.80), (-1.14, 0.77), (-1.40, 0.79), (-1.63, 0.83), (-0.55, 0.84), (-1.04, 0.62), (-0.84, 0.44), (-0.62, 0.44), (-0.49, 0.76), (-0.88, 0.68), (-0.77, 0.51), (-0.57, 0.50), (-0.46, 0.70), (-0.75, 0.68), (-0.69, 0.59), (-0.55, 0.55)],
                    confidence: [0.50, 0.57, 0.69, 0.84, 0.84, 0.73, 0.84, 0.86, 0.91, 0.72, 0.64, 0.76, 0.76, 0.61, 0.53, 0.54, 0.70, 0.47, 0.47, 0.46, 0.55]),
            Reading(picture: "👌🏿 dark skin, upright, turned 0°, 460 pt, clean", expected: .okSign,
                    joints: [(0.00, 0.00), (-0.33, 0.04), (-0.68, 0.29), (-0.98, 0.65), (-1.11, 0.97), (0.29, 0.87), (-0.39, 1.24), (-0.76, 1.21), (-0.96, 1.12), (0.43, 0.90), (0.14, 1.53), (-0.07, 1.86), (-0.21, 2.11), (0.40, 0.93), (0.16, 1.43), (-0.09, 1.70), (-0.32, 1.93), (0.35, 0.92), (0.14, 1.28), (-0.03, 1.48), (-0.16, 1.65)],
                    confidence: [0.42, 0.64, 0.74, 0.82, 0.89, 0.71, 0.82, 0.76, 0.80, 0.75, 0.82, 0.81, 0.87, 0.61, 0.60, 0.51, 0.63, 0.53, 0.54, 0.58, 0.51]),
            Reading(picture: "👌🏻 light skin, blurred, turned 0°, 260 pt, blur", expected: .okSign,
                    joints: [(0.00, 0.00), (-0.28, 0.06), (-0.60, 0.30), (-0.89, 0.63), (-1.03, 0.98), (0.33, 0.86), (-0.33, 1.21), (-0.65, 1.22), (-0.89, 1.16), (0.46, 0.89), (0.18, 1.53), (-0.04, 1.84), (-0.16, 2.10), (0.35, 0.91), (0.10, 1.42), (-0.12, 1.67), (-0.29, 1.91), (0.24, 0.91), (0.02, 1.25), (-0.10, 1.43), (-0.20, 1.62)],
                    confidence: [0.31, 0.63, 0.75, 0.83, 0.91, 0.71, 0.79, 0.75, 0.88, 0.76, 0.84, 0.85, 0.92, 0.68, 0.60, 0.69, 0.73, 0.58, 0.69, 0.69, 0.62]),
            Reading(picture: "👌🏽 medium skin, smeared by motion, turned 0°, 460 pt, motion", expected: .okSign,
                    joints: [(0.00, 0.00), (-0.36, 0.08), (-0.71, 0.32), (-1.01, 0.71), (-1.13, 0.99), (0.31, 0.87), (-0.40, 1.23), (-0.81, 1.24), (-0.97, 1.15), (0.43, 0.90), (0.12, 1.54), (-0.09, 1.89), (-0.22, 2.14), (0.37, 0.91), (0.11, 1.46), (-0.13, 1.75), (-0.35, 1.97), (0.31, 0.89), (0.06, 1.27), (-0.10, 1.48), (-0.23, 1.70)],
                    confidence: [0.40, 0.62, 0.74, 0.77, 0.90, 0.69, 0.77, 0.76, 0.74, 0.76, 0.86, 0.82, 0.87, 0.64, 0.54, 0.52, 0.60, 0.56, 0.54, 0.60, 0.50]),
            Reading(picture: "👌🏻 turned, turned 50°, 460 pt, clean", expected: .okSign,
                    joints: [(0.00, 0.00), (-0.30, -0.28), (-0.75, -0.38), (-1.20, -0.40), (-1.55, -0.28), (-0.51, 0.77), (-1.21, 0.51), (-1.47, 0.25), (-1.63, -0.02), (-0.47, 0.88), (-1.18, 1.06), (-1.56, 1.12), (-1.86, 1.16), (-0.50, 0.87), (-1.08, 1.08), (-1.46, 0.94), (-1.77, 0.90), (-0.51, 0.85), (-1.03, 0.82), (-1.31, 0.67), (-1.49, 0.65)],
                    confidence: [0.22, 0.58, 0.74, 0.77, 0.89, 0.68, 0.73, 0.78, 0.87, 0.76, 0.85, 0.76, 0.82, 0.67, 0.45, 0.43, 0.82, 0.62, 0.39, 0.24, 0.28]),
            Reading(picture: "👌🏻 upright, turned 0°, 260 pt, clean", expected: .okSign,
                    joints: [(0.00, 0.00), (-0.31, 0.08), (-0.64, 0.33), (-0.91, 0.65), (-1.04, 0.99), (0.33, 0.86), (-0.31, 1.22), (-0.64, 1.22), (-0.89, 1.19), (0.44, 0.90), (0.16, 1.53), (-0.04, 1.84), (-0.17, 2.09), (0.36, 0.90), (0.11, 1.41), (-0.11, 1.67), (-0.30, 1.91), (0.29, 0.89), (0.06, 1.25), (-0.08, 1.44), (-0.20, 1.62)],
                    confidence: [0.29, 0.60, 0.76, 0.85, 0.92, 0.74, 0.82, 0.78, 0.89, 0.75, 0.85, 0.86, 0.91, 0.70, 0.57, 0.65, 0.70, 0.56, 0.58, 0.62, 0.56]),
    ]

    /// A recorded reading as a hand, wrist at `wrist`, palm `size` pixels long, with Vision's joint confidences.
    static func recorded(_ reading: Reading, at wrist: CGPoint = CGPoint(x: 640, y: 300), size: Double = 100, id: Int = 1) -> HandState {
        var h = recorded(reading.joints, at: wrist, size: size, id: id)
        h.jointConfidence = reading.confidence
        return h
    }

    static func recorded(_ joints: [(Double, Double)], at wrist: CGPoint = CGPoint(x: 640, y: 300), size: Double = 100, id: Int = 1) -> HandState {
        place(joints, at: wrist, size: size, angle: 0, mirrored: false, id: id, velocity: .zero, tipVelocity: .zero)
    }
}
