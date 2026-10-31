import CoreGraphics
import Foundation
import simd

/// The 21 points Vision finds on a hand.
enum HandJoint: Int, CaseIterable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip

    static let count = 21
}

enum Finger: Int, CaseIterable {
    case thumb, index, middle, ring, little

    /// The four that bend at the knuckle and in the middle.
    static let long: [Finger] = [.index, .middle, .ring, .little]

    var tip: HandJoint {
        switch self {
        case .thumb: return .thumbTip
        case .index: return .indexTip
        case .middle: return .middleTip
        case .ring: return .ringTip
        case .little: return .littleTip
        }
    }

    /// Where the finger joins the palm.
    var knuckle: HandJoint {
        switch self {
        case .thumb: return .thumbMP
        case .index: return .indexMCP
        case .middle: return .middleMCP
        case .ring: return .ringMCP
        case .little: return .littleMCP
        }
    }

    /// The first bend out from the knuckle.
    var middleJoint: HandJoint {
        switch self {
        case .thumb: return .thumbIP
        case .index: return .indexPIP
        case .middle: return .middlePIP
        case .ring: return .ringPIP
        case .little: return .littlePIP
        }
    }
}

/// What a hand looks like it is doing.
enum HandPose: Equatable {
    case unknown
    /// All fingers out, like a "stop" or a high five.
    case openPalm
    /// No fingers out.
    case fist
    /// Index finger out, the rest curled, thumb tucked.
    case point
    /// Index and middle fingers out.
    case peace
    /// Index finger out and thumb up, the rest curled: a finger gun.
    case fingerGun
}

/// One hand in one frame, in output pixels (origin lower left, y up), as Vision reported it and the tracker smoothed it.
///
/// Everything here is measured against the size of the hand itself, so it reads the same near the camera or far from it.
struct HandState: Equatable {
    /// Which hand it is. Vision guesses this afresh on every look and often gets it wrong, so the tracker only says once it has
    /// seen the same answer for a while; until then it is `.unknown`.
    enum Chirality: Equatable {
        case unknown, left, right
    }

    /// Stays the same for as long as the hand is followed, so a game can tell the left hand from the right.
    var id: Int
    /// The 21 joints in `HandJoint` order.
    var joints: [CGPoint]
    /// How the middle of the palm is moving, in pixels a second.
    var velocity: CGVector = .zero
    /// How the tip of the index finger is moving, in pixels a second.
    var tipVelocity: CGVector = .zero
    /// How sure the tracker is that this is a hand, 0...1. Made-up hands are sure.
    var confidence: Double = 1
    /// The person's left or right hand, once the tracker is fairly sure.
    var chirality: Chirality = .unknown
    /// How sure the tracker is of each joint, 0...1 in `HandJoint` order. Empty means sure of every one.
    var jointConfidence: [Double] = []
    /// Seconds since the hand was last actually seen. 0 while it is in view; above 0 the tracker is bridging a short gap (a blur in
    /// a fast swipe) by carrying the hand on along its last motion, so a game may want to dim a cursor or not count a hit.
    var unseenFor: Double = 0
    /// Seconds this hand has been followed.
    var age: Double = 0

    subscript(joint: HandJoint) -> CGPoint { joints[joint.rawValue] }

    /// How sure the tracker is of one joint, 0...1.
    func confidence(of joint: HandJoint) -> Double {
        jointConfidence.indices.contains(joint.rawValue) ? jointConfidence[joint.rawValue] : 1
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(Double(a.x - b.x), Double(a.y - b.y)) }

    var wrist: CGPoint { self[.wrist] }

    /// The middle of the palm: the wrist and the four knuckles averaged.
    var palm: CGPoint {
        let points = [wrist, self[.indexMCP], self[.middleMCP], self[.ringMCP], self[.littleMCP]]
        return CGPoint(x: points.reduce(0) { $0 + $1.x } / 5, y: points.reduce(0) { $0 + $1.y } / 5)
    }

