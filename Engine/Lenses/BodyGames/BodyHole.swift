import CoreGraphics
import Foundation

/// Where a person is, taken in one glance: the box around them, how wide their head is, and where their shoulders start.
/// The head is the yardstick, so holes scale with how close you sit to the camera.
struct BodyFrame: Equatable {
    var left: Double
    var right: Double
    var top: Double
    var bottom: Double
    var headWidth: Double
    /// Height of the line where the shoulders begin.
    var shoulderY: Double

    var width: Double { right - left }
    var centerX: Double { (left + right) / 2 }
    var unit: Double { headWidth }

    init(left: Double, right: Double, top: Double, bottom: Double, headWidth: Double, shoulderY: Double) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
        self.headWidth = headWidth
        self.shoulderY = shoulderY
    }

    /// Nil when nobody is in the scan.
    init?(scan: BodyScan) {
        guard scan.present, let box = scan.box else { return nil }
        left = box.minX
        right = box.maxX
        top = box.maxY
        bottom = box.minY

        // The head is the widest the person gets near the top; the shoulders start where they first become much wider.
        let headRows = Int(bodyClamp(box.height * 0.22, 90, 150) / scan.step)
        var head = 0.0
        for gy in max(scan.bottomRow, scan.topRow - headRows)...scan.topRow { head = max(head, scan.rowWidth(gy)) }
        head = max(head, 60)
        headWidth = head
        var shoulders = top - 1.5 * head
        var gy = scan.topRow - 3
        while gy >= scan.bottomRow {
            if scan.rowWidth(gy) >= 1.45 * head {
                shoulders = (Double(gy) + 0.5) * scan.step
                break
            }
            gy -= 1
        }
        shoulderY = bodyClamp(shoulders, top - 2.2 * head, top - 1.0 * head)
    }

    /// Moves part of the way to another reading, so one noisy frame doesn't set the size of a wall.
    func blended(toward other: BodyFrame, by t: Double) -> BodyFrame {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return BodyFrame(left: mix(left, other.left), right: mix(right, other.right), top: mix(top, other.top),
                         bottom: mix(bottom, other.bottom), headWidth: mix(headWidth, other.headWidth), shoulderY: mix(shoulderY, other.shoulderY))
    }

    /// Rectangles standing in for this person standing normally: chest and shoulders, a neck, a head.
    var neutralRects: [CGRect] {
        let u = unit
        return [CGRect(x: left, y: bottom, width: width, height: max(1, shoulderY - bottom)),
                CGRect(x: centerX - 0.3 * u, y: shoulderY, width: 0.6 * u, height: max(1, top - 1.3 * u - shoulderY)),
                CGRect(x: centerX - 0.5 * u, y: top - 1.3 * u, width: u, height: 1.3 * u)]
    }
}

/// The opening in a wall, in the shape of a pose, sized from the person who has to fit through it.
struct BodyHole {
    enum Template: CaseIterable, Hashable {
        case left, right, middle, armsUp, armsOut, crouch

        /// What the label on screen says.
        var label: String {
            switch self {
            case .left: return "←  LEFT!"
            case .right: return "RIGHT!  →"
            case .middle: return "CENTER!"
            case .armsUp: return "ARMS UP!"
            case .armsOut: return "ARMS OUT!"
            case .crouch: return "CROUCH!"
            }
        }
    }

    enum Part {
        case rect(CGRect, corner: Double)
        /// A convex four-sided shape.
        case quad([CGPoint])

        var path: CGPath {
            switch self {
            case .rect(let rect, let corner):
                let radius = min(corner, rect.width / 2, rect.height / 2)
                return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            case .quad(let points):
                let path = CGMutablePath()
                path.addLines(between: points)
                path.closeSubpath()
                return path
            }
        }

