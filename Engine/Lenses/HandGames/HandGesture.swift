import CoreGraphics
import Foundation

/// Something a hand just did: a pose it settled into or left, a swipe, a tap, a pinch. Made by `HandGestureRecognizer` from the
/// hands of each frame, so a game can react to "the thumb went up" instead of re-reading joints every frame.
struct HandGesture: Equatable {
    /// What a hand looks like it is doing. A wider set than `HandPose`, read with thresholds measured on Vision's own output.
    enum Pose: Equatable, CaseIterable {
        case unknown
        /// All four fingers out.
        case openPalm
        /// No fingers out and the thumb folded over them.
        case fist
        /// Index finger out, the rest curled, thumb tucked.
        case point
        /// Index and middle fingers out.
        case peace
        /// Index finger out and thumb up, the rest curled.
        case fingerGun
        /// A fist with the thumb standing clear of it and pointing up the picture.
        case thumbsUp
        /// The same, pointing down.
        case thumbsDown
        /// Thumb and index fingertips together, the other three folded.
        case pinch
        /// Thumb and index fingertips together in a ring, the other three out.
        case okSign

        /// The nearest of the older, smaller set of poses.
        var handPose: HandPose {
            switch self {
            case .openPalm: return .openPalm
            case .fist, .thumbsUp, .thumbsDown: return .fist
            case .point: return .point
            case .peace: return .peace
            case .fingerGun: return .fingerGun
            case .unknown, .pinch, .okSign: return .unknown
            }
        }

        /// Whether the index finger is the one held out, as for aiming.
        var isPointing: Bool { self == .point || self == .fingerGun }

        // Thresholds, in palm lengths. Each was set between the readings of the poses it separates, measured on Vision's output for
        // emoji hands in four skin tones, turned, scaled, blurred, smeared and noisy (see `HandFixtures.gallery` in the tests).

        /// Thumb tip to index tip under this, with the index finger out of the fist, is a pinch. Vision reads 🤏 at 0.33...0.62 and
        /// 👌 at 0.12...0.51; an open hand at 1.1 or more, a pointing finger at 0.9 or more.
        static let pinchBelow = 0.45
        /// A pinch lets go above this, so a pinch held loosely does not flicker.
        static let pinchReleaseAbove = 0.62
        /// A thumb tip further than this from the top of the fist is out of it: 1.6...2.1 for 👍 and 👎, 0.35...0.62 for ✊ and 👊.
        static let thumbOutAbove = 1.15

        /// Reads one hand in one frame, with no memory.
        static func classify(_ h: HandState) -> Pose {
            let index = h.isExtended(.index), middle = h.isExtended(.middle), ring = h.isExtended(.ring), little = h.isExtended(.little)
            let up = [index, middle, ring, little].filter { $0 }.count
            // Fingertips together with the index finger reaching out of the fist: a pinch, or an OK sign when the other three stand up.
            if h.pinch < pinchBelow, h.reach(of: .index) > 1.2 {
                return [middle, ring, little].filter { $0 }.count >= 2 ? .okSign : .pinch
            }
            if up == 4 { return .openPalm }
            if index && !middle && !ring && !little { return h.thumbOpen > 0.55 ? .fingerGun : .point }
            if index && middle && !ring && !little { return .peace }
            if up == 0 {
                // The thumb must also stand up level with the knuckles: Vision reads a finger pointed down the lens (🫵) as a fist
                // with its thumb hanging below the wrist, which is not a thumbs up.
                let tip = h[.thumbTip] - h.wrist, up = h.axis
                let thumbAlong = Double(tip.dx * up.dx + tip.dy * up.dy) / h.size
                if h.thumbClearance > thumbOutAbove, thumbAlong > 0.25, Finger.long.allSatisfy(h.isCurled) {
                    let along = Double(h.thumbDirection.dy)
                    if along > 0.5 { return .thumbsUp }
                    if along < -0.5 { return .thumbsDown }
                }
                return .fist
            }
            return .unknown
        }
    }

    /// Which way a swipe went, in the picture.
    enum Direction: Equatable, CaseIterable {
        case left, right, up, down
    }

    enum Kind: Equatable {
        /// The hand has held a pose long enough to count.
        case poseStarted(Pose)
        /// It has left that pose.
        case poseEnded(Pose)
        /// A quick sweep of the whole hand; `speed` in pixels a second.
        case swipe(Direction, speed: Double)
        /// A short jab of the index fingertip that stops: a poke at something.
        case tap
        case pinchStarted
        case pinchEnded
    }

    var kind: Kind
    /// The `HandState.id` of the hand that did it.
    var hand: Int
    /// Where: the palm for poses and swipes, the fingertip for a tap, between the fingertips for a pinch.
    var point: CGPoint
    /// Seconds on the recognizer's clock.
    var time: Double
}