    /// The length of the palm, wrist to the knuckle of the middle finger, in pixels. The yardstick for everything else.
    var size: Double { max(1, Self.distance(wrist, self[.middleMCP])) }

    var rect: CGRect {
        let xs = joints.map(\.x), ys = joints.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return .zero }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    // MARK: Fingers

    /// How far out a finger reaches, as a multiple of the distance from the wrist to its knuckle. About 1.8 straight out;
    /// about 1 curled into a fist.
    func reach(of finger: Finger) -> Double {
        Self.distance(wrist, self[finger.tip]) / max(Self.distance(wrist, self[finger.knuckle]), 1e-6)
    }

    /// 1 when the finger is straight and -1 when it is folded right back on itself.
    func straightness(of finger: Finger) -> Double {
        let a = self[finger.middleJoint] - self[finger.knuckle], b = self[finger.tip] - self[finger.middleJoint]
        let la = max(hypot(a.dx, a.dy), 1e-6), lb = max(hypot(b.dx, b.dy), 1e-6)
        return Double((a.dx * b.dx + a.dy * b.dy) / (la * lb))
    }

    /// How far out the thumb is held, 0 tucked against the hand to 1 sticking out. Measured from the middle of the palm, so a thumb
    /// raised alongside the index finger counts as out and one folded across the palm does not.
    var thumbOpen: Double {
        let d = Self.distance(self[.thumbTip], palm) / size
        return min(1, max(0, (d - 0.5) / 0.3))
    }

    func isExtended(_ finger: Finger) -> Bool {
        if finger == .thumb { return thumbOpen > 0.55 }
        return reach(of: finger) > 1.45 && straightness(of: finger) > 0.3
    }

    /// How many of the four long fingers are held out.
    var fingersUp: Int { Finger.long.filter(isExtended).count }

    var pose: HandPose {
        let index = isExtended(.index), middle = isExtended(.middle), ring = isExtended(.ring), little = isExtended(.little)
        let up = fingersUp
        if up == 4 { return .openPalm }
        if up == 0 { return .fist }
        if index && !middle && !ring && !little { return thumbOpen > 0.55 ? .fingerGun : .point }
        if index && middle && !ring && !little { return .peace }
        return .unknown
    }

    // MARK: Aim

    /// Unit vector along the index finger, from the knuckle to the tip.
    var aim: CGVector {
        let d = self[.indexTip] - self[.indexMCP]
        let l = max(hypot(d.dx, d.dy), 1e-6)
        return CGVector(dx: d.dx / l, dy: d.dy / l)
    }

    /// How long the index finger looks, as a fraction of the palm. About 0.85 held across the picture; near 0 pointing at the camera.
    var aimLength: Double { Self.distance(self[.indexMCP], self[.indexTip]) / size }

    /// Where the index fingertip is.
    var indexTip: CGPoint { self[.indexTip] }

    /// The fingertip that reaches furthest from the wrist: the point of a hand swung like a blade.
    var leadTip: CGPoint {
        Finger.allCases.map { self[$0.tip] }.max { Self.distance($0, wrist) < Self.distance($1, wrist) } ?? wrist
    }

    /// Thumb tip to index tip over the palm: near 0 for a pinch, 1 or more for a spread hand.
    var pinch: Double { Self.distance(self[.thumbTip], self[.indexTip]) / size }
}

// MARK: - More measurements, for the gesture reader

extension HandState {
    /// Unit vector up the hand, from the wrist to the knuckle of the middle finger.
    var axis: CGVector {
        let d = self[.middleMCP] - wrist
        let l = max(hypot(d.dx, d.dy), 1e-6)
        return CGVector(dx: d.dx / l, dy: d.dy / l)
    }

    /// Whether one of the four long fingers is folded into the hand. Not the same as "not extended": a finger half out is neither.
    func isCurled(_ finger: Finger) -> Bool {
        if finger == .thumb { return thumbClearance < 0.85 }
        return reach(of: finger) < 1.3 || straightness(of: finger) < -0.2
    }

