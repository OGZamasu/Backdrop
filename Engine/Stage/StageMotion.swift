import CoreGraphics
import Foundation

/// How things move in Present: springs, glides and the gentle magnet of the guides. Nothing here ever jumps; every change of place
/// goes through a spring, so a preset, a slider, a mouse drag and a pinch all move things the same physical way.
enum StageMotion {
    /// A damped spring, worked out exactly for any step (no matter how long a frame took), so it never blows up after a stall.
    /// `omega` is its natural frequency in radians a second (higher is snappier); `zeta` is its damping (1 settles with no
    /// overshoot, below 1 overshoots a little and settles, which reads as soft and physical).
    struct Spring {
        var omega: Double
        var zeta: Double

        /// Something the hand is holding: follows closely, never overshoots.
        static let follow = Spring(omega: 32, zeta: 1)
        /// Letting go: a soft settle with a whisper of overshoot.
        static let settle = Spring(omega: 10.5, zeta: 0.8)
        /// Presets and maximise: a smooth zoom.
        static let zoom = Spring(omega: 9, zeta: 0.92)
        /// Back from past an edge.
        static let rubber = Spring(omega: 14, zeta: 1)

        /// Moves `x` (with velocity `v`) toward `target` over `dt` seconds.
        func step(_ x: inout Double, _ v: inout Double, toward target: Double, dt: Double) {
            let dt = max(0, min(dt, 0.25))
            guard dt > 0 else { return }
            let w = omega, z = zeta
            let x0 = x - target, v0 = v
            if z >= 1 - 1e-6 {
                // Critically damped (over-damping is never used, so treat anything at 1 as exactly critical).
                let e = exp(-w * dt)
                let c = v0 + w * x0
                x = target + (x0 + c * dt) * e
                v = (c - w * (x0 + c * dt)) * e
            } else {
                let wd = w * sqrt(1 - z * z)
                let e = exp(-z * w * dt)
                let a = x0, b = (v0 + z * w * x0) / wd
                let cosT = cos(wd * dt), sinT = sin(wd * dt)
                x = target + e * (a * cosT + b * sinT)
                v = e * ((b * wd - z * w * a) * cosT - (a * wd + z * w * b) * sinT)
            }
            if abs(x - target) < 1e-5, abs(v) < 1e-4 { x = target; v = 0 }
        }

        func step(_ p: inout CGPoint, _ v: inout CGVector, toward target: CGPoint, dt: Double) {
            var x = Double(p.x), y = Double(p.y), vx = Double(v.dx), vy = Double(v.dy)
            step(&x, &vx, toward: Double(target.x), dt: dt)
            step(&y, &vy, toward: Double(target.y), dt: dt)
            p = CGPoint(x: x, y: y)
            v = CGVector(dx: vx, dy: vy)
        }
    }

    /// How long a thrown thing keeps going: a glide covers its speed times this.
    static let glideTime = 0.22
    /// The fastest a thrown thing may leave the hand, in pixels a second. Faster than this is a flick of the wrist, not a throw.
    static let maxThrow = 2600.0

    /// Where something thrown at `velocity` would come to rest.
    static func projected(_ p: CGPoint, velocity v: CGVector) -> CGPoint {
        CGPoint(x: Double(p.x) + Double(v.dx) * glideTime, y: Double(p.y) + Double(v.dy) * glideTime)
    }

    static func capped(_ v: CGVector, at limit: Double = maxThrow) -> CGVector {
        let speed = hypot(Double(v.dx), Double(v.dy))
        guard speed > limit else { return v }
        return CGVector(dx: Double(v.dx) * limit / speed, dy: Double(v.dy) * limit / speed)
    }

    /// The resistance of pulling past an edge: the further you pull, the less it gives, never more than `limit` pixels.
    static func rubberBand(_ overshoot: Double, limit: Double = 90) -> Double {
        guard overshoot != 0 else { return 0 }
        let sign: Double = overshoot < 0 ? -1 : 1
        let x = abs(overshoot)
        return sign * (1 - 1 / (x * 0.55 / limit + 1)) * limit
    }