/// Turns the hands of each frame into steady poses and `HandGesture` events.
///
/// Tracking flickers, so nothing changes on one frame's say. A new pose must be read for a hold time of its own before it counts
/// (quick for a pinch, slower for a thumbs up, which is easy to pass through on the way to a fist), frames that read as nothing in
/// particular neither confirm nor cancel a change, and a hand is only said to have no pose after a third of a second of nothing.
///
/// A finger pointed straight at the camera is the hard case: seen end on it is foreshortened to a stub, and Vision reads the hand
/// as a fist. So a pointing hand that starts to read as a fist keeps pointing for half a second, and is reported as pointing at the
/// camera (`isTowardCamera`) meanwhile; turning your finger toward the screen to aim does not drop the aim.
struct HandGestureRecognizer {
    /// How long each pose must be read before it counts, in seconds.
    static func hold(for pose: HandGesture.Pose) -> Double {
        switch pose {
        case .pinch: return 0.06
        case .point, .fingerGun: return 0.1
        case .openPalm: return 0.12
        case .fist, .peace: return 0.15
        case .okSign: return 0.2
        case .thumbsUp, .thumbsDown: return 0.25
        case .unknown: return 0.35
        }
    }

    /// How long a pointing hand reading as a fist keeps pointing: the finger may have turned toward the camera.
    static let pointThroughFist = 0.5
    /// A swipe: the palm travels at least this many palm lengths in `swipeWindow` seconds, faster than `swipeSpeed` palms a second.
    static let swipeTravel = 1.2
    static let swipeSpeed = 6.0
    static let swipeWindow = 0.2
    /// A tap: the fingertip darts at least `tapSpeed` palms a second, covers `tapTravel` palms or more (but not more than a swipe),
    /// and stops within `tapWindow` seconds.
    static let tapSpeed = 4.0
    static let tapTravel = 0.35
    static let tapWindow = 0.35

    private struct Mark { var time: Double; var palm: CGPoint; var tip: CGPoint }

    private struct Track {
        var stable = HandGesture.Pose.unknown
        var stableFor = 0.0
        var candidate = HandGesture.Pose.unknown
        var candidateFor = 0.0
        var nothingFor = 0.0
        var towardCamera = false
        var pinching = false
        var pinchFor = 0.0
        var history: [Mark] = []
        var swipeArmed = true
        var lastSwipe = -9.0
        /// A fingertip dart in progress: when it began, where from, and its top speed so far.
        var dart: (start: Double, from: CGPoint, peak: Double)?
        var lastSeen = 0.0
    }

    private var tracks: [Int: Track] = [:]
    private(set) var time = 0.0

    mutating func reset() {
        tracks.removeAll()
        time = 0
    }

    /// The pose a hand has held steadily, or `.unknown`.
    func pose(of hand: Int) -> HandGesture.Pose { tracks[hand]?.stable ?? .unknown }

    /// How long the hand has held its current pose.
    func heldFor(_ hand: Int) -> Double { tracks[hand]?.stableFor ?? 0 }

    func isPinching(_ hand: Int) -> Bool { tracks[hand]?.pinching ?? false }

    /// Whether a pointing hand looks to be pointing down the lens.
    func isTowardCamera(_ hand: Int) -> Bool { tracks[hand]?.towardCamera ?? false }

    /// Takes one frame's hands, `dt` seconds after the last, and returns what happened.
    mutating func update(_ hands: [HandState], dt: Double) -> [HandGesture] {
        let dt = min(max(dt, 0), 0.5)
        time += dt
        var events: [HandGesture] = []
        for hand in hands {
            var track = tracks[hand.id] ?? Track()
            track.lastSeen = time
            // A hand the tracker is only guessing at (carried through a gap) keeps whatever it was doing.
            if hand.unseenFor <= 0 {
                readPose(hand, &track, dt: dt, into: &events)
                readPinch(hand, &track, dt: dt, into: &events)
                readMotion(hand, &track, into: &events)
            }
            tracks[hand.id] = track
        }
        // Hands that left end their pose and any pinch, once.
        for (id, track) in tracks where !hands.contains(where: { $0.id == id }) {
            if track.stable != .unknown { events.append(HandGesture(kind: .poseEnded(track.stable), hand: id, point: track.history.last?.palm ?? .zero, time: time)) }
            if track.pinching { events.append(HandGesture(kind: .pinchEnded, hand: id, point: track.history.last?.tip ?? .zero, time: time)) }
            tracks[id] = nil
        }
        return events
    }

    // MARK: Poses