    /// How far the thumb tip stands clear of a curled hand: thumb tip to the middle joint of the middle finger (the top of a fist),
    /// over the palm. About 0.5 for a thumb folded over a fist; 1.6 or more for a thumbs up. Measured on Vision's reading of fists and
    /// thumbs up in every skin tone, turned and blurred; the plain `thumbOpen` cannot tell those two apart.
    var thumbClearance: Double { Self.distance(self[.thumbTip], self[.middlePIP]) / size }

    /// Unit vector along the thumb, from its middle knuckle to its tip.
    var thumbDirection: CGVector {
        let d = self[.thumbTip] - self[.thumbMP]
        let l = max(hypot(d.dx, d.dy), 1e-6)
        return CGVector(dx: d.dx / l, dy: d.dy / l)
    }

    /// Halfway between the thumb tip and the index tip: where a pinch holds something.
    var pinchPoint: CGPoint {
        CGPoint(x: (self[.thumbTip].x + self[.indexTip].x) / 2, y: (self[.thumbTip].y + self[.indexTip].y) / 2)
    }

    /// How much the index finger looks shortened because it points toward the camera: 0 seen at full length across the picture, 1
    /// pointed straight down the lens. Seen side on the finger is about 0.85 palms from knuckle to tip; pointed at the camera Vision
    /// reports a third of that or less.
    var towardCamera: Double { min(1, max(0, (0.8 - aimLength) / 0.55)) }

    /// What the hand shows this very frame, with no memory: see `HandGestureRecognizer` for a reading that holds steady.
    var gesturePose: HandGesture.Pose { HandGesture.Pose.classify(self) }
}

extension CGPoint {
    static func - (a: CGPoint, b: CGPoint) -> CGVector { CGVector(dx: a.x - b.x, dy: a.y - b.y) }
}

/// Joints as Vision found them in one look, before any smoothing: 21 points in output pixels.
struct RawHand {
    var joints: [CGPoint]
    /// How sure Vision was of each joint, 0...1, in `HandJoint` order. Empty means sure of every one.
    var confidences: [Double] = []
    /// Vision's guess at which hand this is, for this one look. Often wrong; the tracker takes a vote.
    var chirality: HandState.Chirality = .unknown
    /// How sure the reader is that this is a hand at all, 0...1.
    var confidence: Double = 1
}

/// What the hand tracker found in one look, and when.
struct HandSample {
    var hands: [RawHand]
    var at: CFTimeInterval
}

/// Follows hands from look to look: gives each a steady id, steadies the joints, and works out how fast they move.
///
/// Real cameras are noisy in three ways, and each is handled on its own:
/// - Jitter. Every joint is steadied with a one-euro filter: heavy smoothing while it is nearly still, almost none while it moves
///   fast, so a hand held up does not shimmer and a hand swung like a sword does not lag. Joints are filtered as offsets from the
///   palm, so moving the whole hand never smears the shape of the fingers, and a joint Vision was unsure of follows more slowly.
/// - Dropouts. A fast swipe blurs and Vision misses a look or three. A hand that goes missing carries on along its last motion for
///   a moment, then holds still, and is only reported gone after `holdSeconds`. Each hand is held on its own, so losing one of two
///   hands for a look does not cost it its id.
/// - Identity. New looks are matched to known hands by where each hand was heading, choosing the pairing with the least total
///   travel, with Vision's left/right guess (taken as a running vote) as a tie breaker. A brand new hand Vision is unsure of must be
///   seen twice before it is reported, so a face or a knee mistaken for a hand for one look never appears.
struct HandSmoother {
    /// How long a hand may be missing (a blur in a fast swipe, a finger across the lens) before it is reported gone.
    static let holdSeconds = 0.3
    /// The time constant joints used to follow measurements with, before the one-euro filter took over. Kept for code that reads it.
    static let jointTau = 0.02
    static let velocityTau = 0.05
    /// For the first part of a gap a missing hand drifts on along its last motion, slowing as it goes; after that it holds still.
    static let coastSeconds = 0.12
    /// At most this many hands are reported (Vision looks for two).
    static let maxHands = 2
    /// A new hand that Vision is less sure of than this must be seen in two looks before it is reported.
    static let confirmBelow = 0.5