    /// Keeps an item of half size `half` (pixels) whose centre is `c` inside `area`, pulled back with resistance when past it.
    static func rubberBanded(_ c: CGPoint, half: CGSize, area: CGRect) -> CGPoint {
        let allowed = allowedCentres(half: half, area: area)
        func band(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
            if v < lo { return lo + rubberBand(v - lo) }
            if v > hi { return hi + rubberBand(v - hi) }
            return v
        }
        return CGPoint(x: band(Double(c.x), Double(allowed.minX), Double(allowed.maxX)),
                       y: band(Double(c.y), Double(allowed.minY), Double(allowed.maxY)))
    }

    /// Where an item's centre may rest so the whole item stays inside `area`. An item bigger than the area is centred on it.
    static func allowedCentres(half: CGSize, area: CGRect) -> CGRect {
        var x0 = area.minX + half.width, x1 = area.maxX - half.width
        var y0 = area.minY + half.height, y1 = area.maxY - half.height
        if x0 > x1 { x0 = area.midX; x1 = area.midX }
        if y0 > y1 { y0 = area.midY; y1 = area.midY }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    static func clampCentre(_ c: CGPoint, half: CGSize, area: CGRect) -> CGPoint {
        let a = allowedCentres(half: half, area: area)
        return CGPoint(x: min(a.maxX, max(a.minX, c.x)), y: min(a.maxY, max(a.minY, c.y)))
    }
}

// MARK: - Snapping

/// A line something can settle onto.
struct StageGuide: Equatable {
    enum Kind: Equatable {
        case centre, third, margin
    }

    /// A vertical line at x = `position`, or a horizontal one at y = `position`, in pixels.
    var vertical: Bool
    var position: Double
    var kind: Kind
}

/// The magnet of the centre lines, thirds and margins.
enum StageSnap {
    /// How close (pixels) a resting place must be to a guide for it to pull.
    static let reach = 38.0

    struct Result: Equatable {
        var center: CGPoint
        var guides: [StageGuide]
    }

    /// The guides a thing of half size `half` could settle onto, with the centre each would give it. Each is a centre line, a
    /// third, or an edge lying on the safe margin. `flushBottom` lets the bottom edge sit right on the picture's edge, which is
    /// where a cutout of you belongs.
    static func candidates(half: CGSize, picture: CGSize = StageGeometry.picture, margin: CGFloat = StageGeometry.safeMargin,
                           flushBottom: Bool = false) -> (x: [(Double, StageGuide)], y: [(Double, StageGuide)]) {
        let w = Double(picture.width), h = Double(picture.height), m = Double(margin)
        let hw = Double(half.width), hh = Double(half.height)
        var xs: [(Double, StageGuide)] = [
            (w / 2, StageGuide(vertical: true, position: w / 2, kind: .centre)),
            (w / 3, StageGuide(vertical: true, position: w / 3, kind: .third)),
            (w * 2 / 3, StageGuide(vertical: true, position: w * 2 / 3, kind: .third)),
        ]
        if hw * 2 < w - m * 2 {
            xs.append((m + hw, StageGuide(vertical: true, position: m, kind: .margin)))
            xs.append((w - m - hw, StageGuide(vertical: true, position: w - m, kind: .margin)))
        }
        var ys: [(Double, StageGuide)] = [
            (h / 2, StageGuide(vertical: false, position: h / 2, kind: .centre)),
            (h / 3, StageGuide(vertical: false, position: h / 3, kind: .third)),
            (h * 2 / 3, StageGuide(vertical: false, position: h * 2 / 3, kind: .third)),
        ]
        if hh * 2 < h - m * 2 {
            let bottom = flushBottom ? 0 : m
            ys.append((bottom + hh, StageGuide(vertical: false, position: bottom, kind: .margin)))
            ys.append((h - m - hh, StageGuide(vertical: false, position: h - m, kind: .margin)))
        }
        return (xs, ys)
    }

