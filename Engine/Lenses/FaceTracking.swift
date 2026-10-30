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
    /// How far the head is turned and tipped, in radians, when Vision says. Nil is treated as facing the camera.
    var yaw: Double? = nil
    var pitch: Double? = nil
}

/// A face measured in one frame, before smoothing or calibration.
struct FaceMeasure: Equatable {
    var leftEye: CGPoint
    var rightEye: CGPoint
    var mouth: CGPoint
    var mouthWidth: Double
    var browCenter: CGPoint
    var rect: CGRect
    /// How far apart the inner lips are, as a fraction of the distance from the eyes to the mouth. Both are vertical, so turning
    /// the head to one side doesn't change it, as measuring against the eye spacing would.
    var lipGap: Double
    /// How far the eyebrows sit above the eyes, as a fraction of the distance from the eyes to the mouth.
    var browDistance: Double
    /// Eye height over eye width for the more open of the two eyes: smaller as the eyes close. Using the more open one means
    /// a wink doesn't count as a blink.
    var eyeOpenness: Double = 0.3
    /// Mouth width over eye spacing (both horizontal, so a turned head leaves it alone): larger in a smile.
    var mouthWidthRatio: Double = 0.85
    /// Whether the head is facing the camera closely enough to trust eyebrows, eyes and smile.
    var facingCamera = true
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

        /// How open one eye is: its height over its width, along the face's own axes so a tilted head reads the same.
        func openness(_ points: [CGPoint]) -> Double? {
            guard points.count >= 4 else { return nil }
            let widths = points.map { $0.x * across.dx + $0.y * across.dy }, heights = points.map { $0.x * up.dx + $0.y * up.dy }
            let w = (widths.max() ?? 0) - (widths.min() ?? 0), h = (heights.max() ?? 0) - (heights.min() ?? 0)
            return w > 1e-6 ? h / w : nil
        }
        let eyes2 = [openness(raw.leftEye), openness(raw.rightEye)].compactMap { $0 }
        let facing = abs(raw.yaw ?? 0) <= maxYaw && abs(raw.pitch ?? 0) <= maxPitch

        return FaceMeasure(leftEye: leftEye, rightEye: rightEye, mouth: mouth, mouthWidth: mouthWidth, browCenter: brows,
                           rect: raw.rect, lipGap: gap / upLength, browDistance: height(brows) / upLength,
                           eyeOpenness: eyes2.max() ?? 0.3, mouthWidthRatio: mouthWidth / io, facingCamera: facing)
    }

    /// Past these (about 25 and 22 degrees) the face is turned enough that eyebrows, eyes and smiles stop being readable.
    static let maxYaw = 0.44
    static let maxPitch = 0.38

    private static func mean(_ points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let n = Double(points.count)
        return CGPoint(x: points.reduce(0) { $0 + $1.x } / n, y: points.reduce(0) { $0 + $1.y } / n)
    }

    /// 0 for lips together, 1 for a wide yawn.
    static func mouthOpen(lipGap: Double) -> Double { clamp((lipGap - 0.05) / 0.43) }

    static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
}

/// Steadies the measurements and learns what this face looks like at rest, so "eyebrows up" means up for this person.
struct FaceSmoother {
    /// How long a face may vanish (a blink of the tracker, a hand across it) before it is reported gone.
    static let holdSeconds = 0.35
    /// How much higher than rest the brows must go for `browRaise` to read 1, as a fraction of the eyes-to-mouth distance.
    static let browRange = 0.14

    /// How much narrower than wide-open the eyes must get for `blink` to read 1. A squint in a big smile closes them a quarter
    /// or so; a blink closes them most of the way.
    static let blinkRange = 0.7
    /// How much wider than rest the mouth must get for `smile` to read 1, in eye-spacings.
    static let smileRange = 0.14

    private var state: FaceState?
    private var baseline: Double?
    private var eyeBaseline: Double?
    private var mouthBaseline: Double?
    private var lostFor = 0.0