    /// The one-euro filter (Casiez, Roussel and Vogel, 2012): a low-pass filter whose cut-off rises with speed. Speeds are measured in
    /// palm lengths a second (`scale`), so it behaves the same for a hand near the camera and one across the room.
    struct OneEuro {
        /// Cut-off when still, in hertz. Lower is smoother and laggier.
        var minCutoff: Double
        /// How much the cut-off rises per palm length a second of speed.
        var beta: Double
        /// Cut-off for the speed estimate itself.
        var derivativeCutoff: Double = 4
        private(set) var value: SIMD2<Double>?
        private(set) var speed = SIMD2<Double>(0, 0)

        init(minCutoff: Double, beta: Double, derivativeCutoff: Double = 4) {
            self.minCutoff = minCutoff
            self.beta = beta
            self.derivativeCutoff = derivativeCutoff
        }

        static func alpha(cutoff: Double, dt: Double) -> Double {
            let tau = 1 / (2 * Double.pi * max(cutoff, 1e-3))
            return 1 / (1 + tau / max(dt, 1e-4))
        }

        /// Takes a new measurement `dt` seconds after the last one. `weight` (0...1) slows the filter for a measurement it should trust
        /// less. Returns the steadied value.
        mutating func filter(_ x: SIMD2<Double>, dt: Double, scale: Double = 1, weight: Double = 1) -> SIMD2<Double> {
            guard let previous = value else {
                value = x
                return x
            }
            let raw = (x - previous) / max(dt, 1e-4)
            speed += (raw - speed) * Self.alpha(cutoff: derivativeCutoff, dt: dt)
            let cutoff = minCutoff + beta * (speed.x * speed.x + speed.y * speed.y).squareRoot() / max(scale, 1e-6)
            let a = Self.alpha(cutoff: cutoff, dt: dt) * min(1, max(0, weight))
            let next = previous + (x - previous) * a
            value = next
            return next
        }

        mutating func reset() {
            value = nil
            speed = .zero
        }
    }

    private struct Track {
        var state: HandState
        var palm = OneEuro(minCutoff: 1.0, beta: 2.0)
        var shape = [OneEuro](repeating: OneEuro(minCutoff: 1.0, beta: 1.5, derivativeCutoff: 2), count: HandJoint.count)
        /// Running votes for Vision's left/right guess, fading so an old mistake is forgotten.
        var leftVotes = 0.0, rightVotes = 0.0
        var looks = 0
        var confirmed: Bool
        /// When it was last matched to a look, on the sample clock.
        var measuredAt: CFTimeInterval
    }

    private(set) var hands: [HandState] = []
    private var tracks: [Track] = []
    private var lastSampleAt: CFTimeInterval?
    private var nextID = 1

    mutating func reset() {
        hands = []
        tracks = []
        lastSampleAt = nil
    }

    /// `sample` is the tracker's latest look, or nil if it has none that is recent. A sample seen before changes nothing but time.
    mutating func update(_ sample: HandSample?, dt: Double) -> [HandState] {
        let dt = min(max(dt, 0), 0.5)
        for i in tracks.indices { tracks[i].state.age += dt }

        guard let sample, sample.at != lastSampleAt else {
            // Nothing new was measured. Hands seen in the latest look stay where they are; hands already missing drift and age.
            age(seen: sample != nil, dt: dt)
            return publish()
        }
        let interval = lastSampleAt.map { min(0.3, max(0.01, sample.at - $0)) } ?? 0.04
        lastSampleAt = sample.at

        let incoming = sample.hands.filter { $0.joints.count == HandJoint.count && Self.isPlausible($0) }
        let pairs = assign(incoming, interval: interval)
        var matched = Set<Int>()
        for (detection, track) in pairs.enumerated() {
            let raw = incoming[detection]
            if let t = track {
                matched.insert(t)
                measure(&tracks[t], raw, at: sample.at)
            } else {
                tracks.append(start(raw, at: sample.at))
                matched.insert(tracks.count - 1)
            }
        }
        for i in tracks.indices where !matched.contains(i) { coast(&tracks[i], dt: interval) }
        prune()
        return publish()
    }