    /// Where something heading for `rest` settles: onto the nearest guide each way that is within reach, or where it was going.
    static func snap(_ rest: CGPoint, half: CGSize, picture: CGSize = StageGeometry.picture, flushBottom: Bool = false,
                     reach: Double = reach) -> Result {
        let options = candidates(half: half, picture: picture, flushBottom: flushBottom)
        var center = rest
        var guides: [StageGuide] = []
        if let best = options.x.min(by: { abs($0.0 - Double(rest.x)) < abs($1.0 - Double(rest.x)) }), abs(best.0 - Double(rest.x)) <= reach {
            center.x = CGFloat(best.0)
            guides.append(best.1)
        }
        if let best = options.y.min(by: { abs($0.0 - Double(rest.y)) < abs($1.0 - Double(rest.y)) }), abs(best.0 - Double(rest.y)) <= reach {
            center.y = CGFloat(best.0)
            guides.append(best.1)
        }
        return Result(center: center, guides: guides)
    }
}

// MARK: - One moving thing

/// The motion of one item: where it is, how fast it is going, and what it is doing about it.
///
/// It is held (following a hand or the mouse closely), springing toward a place (let go, a preset, maximise), or at rest.
struct StageItemMotion {
    enum Mode: Equatable {
        case rest
        case held
        case springing
    }

    /// Centre in pixels and size in the item's own units (see `StageFrame.size`).
    var center: CGPoint
    var size: Double
    var velocity = CGVector.zero
    var sizeVelocity = 0.0
    private(set) var mode = Mode.rest
    /// Where it is springing to, when springing.
    private(set) var target: CGPoint
    private(set) var targetSize: Double
    private var spring = StageMotion.Spring.settle
    /// Where the hand or mouse wants it while held.
    private var heldTarget: CGPoint
    private var heldSize: Double

    init(center: CGPoint, size: Double) {
        self.center = center
        self.size = size
        target = center
        targetSize = size
        heldTarget = center
        heldSize = size
    }

    var isMoving: Bool { mode != .rest }

    /// Puts it somewhere at once, at rest. Used when a slider sets a place and nothing is moving.
    mutating func place(_ c: CGPoint, size s: Double) {
        center = c
        size = s
        velocity = .zero
        sizeVelocity = 0
        target = c
        targetSize = s
        mode = .rest
    }

    mutating func hold() {
        mode = .held
        heldTarget = center
        heldSize = size
    }

    /// While held: where the hand would put it.
    mutating func follow(_ c: CGPoint, size s: Double) {
        heldTarget = c
        heldSize = s
    }

    /// Sends it springing toward a place, keeping the speed it has.
    mutating func spring(to c: CGPoint, size s: Double, with spring: StageMotion.Spring = .settle) {
        target = c
        targetSize = s
        self.spring = spring
        mode = .springing
    }

    /// Advances by `dt` seconds. Returns true while it is still moving.
    @discardableResult
    mutating func step(dt: Double) -> Bool {
        switch mode {
        case .rest:
            return false
        case .held:
            StageMotion.Spring.follow.step(&center, &velocity, toward: heldTarget, dt: dt)
            StageMotion.Spring.follow.step(&size, &sizeVelocity, toward: heldSize, dt: dt)
            return true
        case .springing:
            spring.step(&center, &velocity, toward: target, dt: dt)
            spring.step(&size, &sizeVelocity, toward: targetSize, dt: dt)
            let still = HandState.distance(center, target) < 0.15 && hypot(Double(velocity.dx), Double(velocity.dy)) < 4
                && abs(size - targetSize) < 1e-4 && abs(sizeVelocity) < 1e-3
            if still {
                center = target
                size = targetSize
                velocity = .zero
                sizeVelocity = 0
                mode = .rest
                return false
            }
            return true
        }
    }
}