        func contains(_ p: CGPoint) -> Bool {
            switch self {
            case .rect(let rect, let corner):
                guard rect.contains(p) else { return false }
                let radius = min(corner, rect.width / 2, rect.height / 2)
                let dx = min(p.x - rect.minX, rect.maxX - p.x), dy = min(p.y - rect.minY, rect.maxY - p.y)
                guard dx < radius, dy < radius else { return true }
                let middle = CGPoint(x: p.x < rect.midX ? rect.minX + radius : rect.maxX - radius,
                                     y: p.y < rect.midY ? rect.minY + radius : rect.maxY - radius)
                return hypot(p.x - middle.x, p.y - middle.y) <= radius
            case .quad(let points):
                var sign = 0.0
                for i in points.indices {
                    let a = points[i], b = points[(i + 1) % points.count]
                    let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
                    if cross == 0 { continue }
                    if sign == 0 { sign = cross } else if sign * cross < 0 { return false }
                }
                return true
            }
        }
    }

    /// How a body measured up against a hole.
    struct Verdict: Equatable {
        /// How much of the silhouette is inside the hole and how much is over the solid wall (in samples).
        var inside = 0.0
        var outside = 0.0
        /// How much of each must-fill zone the body covers, 0...1.
        var zoneFill: [Double] = []
        /// How much of each must-stay-clear area the body covers, 0...1.
        var keepOutFill: [Double] = []

        var hasBody: Bool { inside + outside >= 20 }
        var outsideFraction: Double { inside + outside > 0 ? outside / (inside + outside) : 1 }
        /// 0...1, how much of you fits.
        var fit: Double { 1 - outsideFraction }
        var passed: Bool {
            hasBody && outsideFraction <= BodyHole.allowedOutside && zoneFill.allSatisfy { $0 >= BodyHole.requiredFill }
                && keepOutFill.allSatisfy { $0 <= BodyHole.allowedKeepOut }
        }
        var perfect: Bool { passed && outsideFraction <= 0.03 }

        /// 0...1, how close this is to passing, for the meter: what is left over the wall, arms short of where they should be,
        /// and a head still too high all count against it. Never above the pass mark unless it passes.
        var match: Double {
            let tooHigh = max(0, (keepOutFill.max() ?? 0) - BodyHole.allowedKeepOut) * 1.5
            let armsShort = zoneFill.map { max(0, BodyHole.requiredFill - $0) / BodyHole.requiredFill }.max() ?? 0
            let value = bodyClamp(fit - tooHigh - 0.5 * armsShort, 0, 1)
            return passed ? value : min(value, 1 - BodyHole.allowedOutside - 0.01)
        }

        /// A word or two on what is missing, when most of the body fits but it still does not pass.
        var advice: String? {
            guard hasBody, !passed else { return nil }
            // The head sticks up through a low wall: you are in the right place, just not low enough.
            if outsideFraction <= 0.5, keepOutFill.contains(where: { $0 > BodyHole.allowedKeepOut }) { return "LOWER!" }
            if outsideFraction <= BodyHole.allowedOutside * 1.5, zoneFill.contains(where: { $0 < BodyHole.requiredFill }) { return "MORE ARMS!" }
            return nil
        }
    }

    /// How much of you may be left over the wall and still count as through. Forgiving on purpose.
    static let allowedOutside = 0.12
    /// How much of a zone that asks for an arm has to be covered.
    static let requiredFill = 0.12
    /// How much of a keep-out area may be covered. A wall that asks you to duck is about where your head is, not how much of you
    /// is left over it, since the body below the head makes up most of the silhouette.
    static let allowedKeepOut = 0.10

    let template: Template
    let parts: [Part]
    /// Areas the body has to reach into, so standing still cannot pass a wall that asks for raised or outstretched arms.
    let zones: [CGRect]
    /// Areas the body has to stay out of, so a low wall cannot be passed by barely bending.
    let keepOut: [CGRect]

    func contains(_ p: CGPoint) -> Bool { parts.contains { $0.contains(p) } }