    private func readPose(_ hand: HandState, _ track: inout Track, dt: Double, into events: inout [HandGesture]) {
        let reading = HandGesture.Pose.classify(hand)
        track.stableFor += dt
        if reading == .unknown {
            // Nothing in particular: wait, and only after a while say the hand has no pose.
            track.nothingFor += dt
            if track.nothingFor >= Self.hold(for: .unknown), track.stable != .unknown { change(&track, to: .unknown, hand, into: &events) }
            return
        }
        track.nothingFor = 0
        if reading == track.stable {
            track.candidate = reading
            track.candidateFor = 0
            if reading.isPointing { track.towardCamera = hand.towardCamera > 0.6 }
            return
        }
        if reading != track.candidate {
            track.candidate = reading
            track.candidateFor = 0
        }
        track.candidateFor += dt
        var needed = Self.hold(for: reading)
        if track.stable.isPointing && reading == .fist {
            // Possibly the same finger, now pointing down the lens.
            needed = Self.pointThroughFist
            track.towardCamera = true
        }
        if track.candidateFor + 1e-9 >= needed { change(&track, to: reading, hand, into: &events) }
    }

    private func change(_ track: inout Track, to pose: HandGesture.Pose, _ hand: HandState, into events: inout [HandGesture]) {
        if track.stable != .unknown { events.append(HandGesture(kind: .poseEnded(track.stable), hand: hand.id, point: hand.palm, time: time)) }
        track.stable = pose
        track.stableFor = 0
        track.candidate = pose
        track.candidateFor = 0
        track.towardCamera = pose.isPointing && hand.towardCamera > 0.6
        if pose != .unknown { events.append(HandGesture(kind: .poseStarted(pose), hand: hand.id, point: hand.palm, time: time)) }
    }

    // MARK: Pinch

    private func readPinch(_ hand: HandState, _ track: inout Track, dt: Double, into events: inout [HandGesture]) {
        let closed = hand.pinch < HandGesture.Pose.pinchBelow && hand.reach(of: .index) > 1.1
        let open = hand.pinch > HandGesture.Pose.pinchReleaseAbove
        if !track.pinching {
            track.pinchFor = closed ? track.pinchFor + dt : 0
            if track.pinchFor + 1e-9 >= Self.hold(for: .pinch) {
                track.pinching = true
                track.pinchFor = 0
                events.append(HandGesture(kind: .pinchStarted, hand: hand.id, point: hand.pinchPoint, time: time))
            }
        } else {
            track.pinchFor = open ? track.pinchFor + dt : 0
            if track.pinchFor + 1e-9 >= 0.08 {
                track.pinching = false
                track.pinchFor = 0
                events.append(HandGesture(kind: .pinchEnded, hand: hand.id, point: hand.pinchPoint, time: time))
            }
        }
    }

    // MARK: Swipes and taps

    private func readMotion(_ hand: HandState, _ track: inout Track, into events: inout [HandGesture]) {
        let size = hand.size
        track.history.append(Mark(time: time, palm: hand.palm, tip: hand.indexTip))
        track.history.removeAll { time - $0.time > 0.5 }

        // Swipe: how far the palm went over the last fifth of a second, and how fast it is going over the last few frames.
        if let from = track.history.first(where: { time - $0.time <= Self.swipeWindow + 1e-9 }), from.time < time,
           let recent = track.history.first(where: { time - $0.time <= 0.07 + 1e-9 && $0.time < time }) {
            let move = hand.palm - from.palm
            let travel = hypot(Double(move.dx), Double(move.dy)) / size
            let speed = HandState.distance(recent.palm, hand.palm) / size / max(time - recent.time, 1e-3)
            if track.swipeArmed, time - track.lastSwipe > 0.3, travel >= Self.swipeTravel, speed >= Self.swipeSpeed {
                let direction: HandGesture.Direction = abs(move.dx) >= abs(move.dy) ? (move.dx > 0 ? .right : .left) : (move.dy > 0 ? .up : .down)
                events.append(HandGesture(kind: .swipe(direction, speed: speed * size), hand: hand.id, point: hand.palm, time: time))
                track.swipeArmed = false
                track.lastSwipe = time
                track.dart = nil
            } else if !track.swipeArmed, speed < Self.swipeSpeed * 0.4 {
                track.swipeArmed = true
            }
        }

        // Tap: the fingertip darts and stops.
        guard track.history.count >= 2 else { return }
        let last = track.history[track.history.count - 2]
        let step = HandState.distance(last.tip, hand.indexTip) / size / max(time - last.time, 1e-3)
        if var dart = track.dart {
            dart.peak = max(dart.peak, step)
            let travel = HandState.distance(dart.from, hand.indexTip) / size
            if time - dart.start > Self.tapWindow || travel > Self.swipeTravel * 1.6 {
                track.dart = nil
            } else if step < dart.peak * 0.35 {
                if travel >= Self.tapTravel, time - track.lastSwipe > 0.3 {
                    events.append(HandGesture(kind: .tap, hand: hand.id, point: hand.indexTip, time: time))
                }
                track.dart = nil
            } else {
                track.dart = dart
            }
        } else if step >= Self.tapSpeed {
            track.dart = (start: last.time, from: last.tip, peak: step)
        }
    }
}
