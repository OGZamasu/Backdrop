import CoreGraphics
import CoreVideo
import Foundation
import QuartzCore
import Vision

/// Landmark points for one face, in output pixels. What Vision reports, before any measuring.
struct RawFace {
    var leftEye: [CGPoint]
    var rightEye: [CGPoint]
    var leftBrow: [CGPoint]
    var rightBrow: [CGPoint]
    var outerLips: [CGPoint]
    var innerLips: [CGPoint]
    var rect: CGRect
}

/// A face measured in one frame, before smoothing or calibration.
struct FaceMeasure: Equatable {
    var leftEye: CGPoint
    var rightEye: CGPoint
    var mouth: CGPoint
    var mouthWidth: Double
    var browCenter: CGPoint
    var rect: CGRect
    /// How far apart the inner lips are, in eye-spacings.
    var lipGap: Double
    /// How far the eyebrows sit above the eyes, in eye-spacings.
    var browDistance: Double
}

enum FaceFeatureExtractor {
    static func measure(_ raw: RawFace) -> FaceMeasure? {
        guard let a = mean(raw.leftEye), let b = mean(raw.rightEye),
              let mouth = mean(raw.outerLips), let brows = mean(raw.leftBrow + raw.rightBrow) else { return nil }
        // Vision's left and right depend on which way the subject faces the camera; the picture's left and right don't.
        let (leftEye, rightEye) = a.x <= b.x ? (a, b) : (b, a)
        let io = hypot(rightEye.x - leftEye.x, rightEye.y - leftEye.y)
        guard io > 4 else { return nil }

        let eyes = CGPoint(x: (leftEye.x + rightEye.x) / 2, y: (leftEye.y + rightEye.y) / 2)
        let upLength = max(hypot(eyes.x - mouth.x, eyes.y - mouth.y), 1e-9)
        let up = CGVector(dx: (eyes.x - mouth.x) / upLength, dy: (eyes.y - mouth.y) / upLength)

        func height(_ p: CGPoint) -> Double { (p.x - eyes.x) * up.dx + (p.y - eyes.y) * up.dy }

        let lips = raw.innerLips.map(height)
        let gap = (lips.max() ?? 0) - (lips.min() ?? 0)
        let across = CGVector(dx: up.dy, dy: -up.dx)
        let spread = raw.outerLips.map { ($0.x - mouth.x) * across.dx + ($0.y - mouth.y) * across.dy }
        let mouthWidth = (spread.max() ?? 0) - (spread.min() ?? 0)

        return FaceMeasure(leftEye: leftEye, rightEye: rightEye, mouth: mouth, mouthWidth: mouthWidth, browCenter: brows,
                           rect: raw.rect, lipGap: gap / io, browDistance: height(brows) / io)
    }

    private static func mean(_ points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let n = Double(points.count)
        return CGPoint(x: points.reduce(0) { $0 + $1.x } / n, y: points.reduce(0) { $0 + $1.y } / n)
    }

    /// 0 for lips together, 1 for a wide yawn.
    static func mouthOpen(lipGap: Double) -> Double { clamp((lipGap - 0.05) / 0.45) }

    static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
}

/// Steadies the measurements and learns what this face looks like at rest, so "eyebrows up" means up for this person.
struct FaceSmoother {
    /// How long a face may vanish (a blink of the tracker, a hand across it) before it is reported gone.
    static let holdSeconds = 0.35
    /// How much higher than rest the brows must go for `browRaise` to read 1, in eye-spacings.
    static let browRange = 0.14

    private var state: FaceState?
    private var baseline: Double?
    private var lostFor = 0.0

    mutating func reset() {
        state = nil
        baseline = nil
        lostFor = 0
    }