    func judge(_ scan: BodyScan) -> Verdict {
        var verdict = Verdict()
        var zoneSum = [Double](repeating: 0, count: zones.count), zoneCount = [Double](repeating: 0, count: zones.count)
        var keepSum = [Double](repeating: 0, count: keepOut.count), keepCount = [Double](repeating: 0, count: keepOut.count)
        for gy in 0..<scan.rows {
            for gx in 0..<scan.columns {
                let w = scan.weight(gx, gy), p = scan.center(gx, gy)
                if w > 0.02 {
                    if contains(p) { verdict.inside += w } else { verdict.outside += w }
                }
                for (k, zone) in zones.enumerated() where zone.contains(p) {
                    zoneCount[k] += 1
                    zoneSum[k] += w
                }
                for (k, area) in keepOut.enumerated() where area.contains(p) {
                    keepCount[k] += 1
                    keepSum[k] += w
                }
            }
        }
        verdict.zoneFill = zip(zoneSum, zoneCount).map { $1 > 0 ? $0 / $1 : 1 }
        verdict.keepOutFill = zip(keepSum, keepCount).map { $1 > 0 ? $0 / $1 : 0 }
        return verdict
    }

    // MARK: Making holes

    /// A hole for `template` that this person can fit through but could not by standing still. Nil when this person, as
    /// measured, cannot be asked for that pose: too wide to step aside, too small to crouch, no room for arms.
    ///
    /// `tight` (0...1) takes away the slack as the game goes on.
    static func make(_ template: Template, around ref: BodyFrame, size: CGSize, tight: Double, validate: Bool = true) -> BodyHole? {
        guard let hole = build(template, around: ref, size: size, tight: tight) else { return nil }
        guard validate else { return hole }

        // It must not be passable by standing still...
        let still = hole.judge(BodyScan(matte: BodyRectsMatte(rects: ref.neutralRects), size: size))
        guard !still.passed, still.outsideFraction > 0.2 || still.zoneFill.contains(where: { $0 < 0.05 })
                || still.keepOutFill.contains(where: { $0 > 0.2 }) else { return nil }
        // ...and passable by striking the pose.
        let posed = hole.judge(BodyScan(matte: BodyRectsMatte(rects: hole.idealPose(for: ref, size: size)), size: size))
        guard posed.passed, posed.outsideFraction <= 0.04 else { return nil }
        return hole
    }