    mutating func reset() {
        state = nil
        baseline = nil
        eyeBaseline = nil
        mouthBaseline = nil
        lostFor = 0
    }

    mutating func update(_ measure: FaceMeasure?, dt: Double) -> FaceState? {
        guard let m = measure else {
            lostFor += dt
            if lostFor > Self.holdSeconds { reset() }
            return state
        }
        lostFor = 0
        let open = FaceFeatureExtractor.mouthOpen(lipGap: m.lipGap)

        // Eyebrows, eyes and smile are only read while the face looks at the camera. Turned or tipped, their measurements
        // change for reasons that have nothing to do with the expression, and the rest levels are left as they were.
        var raise = 0.0, shut = 0.0, grin = 0.0
        if m.facingCamera {
            // Brows: the resting height drops quickly (a raised brow is never mistaken for rest for long) and rises slowly,
            // and only while the brows aren't up, so holding them there doesn't teach it a new rest.
            if var b = baseline {
                let up = (m.browDistance - b) / Self.browRange
                if m.browDistance < b { b += (m.browDistance - b) * min(1, dt * 2) } else if up < 0.25 { b += (m.browDistance - b) * min(1, dt * 0.08) }
                baseline = b
            } else {
                baseline = m.browDistance
            }
            raise = FaceFeatureExtractor.clamp((m.browDistance - (baseline ?? m.browDistance)) / Self.browRange)

            // Eyes: how open they are at their widest lately is "open"; a blink is how far below that they are now.
            if var e = eyeBaseline {
                e += (m.eyeOpenness - e) * min(1, dt * (m.eyeOpenness > e ? 1.5 : 0.1))
                eyeBaseline = e
            } else {
                eyeBaseline = m.eyeOpenness
            }
            let eyeRest = max(eyeBaseline ?? m.eyeOpenness, 1e-6)
            shut = FaceFeatureExtractor.clamp((eyeRest - m.eyeOpenness) / (eyeRest * Self.blinkRange))

            // Mouth: its width when not smiling is "rest", followed over about ten seconds; a smile is wider than that.
            if var w = mouthBaseline {
                let wide = (m.mouthWidthRatio - w) / Self.smileRange
                if wide < 0.25 { w += (m.mouthWidthRatio - w) * min(1, dt * 0.1) }     // a held smile doesn't become the new rest
                mouthBaseline = w
            } else {
                mouthBaseline = m.mouthWidthRatio
            }
            grin = FaceFeatureExtractor.clamp((m.mouthWidthRatio - (mouthBaseline ?? m.mouthWidthRatio)) / Self.smileRange)
        }

        guard let old = state else {
            let fresh = FaceState(leftEye: m.leftEye, rightEye: m.rightEye, mouth: m.mouth, mouthWidth: m.mouthWidth,
                                  browCenter: m.browCenter, rect: m.rect, mouthOpen: open, browRaise: raise, browDistance: m.browDistance,
                                  blink: shut, smile: grin)
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
            browDistance: blend(old.browDistance, m.browDistance, 0.09),
            // A blink is over in a tenth of a second and the tracker looks every 40 ms, so it comes up quickly and lets go slowly.
            // A smile has to last a moment to count, so the "ee" in a word doesn't.
            blink: blend(old.blink, shut, shut > old.blink ? 0.02 : 0.1), smile: blend(old.smile, grin, grin > old.smile ? 0.25 : 0.12))
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
    /// At most this often (25 a second): enough to catch a blink, and it leaves the neural engine to the cutout.
    static let minInterval = 0.04
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
        // Left at "not defined" the request may give the older 65-point set; ask for the 76-point one on purpose.
        if VNDetectFaceLandmarksRequest.revision(request.revision, supportsConstellation: .constellation76Points) { request.constellation = .constellation76Points }
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
                       rect: VNImageRectForNormalizedRect(face.boundingBox, Int(size.width), Int(size.height)).applying(transform),
                       yaw: face.yaw?.doubleValue, pitch: face.pitch?.doubleValue)
    }
}