    // MARK: Matching

    /// A hand Vision could have mistaken for something else is not worth following: one squashed to a sliver, or with a palm that is
    /// far longer than the fingers allow.
    private static func isPlausible(_ raw: RawHand) -> Bool {
        let probe = HandState(id: 0, joints: raw.joints)
        guard probe.size > 6, probe.joints.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return false }
        // Vision's own readings span at most about 6 palm lengths (a finger pointed down the lens squashes the palm); 9 is nonsense.
        let r = probe.rect
        return max(r.width, r.height) < probe.size * 9
    }

    /// For each incoming hand, the index of the known hand it continues, or nil for a new hand. Every pairing is tried (there are at
    /// most a few hands), and the one with the least total travel wins; a pairing further than a hand could plausibly have moved is
    /// not allowed.
    private func assign(_ incoming: [RawHand], interval: Double) -> [Int?] {
        guard !incoming.isEmpty else { return [] }
        let detections = incoming.prefix(4).map { HandState(id: 0, joints: $0.joints) }
        var cost = [[Double?]](repeating: [Double?](repeating: nil, count: tracks.count), count: detections.count)
        for (d, hand) in detections.enumerated() {
            for (t, track) in tracks.enumerated() {
                let elapsed = min(Self.holdSeconds, interval + track.state.unseenFor)
                let v = track.state.velocity
                let predicted = CGPoint(x: track.state.palm.x + v.dx * elapsed * 0.6, y: track.state.palm.y + v.dy * elapsed * 0.6)
                let travel = HandState.distance(predicted, hand.palm)
                let gate = max(150, hand.size * 2.5) + hypot(Double(v.dx), Double(v.dy)) * elapsed * 0.5
                guard travel <= gate else { continue }
                var c = travel / max(hand.size, 40)
                let guess = incoming[d].chirality
                if guess != .unknown, track.state.chirality != .unknown, guess != track.state.chirality { c += 0.6 }
                cost[d][t] = c
            }
        }
        // Leaving a hand unmatched costs about as much as a two-palm jump.
        let newHand = 2.5
        var best: (total: Double, choice: [Int?])?
        var choice = [Int?](repeating: nil, count: detections.count)
        func search(_ d: Int, used: Set<Int>, total: Double) {
            if let b = best, total >= b.total { return }
            if d == detections.count {
                best = (total, choice)
                return
            }
            for t in tracks.indices where !used.contains(t) {
                guard let c = cost[d][t] else { continue }
                choice[d] = t
                search(d + 1, used: used.union([t]), total: total + c)
            }
            choice[d] = nil
            search(d + 1, used: used, total: total + newHand)
        }
        search(0, used: [], total: 0)
        var result = best?.choice ?? choice
        // More than four hands in one look is not something Vision does; any beyond the first four start fresh.
        while result.count < incoming.count { result.append(nil) }
        return result
    }

    // MARK: Updating a hand

    private mutating func start(_ raw: RawHand, at time: CFTimeInterval) -> Track {
        var state = HandState(id: nextID, joints: raw.joints)
        nextID += 1
        state.confidence = raw.confidence
        state.jointConfidence = raw.confidences
        var track = Track(state: state, confirmed: raw.confidence >= Self.confirmBelow, measuredAt: time)
        vote(&track, raw.chirality)
        track.looks = 1
        let palm = state.palm
        _ = track.palm.filter(SIMD2(Double(palm.x), Double(palm.y)), dt: 0.04, scale: state.size)
        for j in 0..<HandJoint.count {
            _ = track.shape[j].filter(SIMD2(Double(raw.joints[j].x - palm.x), Double(raw.joints[j].y - palm.y)), dt: 0.04, scale: state.size)
        }
        return track
    }

    private func measure(_ track: inout Track, _ raw: RawHand, at time: CFTimeInterval) {
        let measured = HandState(id: 0, joints: raw.joints)
        let since = min(Self.holdSeconds + 0.1, max(0.01, time - track.measuredAt))
        let scale = max(track.state.size * 0.7 + measured.size * 0.3, 8)
        let oldPalm = track.palm.value ?? SIMD2(Double(track.state.palm.x), Double(track.state.palm.y))
        let oldTip = track.state.indexTip

        let mp = measured.palm
        let palm = track.palm.filter(SIMD2(Double(mp.x), Double(mp.y)), dt: since, scale: scale, weight: Self.weight(raw.confidence))
        var joints = track.state.joints
        for j in 0..<HandJoint.count {
            let c = raw.confidences.indices.contains(j) ? raw.confidences[j] : 1
            let offset = SIMD2(Double(raw.joints[j].x - mp.x), Double(raw.joints[j].y - mp.y))
            let o = track.shape[j].filter(offset, dt: since, scale: scale, weight: Self.weight(c))
            joints[j] = CGPoint(x: palm.x + o.x, y: palm.y + o.y)
        }

        var next = track.state
        next.joints = joints
        // Speeds come from the steadied joints, so a still hand reads as still and not as jitter, and they are themselves eased a
        // little so one odd look cannot spike them.
        let k = 1 - exp(-since / Self.velocityTau)
        let palmMove = CGVector(dx: (palm.x - oldPalm.x) / since, dy: (palm.y - oldPalm.y) / since)
        let tipMove = CGVector(dx: (next.indexTip.x - oldTip.x) / since, dy: (next.indexTip.y - oldTip.y) / since)
        if track.state.unseenFor > 0 {
            // Back from a gap: the old speed was a guess, so take the new one as it is.
            next.velocity = palmMove
            next.tipVelocity = tipMove
        } else {
            next.velocity = CGVector(dx: next.velocity.dx + (palmMove.dx - next.velocity.dx) * k, dy: next.velocity.dy + (palmMove.dy - next.velocity.dy) * k)
            next.tipVelocity = CGVector(dx: next.tipVelocity.dx + (tipMove.dx - next.tipVelocity.dx) * k,
                                        dy: next.tipVelocity.dy + (tipMove.dy - next.tipVelocity.dy) * k)
        }
        next.unseenFor = 0
        next.confidence = next.confidence * 0.5 + raw.confidence * 0.5
        next.jointConfidence = raw.confidences
        track.state = next
        track.measuredAt = time
        track.looks += 1
        if track.looks >= 2 { track.confirmed = true }
        vote(&track, raw.chirality)
    }

    /// How much a measurement is trusted, from how sure Vision was of it. Never zero, so even a doubtful joint keeps up eventually.
    private static func weight(_ confidence: Double) -> Double { min(1, max(0.12, (confidence - 0.05) / 0.45)) }

    private func vote(_ track: inout Track, _ guess: HandState.Chirality) {
        track.leftVotes *= 0.9
        track.rightVotes *= 0.9
        switch guess {
        case .left: track.leftVotes += 1
        case .right: track.rightVotes += 1
        case .unknown: break
        }
        let total = track.leftVotes + track.rightVotes
        let current = track.state.chirality
        // Say which hand only on a clear majority, and change your mind only on a clearer one.
        let needed = current == .unknown ? 0.7 : 0.8
        if total >= 1.8, track.leftVotes / total >= needed { track.state.chirality = .left }
        else if total >= 1.8, track.rightVotes / total >= needed { track.state.chirality = .right }
    }

    private mutating func age(seen: Bool, dt: Double) {
        for i in tracks.indices {
            if tracks[i].state.unseenFor > 0 || !seen {
                coast(&tracks[i], dt: dt)
            } else {
                fade(&tracks[i].state, dt: dt)
            }
        }
        prune()
    }

    /// Carries a missing hand on along its last motion, slowing, then holds it.
    private func coast(_ track: inout Track, dt: Double) {
        let before = track.state.unseenFor
        track.state.unseenFor += dt
        let moving = max(0, min(track.state.unseenFor, Self.coastSeconds) - min(before, Self.coastSeconds))
        if moving > 0 {
            let carry = exp(-before / 0.06)
            let shift = CGVector(dx: track.state.velocity.dx * moving * carry, dy: track.state.velocity.dy * moving * carry)
            // Only the picture moves: the filters keep the last real measurement, so when the hand is seen again its speed is
            // worked out over the whole gap.
            track.state.joints = track.state.joints.map { CGPoint(x: $0.x + shift.dx, y: $0.y + shift.dy) }
        }
        fade(&track.state, dt: dt)
        track.state.confidence *= exp(-dt / 0.25)
    }

    /// Between looks nothing is measured, so speeds fade rather than carry on for ever.
    private func fade(_ state: inout HandState, dt: Double) {
        let keep = exp(-dt / 0.12)
        state.velocity = CGVector(dx: state.velocity.dx * keep, dy: state.velocity.dy * keep)
        state.tipVelocity = CGVector(dx: state.tipVelocity.dx * keep, dy: state.tipVelocity.dy * keep)
    }

    private mutating func prune() {
        tracks.removeAll { $0.state.unseenFor > Self.holdSeconds || (!$0.confirmed && $0.state.unseenFor > 0) }
        // Two hands in view and one more coming back: the one missing longest makes way.
        while tracks.filter(\.confirmed).count > Self.maxHands {
            guard let gone = tracks.indices.filter({ tracks[$0].confirmed && tracks[$0].state.unseenFor > 0 })
                .max(by: { tracks[$0].state.unseenFor < tracks[$1].state.unseenFor }) else { break }
            tracks.remove(at: gone)
        }
    }

    private mutating func publish() -> [HandState] {
        hands = tracks.filter(\.confirmed).map(\.state).sorted { $0.id < $1.id }
        return hands
    }
}

