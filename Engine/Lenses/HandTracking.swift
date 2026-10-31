import CoreGraphics
import CoreVideo
import Foundation
import QuartzCore
import Vision

/// Runs Vision's hand pose off to the side, so finding hands never holds up a video frame.
///
/// The pipeline hands it the newest camera frame whenever it is free and reads back whatever was found last, a frame or two old.
final class HandTrackingService {
    private let queue = DispatchQueue(label: "app.backdrop.hands", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false
    private var lastSubmit = 0.0
    /// At most this often (30 a second). A swung hand moves a long way between looks, which the games allow for.
    static let minInterval = 0.033
    private var found: HandSample?
    // For the log: how often it looks, how often it finds a hand, and how long a look takes.
    private var looks = 0, hits = 0, slowest = 0.0, lastReport = CACurrentMediaTime()

    /// Starts looking at `buffer` unless the last look is still going. `transform` takes camera pixels to output pixels.
    func submit(_ buffer: CVPixelBuffer, transform: CGAffineTransform) {
        let go = lock.withLock { () -> Bool in
            let now = CACurrentMediaTime()
            if busy || now - lastSubmit < Self.minInterval { return false }
            busy = true
            lastSubmit = now
            return true
        }
        guard go else { return }
        queue.async {
            let started = CACurrentMediaTime()
            let hands = Self.detect(in: VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:]),
                                    size: CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)), transform: transform)
            let now = CACurrentMediaTime()
            let report = self.lock.withLock { () -> (Int, Int, Double)? in
                self.found = HandSample(hands: hands, at: now)
                self.busy = false
                self.looks += 1
                if !hands.isEmpty { self.hits += 1 }
                self.slowest = max(self.slowest, now - started)
                guard now - self.lastReport >= 5 else { return nil }
                defer { self.looks = 0; self.hits = 0; self.slowest = 0; self.lastReport = now }
                return (self.looks, self.hits, self.slowest)
            }
            if let (looks, hits, slowest) = report {
                Log.lens.notice("hand tracking: \(hits, privacy: .public) of \(looks, privacy: .public) looks found a hand, slowest took \(Int(slowest * 1000), privacy: .public) ms")
            }
        }
    }

    /// The most recent look, or nil if there hasn't been one or it is older than `maxAge`.
    func latest(maxAge: TimeInterval = 0.4) -> HandSample? {
        lock.withLock {
            guard let found, CACurrentMediaTime() - found.at <= maxAge else { return nil }
            return found
        }
    }

    func reset() { lock.withLock { found = nil } }

    /// Finds up to two hands. Points come back in output pixels (`transform` applied), the way every other lens signal does.
    static func detect(in handler: VNImageRequestHandler, size: CGSize, transform: CGAffineTransform) -> [RawHand] {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        do { try handler.perform([request]) } catch { return [] }
        return (request.results ?? []).compactMap { hand(from: $0, size: size, transform: transform) }
    }

    /// For tests and previews: a hand pose from a still picture.
    static func detect(in image: CGImage, transform: CGAffineTransform = .identity) -> [RawHand] {
        detect(in: VNImageRequestHandler(cgImage: image, options: [:]), size: CGSize(width: image.width, height: image.height), transform: transform)
    }

    private static let joints: [(HandJoint, VNHumanHandPoseObservation.JointName)] = [
        (.wrist, .wrist),
        (.thumbCMC, .thumbCMC), (.thumbMP, .thumbMP), (.thumbIP, .thumbIP), (.thumbTip, .thumbTip),
        (.indexMCP, .indexMCP), (.indexPIP, .indexPIP), (.indexDIP, .indexDIP), (.indexTip, .indexTip),
        (.middleMCP, .middleMCP), (.middlePIP, .middlePIP), (.middleDIP, .middleDIP), (.middleTip, .middleTip),
        (.ringMCP, .ringMCP), (.ringPIP, .ringPIP), (.ringDIP, .ringDIP), (.ringTip, .ringTip),
        (.littleMCP, .littleMCP), (.littlePIP, .littlePIP), (.littleDIP, .littleDIP), (.littleTip, .littleTip),
    ]

    /// A hand worth following: the wrist and the knuckles that give its size and direction were seen, and most of the rest too.
    ///
    /// Vision often has little confidence in a fingertip that is curled out of sight or blurred by a fast swipe, so one weak joint
    /// does not throw the whole hand away: it is kept with its confidence, which tells the tracker to trust it less, and a joint
    /// Vision did not place at all is filled in by carrying its finger on straight. Measured on Vision's reading of about 2,000
    /// pictures of hands, this keeps one hand in twenty more of the blurred ones, which are exactly the hands in a fast swipe.
    static func hand(from observation: VNHumanHandPoseObservation, size: CGSize, transform: CGAffineTransform) -> RawHand? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }
        var placed = [CGPoint](repeating: .zero, count: HandJoint.count)
        var confidences = [Double](repeating: 0, count: HandJoint.count)
        for (joint, name) in joints {
            guard let p = points[name], p.confidence >= Self.seenAbove else { continue }
            confidences[joint.rawValue] = Double(p.confidence)
            placed[joint.rawValue] = CGPoint(x: p.location.x * size.width, y: p.location.y * size.height).applying(transform)
        }
        let chirality: HandState.Chirality
        switch observation.chirality {
        case .left: chirality = .left
        case .right: chirality = .right
        default: chirality = .unknown
        }
        return reading(placed, confidences: confidences, chirality: chirality)
    }

    /// Below this Vision has not really placed a joint; its position is not worth reading.
    static let seenAbove: Float = 0.05

    /// Checks one look at a hand and fills in what Vision missed. `confidences` are 0 for joints it did not place. Nil if the hand
    /// cannot be trusted at all.
    static func reading(_ joints: [CGPoint], confidences: [Double], chirality: HandState.Chirality = .unknown) -> RawHand? {
        guard joints.count == HandJoint.count, confidences.count == HandJoint.count else { return nil }
        let core: [HandJoint] = [.wrist, .middleMCP]
        guard core.allSatisfy({ confidences[$0.rawValue] >= 0.15 }) else { return nil }
        let knuckles: [HandJoint] = [.indexMCP, .ringMCP, .littleMCP]
        guard knuckles.filter({ confidences[$0.rawValue] >= 0.15 }).count >= 2 else { return nil }
        let mean = confidences.reduce(0, +) / Double(confidences.count)
        guard mean >= 0.3 else { return nil }

        var filled = joints
        var known = confidences.map { $0 > 0 }
        // A missing knuckle sits next to its neighbours, as far again as they are from each other.
        let row: [HandJoint] = [.indexMCP, .middleMCP, .ringMCP, .littleMCP]
        for (i, joint) in row.enumerated() where !known[joint.rawValue] {
            let near = i == 0 ? (row[1], row[2]) : i == 3 ? (row[2], row[1]) : (row[i - 1], row[i + 1])
            let a = filled[near.0.rawValue], b = filled[near.1.rawValue]
            filled[joint.rawValue] = i == 0 || i == 3 ? CGPoint(x: a.x * 2 - b.x, y: a.y * 2 - b.y) : CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            known[joint.rawValue] = known[near.0.rawValue] && known[near.1.rawValue]
            if !known[joint.rawValue] { return nil }
        }
        // Missing joints further out carry their finger on straight, or start up the hand from the knuckle.
        let palm = HandState(id: 0, joints: filled)
        let up = palm.axis
        let chains: [[HandJoint]] = [[.thumbCMC, .thumbMP, .thumbIP, .thumbTip], [.indexMCP, .indexPIP, .indexDIP, .indexTip],
                                     [.middleMCP, .middlePIP, .middleDIP, .middleTip], [.ringMCP, .ringPIP, .ringDIP, .ringTip],
                                     [.littleMCP, .littlePIP, .littleDIP, .littleTip]]
        for chain in chains {
            for (k, joint) in chain.enumerated() where !known[joint.rawValue] {
                let previous = k == 0 ? filled[HandJoint.wrist.rawValue] : filled[chain[k - 1].rawValue]
                var step = CGVector(dx: up.dx * palm.size * 0.3, dy: up.dy * palm.size * 0.3)
                if k >= 2 {
                    let before = filled[chain[k - 2].rawValue]
                    step = CGVector(dx: (previous.x - before.x) * 0.8, dy: (previous.y - before.y) * 0.8)
                }
                filled[joint.rawValue] = CGPoint(x: previous.x + step.dx, y: previous.y + step.dy)
                known[joint.rawValue] = true
            }
        }
        let hand = HandState(id: 0, joints: filled)
        guard hand.size > 8 else { return nil }
        return RawHand(joints: filled, confidences: confidences, chirality: chirality, confidence: min(1, mean * 1.25))
    }
}