    private static func build(_ template: Template, around ref: BodyFrame, size: CGSize, tight: Double) -> BodyHole? {
        let u = ref.unit, pad = u * (0.55 - 0.3 * bodyClamp(tight, 0, 1))
        let cx = ref.centerX, sY = ref.shoulderY, top = ref.top
        let bodyHalf = max(ref.width, 2.2 * u) / 2 + pad
        let W = size.width

        func column(_ half: Double, to y: Double, corner: Double = 0) -> Part {
            .rect(CGRect(x: cx - half, y: -80, width: half * 2, height: y + 80), corner: corner)
        }
        let headColumn = Part.rect(CGRect(x: cx - (u / 2 + pad), y: sY - 0.3 * u, width: u + 2 * pad, height: top + pad - (sY - 0.3 * u)),
                                   corner: u / 2 + pad)

        switch template {
        case .left, .right, .middle:
            // A doorway to one side of the picture, as wide as you are with a little to spare. Fitting means really moving over.
            let slack = u * (0.4 - 0.15 * bodyClamp(tight, 0, 1))
            let holeW = max(ref.width, 2.2 * u) + 2 * slack
            guard holeW <= W * 0.7 else { return nil }
            let middle = template == .left ? W * 0.26 : template == .right ? W * 0.74 : W * 0.5
            let x = bodyClamp(middle - holeW / 2, -40, W + 40 - holeW)
            let door = Part.rect(CGRect(x: x, y: -80, width: holeW, height: top + pad + 80), corner: min(holeW / 2, 0.9 * u))
            return BodyHole(template: template, parts: [door], zones: [], keepOut: [])

        case .armsUp:
            let wedgeTop = sY + 3.2 * u
            func wedge(_ side: Double) -> Part {
                .quad([CGPoint(x: cx + side * 0.35 * u, y: sY - 0.3 * u),
                       CGPoint(x: cx + side * (bodyHalf + 0.2 * u), y: sY - 0.3 * u),
                       CGPoint(x: cx + side * (2.3 * u + pad * 0.6), y: wedgeTop),
                       CGPoint(x: cx + side * 0.45 * u, y: wedgeTop)])
            }
            let zones = [CGRect(x: cx - 2.0 * u, y: sY + 0.4 * u, width: 1.4 * u, height: 1.5 * u),
                         CGRect(x: cx + 0.6 * u, y: sY + 0.4 * u, width: 1.4 * u, height: 1.5 * u)].compactMap { onScreen($0, size) }
            guard zones.count == 2 else { return nil }
            return BodyHole(template: template, parts: [column(bodyHalf, to: sY + 0.1 * u), headColumn, wedge(-1), wedge(1)],
                            zones: zones, keepOut: [])

        case .armsOut:
            let bar = Part.rect(CGRect(x: -80, y: sY - 1.15 * u, width: W + 160, height: 1.5 * u), corner: 0)
            let reach = max(1.5 * u, ref.width / 2 + 0.25 * u)
            let zones = [CGRect(x: cx - reach - 1.4 * u, y: sY - 0.9 * u, width: 1.4 * u, height: 1.0 * u),
                         CGRect(x: cx + reach, y: sY - 0.9 * u, width: 1.4 * u, height: 1.0 * u)].compactMap { onScreen($0, size) }
            guard !zones.isEmpty else { return nil }
            return BodyHole(template: template, parts: [bar, column(bodyHalf, to: sY + 0.3 * u), headColumn], zones: zones, keepOut: [])

        case .crouch:
            let lid = top - 1.5 * u
            guard lid > 90 else { return nil }
            let clear = CGRect(x: cx - 0.9 * u, y: lid, width: 1.8 * u, height: 2.2 * u).intersection(CGRect(origin: .zero, size: size))
            guard !clear.isNull, clear.height >= 0.6 * u else { return nil }
            return BodyHole(template: template, parts: [column(bodyHalf * 1.1, to: lid, corner: u)], zones: [], keepOut: [clear])
        }
    }

    /// A zone trimmed to the picture, or nil when too little of it is in view for anyone to reach into.
    private static func onScreen(_ zone: CGRect, _ size: CGSize) -> CGRect? {
        let visible = zone.intersection(CGRect(origin: .zero, size: size))
        guard !visible.isNull, visible.width * visible.height >= zone.width * zone.height * 0.5 else { return nil }
        return visible
    }

    /// Rectangles for a body that is striking this hole's pose: what the hole was made to let through.
    func idealPose(for ref: BodyFrame, size: CGSize) -> [CGRect] {
        let u = ref.unit, cx = ref.centerX, sY = ref.shoulderY
        let neutral = ref.neutralRects
        switch template {
        case .left, .right, .middle:
            guard case .rect(let door, _)? = parts.first else { return neutral }
            return neutral.map { $0.offsetBy(dx: door.midX - cx, dy: 0) }
        case .armsUp:
            return neutral + [CGRect(x: cx - 1.25 * u, y: sY - 0.3 * u, width: 0.55 * u, height: 2.7 * u),
                              CGRect(x: cx + 0.7 * u, y: sY - 0.3 * u, width: 0.55 * u, height: 2.7 * u)]
        case .armsOut:
            let leftEdge = cx - 0.75 * u, rightEdge = cx + 0.75 * u
            return neutral + [CGRect(x: 0, y: sY - 0.7 * u, width: max(1, leftEdge), height: 0.6 * u),
                              CGRect(x: rightEdge, y: sY - 0.7 * u, width: max(1, size.width - rightEdge), height: 0.6 * u)]
        case .crouch:
            return neutral.map { $0.offsetBy(dx: 0, dy: -1.7 * u) }
        }
    }
}