    mutating func update(_ measure: FaceMeasure?, dt: Double) -> FaceState? {
        guard let m = measure else {
            lostFor += dt
            if lostFor > Self.holdSeconds { reset() }
            return state
        }
        lostFor = 0

        // The resting brow height only creeps up slowly, but drops straight away: a raised brow is never mistaken for rest for long.
        if var b = baseline {
            if m.browDistance < b { b += (m.browDistance - b) * min(1, dt * 6) } else { b += (m.browDistance - b) * min(1, dt * 0.04) }
            baseline = b
        } else {
            baseline = m.browDistance
        }
        let raise = FaceFeatureExtractor.clamp((m.browDistance - (baseline ?? m.browDistance)) / Self.browRange)
        let open = FaceFeatureExtractor.mouthOpen(lipGap: m.lipGap)

        guard let old = state else {
            let fresh = FaceState(leftEye: m.leftEye, rightEye: m.rightEye, mouth: m.mouth, mouthWidth: m.mouthWidth,
                                  browCenter: m.browCenter, rect: m.rect, mouthOpen: open, browRaise: raise, browDistance: m.browDistance)
            state = fresh
            return fresh
        }

        func blend(_ a: Double, _ b: Double, _ tau: Double) -> Double { a + (b - a) * (1 - exp(-dt / tau)) }
        func blend(_ a: CGPoint, _ b: CGPoint, _ tau: Double) -> CGPoint { CGPoint(x: blend(a.x, b.x, tau), y: blend(a.y, b.y, tau)) }
        let place = 0.045
        let smoothed = FaceState(
            leftEye: blend(old.leftEye, m.leftEye, place), rightEye: blend(old.rightEye, m.rightEye, place),
            mouth: blend(old.mouth, m.mouth, place), mouthWidth: blend(old.mouthWidth, m.mouthWidth, 0.1),
            browCenter: blend(old.browCenter, m.browCenter, place),
            rect: CGRect(x: blend(old.rect.minX, m.rect.minX, place), y: blend(old.rect.minY, m.rect.minY, place),
                         width: blend(old.rect.width, m.rect.width, 0.1), height: blend(old.rect.height, m.rect.height, 0.1)),
            mouthOpen: blend(old.mouthOpen, open, 0.05), browRaise: blend(old.browRaise, raise, 0.09),
            browDistance: blend(old.browDistance, m.browDistance, 0.09))
        state = smoothed
        return smoothed
    }
}

/// Runs Vision's face landmarks off to the side, so finding a face never holds up a video frame.
///
/// The pipeline hands it the newest camera frame whenever it is free and reads back whatever was found last, a frame
/// or two old. For eyebrows and an open mouth that delay can't be seen.
final class FaceTrackingService {
    private let queue = DispatchQueue(label: "app.backdrop.faces", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false
    private var lastSubmit = 0.0
    /// At most this often: landmarks are plenty smooth at 20 a second, and it leaves the neural engine to the cutout.
    static let minInterval = 0.05
    private var found: (face: RawFace?, at: CFTimeInterval)?
    // For the log: how often it looks, how often it finds a face, and how long a look takes.
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
            let face = Self.detect(in: buffer, transform: transform)
            let now = CACurrentMediaTime()
            let report = self.lock.withLock { () -> (Int, Int, Double)? in
                self.found = (face, now)
                self.busy = false
                self.looks += 1
                if face != nil { self.hits += 1 }
                self.slowest = max(self.slowest, now - started)
                guard now - self.lastReport >= 5 else { return nil }
                defer { self.looks = 0; self.hits = 0; self.slowest = 0; self.lastReport = now }
                return (self.looks, self.hits, self.slowest)
            }
            if let (looks, hits, slowest) = report {
                Log.lens.notice("face tracking: \(hits, privacy: .public) of \(looks, privacy: .public) looks found a face, slowest took \(Int(slowest * 1000), privacy: .public) ms")
            }
        }
    }

    /// The face from the most recent look, or nil if there wasn't one or it is older than `maxAge`.
    func latest(maxAge: TimeInterval = 0.5) -> RawFace? {
        lock.withLock {
            guard let found, CACurrentMediaTime() - found.at <= maxAge else { return nil }
            return found.face
        }
    }

    func reset() { lock.withLock { found = nil } }

    private static func detect(in buffer: CVPixelBuffer, transform: CGAffineTransform) -> RawFace? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        // Several people in view: follow the biggest, the one closest to the camera.
        guard let face = request.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }),
              let landmarks = face.landmarks else { return nil }

        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            region?.pointsInImage(imageSize: size).map { $0.applying(transform) } ?? []
        }
        return RawFace(leftEye: points(landmarks.leftEye), rightEye: points(landmarks.rightEye),
                       leftBrow: points(landmarks.leftEyebrow), rightBrow: points(landmarks.rightEyebrow),
                       outerLips: points(landmarks.outerLips), innerLips: points(landmarks.innerLips),
                       rect: VNImageRectForNormalizedRect(face.boundingBox, Int(size.width), Int(size.height)).applying(transform))
    }
}