// MARK: - Geometry for hand games

/// Small pieces of geometry that the hand games share: a swung blade against a circle, a pointed finger against a target.
enum HandGeometry {
    /// How close the segment from `a` to `b` passes to `p`.
    static func distance(from p: SIMD2<Double>, toSegmentFrom a: SIMD2<Double>, to b: SIMD2<Double>) -> Double {
        let ab = b - a
        let lengthSquared = simd_dot(ab, ab)
        guard lengthSquared > 1e-9 else { return simd_distance(p, a) }
        let t = min(1, max(0, simd_dot(p - a, ab) / lengthSquared))
        return simd_distance(p, a + ab * t)
    }

    /// Whether a blade that moved from `a` to `b` cut through a circle.
    static func segment(from a: SIMD2<Double>, to b: SIMD2<Double>, hits center: SIMD2<Double>, radius: Double) -> Bool {
        distance(from: center, toSegmentFrom: a, to: b) <= radius
    }

    /// How far along a ray from `origin` going `direction` (a unit vector) a circle is hit, or nil for a miss. `slack` widens the circle by
    /// a fraction of the distance, so aiming from a distance is forgiving.
    static func ray(from origin: SIMD2<Double>, direction: SIMD2<Double>, hits center: SIMD2<Double>, radius: Double,
                    slack: Double = 0, maxDistance: Double = .infinity) -> Double? {
        let along = simd_dot(center - origin, direction)
        guard along > 0, along <= maxDistance else { return nil }
        let off = simd_length(center - origin - direction * along)
        return off <= radius + along * slack ? along : nil
    }

    /// Where a ray from inside `rect` leaves it.
    static func exit(from origin: SIMD2<Double>, direction: SIMD2<Double>, rect: CGRect) -> SIMD2<Double> {
        var t = Double.infinity
        if direction.x > 1e-9 { t = min(t, (rect.maxX - origin.x) / direction.x) } else if direction.x < -1e-9 { t = min(t, (rect.minX - origin.x) / direction.x) }
        if direction.y > 1e-9 { t = min(t, (rect.maxY - origin.y) / direction.y) } else if direction.y < -1e-9 { t = min(t, (rect.minY - origin.y) / direction.y) }
        t = max(0, t.isFinite ? t : 0)
        return origin + direction * t
    }
}
