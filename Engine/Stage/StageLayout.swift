import CoreGraphics
import Foundation

// Present: what a shared screen or window does in the picture, beyond sitting behind you.
//
// Everything here is in normalised picture units so it reads the same at any output size: x runs 0...1 across the picture
// and y runs 0...1 up it (origin lower left, like Core Image). Sliders, the mouse on the Studio preview and your hands all
// read and write this one model, so they can never disagree about where something is.

/// How a shared screen or window is arranged with you.
enum StageArrangement: String, Codable, CaseIterable, Identifiable {
    /// The screen fills the picture behind you, as it always has.
    case backdrop
    /// The screen floats in the room as a framed panel and you stand in front of it.
    case floatingPanel
    /// The screen fills the picture and you are the thing that moves: your cutout or a camera bubble.
    case presenter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backdrop: return "Backdrop"
        case .floatingPanel: return "Floating Panel"
        case .presenter: return "Presenter"
        }
    }

    var blurb: String {
        switch self {
        case .backdrop: return "Your screen fills the picture behind you."
        case .floatingPanel: return "Your screen floats in the room and you stand in front of it."
        case .presenter: return "Your screen fills the picture and you move over it."
        }
    }

    /// Whether there is anything to move: the backdrop arrangement has no panel or bubble.
    var isArranged: Bool { self != .backdrop }
}

/// What fills the picture around a floating panel.
enum StageSurround: String, Codable, CaseIterable, Identifiable {
    /// The screen's own colours, blurred and dimmed, as if it lit a dark room.
    case ambient
    /// Your room, out of focus.
    case room
    /// One of the backdrops from the library.
    case backdrop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ambient: return "Ambient Glow"
        case .room: return "Your Room, Blurred"
        case .backdrop: return "A Backdrop"
        }
    }
}

/// How you appear in the Presenter arrangement.
enum PresenterStyle: String, Codable, CaseIterable, Identifiable {
    /// Just you, cut out, over the screen.
    case cutout
    /// You in a round camera bubble.
    case circle
    /// You in a bubble with soft square corners.
    case roundedSquare

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cutout: return "Cutout"
        case .circle: return "Circle"
        case .roundedSquare: return "Rounded Square"
        }
    }

    var isBubble: Bool { self != .cutout }
}

/// Where one movable thing sits: its centre, and its size as a fraction of the picture.
///
/// For the panel `size` is its width over the picture's width. For you it is your height over the picture's height: 1 is the
/// camera at full size, and for a bubble it is the bubble's diameter.
struct StageFrame: Codable, Equatable {
    var center: CGPoint
    var size: Double

    static let identity = StageFrame(center: CGPoint(x: 0.5, y: 0.5), size: 1)

    func isClose(to other: StageFrame, tolerance: Double = 1e-4) -> Bool {
        abs(center.x - other.center.x) < tolerance && abs(center.y - other.center.y) < tolerance && abs(size - other.size) < tolerance
    }
}

/// The two things Present can move.
enum StageItem: String, Codable, CaseIterable {
    case panel, presenter
}

/// Everything about how the shared screen and you are arranged, and how the panel looks.
struct StageLayout: Codable, Equatable {
    var arrangement: StageArrangement = .backdrop
    /// The floating panel.
    var panel = StageFrame(center: CGPoint(x: 0.345, y: 0.54), size: 0.58)
    /// You. In the Floating Panel arrangement this moves your cutout; at `.identity` you are where the camera put you.
    var presenter = StageFrame.identity
    var presenterStyle: PresenterStyle = .cutout
    /// Where the panel and you were before a double pinch or double click made them big. Nil when not maximised.
    var restorePanel: StageFrame?
    var restorePresenter: StageFrame?

    /// 0...1: how far the panel turns to face the middle of the picture as it moves to the side.
    var tilt = 0.5
    /// 0...1: how much the panel shifts against your head movement, for depth.
    var depth = 0.4
    /// 0...1: from nearly square corners to very round ones.
    var roundness = 0.5
    /// 0...1: how strong the panel's shadow is.
    var shadow = 0.6
    /// A small label with the window's name under the panel.
    var showsLabel = false
    var surround: StageSurround = .ambient
    /// The library backdrop used when `surround` is `.backdrop`.
    var surroundBackdrop: UUID?
    /// Things settle onto the centre, thirds and margins when you let go of them.
    var snapping = true
    /// Pinch with your hands to grab, move and resize.
    var handControl = false

    init() {}

    // MARK: Codable
    // Written by hand so that a setting added later decodes from an older save, taking its default.

    private enum CodingKeys: String, CodingKey {
        case arrangement, panel, presenter, presenterStyle, restorePanel, restorePresenter
        case tilt, depth, roundness, shadow, showsLabel, surround, surroundBackdrop, snapping, handControl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var layout = StageLayout()
        layout.arrangement = (try? c.decodeIfPresent(StageArrangement.self, forKey: .arrangement)) ?? layout.arrangement
        layout.panel = (try? c.decodeIfPresent(StageFrame.self, forKey: .panel)) ?? layout.panel
        layout.presenter = (try? c.decodeIfPresent(StageFrame.self, forKey: .presenter)) ?? layout.presenter
        layout.presenterStyle = (try? c.decodeIfPresent(PresenterStyle.self, forKey: .presenterStyle)) ?? layout.presenterStyle
        layout.restorePanel = try? c.decodeIfPresent(StageFrame.self, forKey: .restorePanel)
        layout.restorePresenter = try? c.decodeIfPresent(StageFrame.self, forKey: .restorePresenter)
        layout.tilt = (try? c.decodeIfPresent(Double.self, forKey: .tilt)) ?? layout.tilt
        layout.depth = (try? c.decodeIfPresent(Double.self, forKey: .depth)) ?? layout.depth
        layout.roundness = (try? c.decodeIfPresent(Double.self, forKey: .roundness)) ?? layout.roundness
        layout.shadow = (try? c.decodeIfPresent(Double.self, forKey: .shadow)) ?? layout.shadow
        layout.showsLabel = (try? c.decodeIfPresent(Bool.self, forKey: .showsLabel)) ?? layout.showsLabel
        layout.surround = (try? c.decodeIfPresent(StageSurround.self, forKey: .surround)) ?? layout.surround
        layout.surroundBackdrop = try? c.decodeIfPresent(UUID.self, forKey: .surroundBackdrop)
        layout.snapping = (try? c.decodeIfPresent(Bool.self, forKey: .snapping)) ?? layout.snapping
        layout.handControl = (try? c.decodeIfPresent(Bool.self, forKey: .handControl)) ?? layout.handControl
        self = layout.clamped()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(arrangement, forKey: .arrangement)
        try c.encode(panel, forKey: .panel)
        try c.encode(presenter, forKey: .presenter)
        try c.encode(presenterStyle, forKey: .presenterStyle)
        try c.encodeIfPresent(restorePanel, forKey: .restorePanel)
        try c.encodeIfPresent(restorePresenter, forKey: .restorePresenter)
        try c.encode(tilt, forKey: .tilt)
        try c.encode(depth, forKey: .depth)
        try c.encode(roundness, forKey: .roundness)
        try c.encode(shadow, forKey: .shadow)
        try c.encode(showsLabel, forKey: .showsLabel)
        try c.encode(surround, forKey: .surround)
        try c.encodeIfPresent(surroundBackdrop, forKey: .surroundBackdrop)
        try c.encode(snapping, forKey: .snapping)
        try c.encode(handControl, forKey: .handControl)
    }

    // MARK: Limits

    static let panelSizes: ClosedRange<Double> = 0.22...1.0
    static let cutoutSizes: ClosedRange<Double> = 0.3...1.15
    static let bubbleSizes: ClosedRange<Double> = 0.14...0.66

    /// The sizes you may be, for the current style.
    var presenterSizes: ClosedRange<Double> {
        arrangement == .presenter && presenterStyle.isBubble ? Self.bubbleSizes : Self.cutoutSizes
    }

    /// Whether the presenter is drawn as a bubble right now. Bubbles belong to the Presenter arrangement only.
    var showsBubble: Bool { arrangement == .presenter && presenterStyle.isBubble }

    /// Every number brought into range. Positions are kept on the picture; `StageGeometry` keeps whole items on it.
    func clamped() -> StageLayout {
        var out = self
        func unit(_ v: Double) -> Double { v.isFinite ? min(1, max(0, v)) : 0.5 }
        out.tilt = unit(tilt)
        out.depth = unit(depth)
        out.roundness = unit(roundness)
        out.shadow = unit(shadow)
        out.panel.size = Self.clamp(panel.size, Self.panelSizes)
        out.panel.center = CGPoint(x: unit(panel.center.x), y: unit(panel.center.y))
        out.presenter.size = Self.clamp(presenter.size, out.presenterSizes)
        // Your cutout may lean off an edge (the controller keeps enough of you in view), so its centre may sit a little outside.
        func loose(_ v: Double) -> Double { v.isFinite ? min(1.5, max(-0.5, v)) : 0.5 }
        out.presenter.center = CGPoint(x: loose(presenter.center.x), y: loose(presenter.center.y))
        return out
    }

    static func clamp(_ v: Double, _ range: ClosedRange<Double>) -> Double {
        guard v.isFinite else { return range.lowerBound }
        return min(range.upperBound, max(range.lowerBound, v))
    }

    func frame(of item: StageItem) -> StageFrame { item == .panel ? panel : presenter }

    mutating func setFrame(_ frame: StageFrame, of item: StageItem) {
        if item == .panel { panel = frame } else { presenter = frame }
    }

    /// The things that can be moved in this arrangement, front first.
    var movableItems: [StageItem] {
        switch arrangement {
        case .backdrop: return []
        case .floatingPanel: return [.panel, .presenter]
        case .presenter: return [.presenter]
        }
    }

    /// The thing hands grab in this arrangement. In front of a floating panel your own hands are in the way of you, so only the
    /// panel answers to a pinch there; the mouse can still move both.
    var handItem: StageItem? {
        switch arrangement {
        case .backdrop: return nil
        case .floatingPanel: return .panel
        case .presenter: return .presenter
        }
    }
}

// MARK: - Presets

/// Ready-made arrangements, one click each.
enum StagePreset: String, CaseIterable, Identifiable {
    case left, right, centre, cornerBubble, sideBySide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .centre: return "Centre"
        case .cornerBubble: return "Corner Bubble"
        case .sideBySide: return "Side by Side"
        }
    }

    var blurb: String {
        switch self {
        case .left: return "The screen on the left, angled toward you."
        case .right: return "The screen on the right, angled toward you."
        case .centre: return "A big screen behind you, like a stage."
        case .cornerBubble: return "The screen fills the picture, you in a bubble in the corner."
        case .sideBySide: return "The screen and you, side by side, not overlapping."
        }
    }

    /// `base` keeps the look (tilt, shadow, surround, hand control...); the preset sets the arrangement and where things are.
    func apply(to base: StageLayout) -> StageLayout {
        var out = base
        out.restorePanel = nil
        out.restorePresenter = nil
        switch self {
        case .left:
            out.arrangement = .floatingPanel
            out.panel = StageFrame(center: CGPoint(x: 0.345, y: 0.54), size: 0.58)
            out.presenter = .identity
        case .right:
            out.arrangement = .floatingPanel
            out.panel = StageFrame(center: CGPoint(x: 0.655, y: 0.54), size: 0.58)
            out.presenter = .identity
        case .centre:
            out.arrangement = .floatingPanel
            out.panel = StageFrame(center: CGPoint(x: 0.5, y: 0.58), size: 0.7)
            out.presenter = .identity
        case .cornerBubble:
            out.arrangement = .presenter
            out.presenterStyle = .circle
            out.presenter = StageFrame(center: CGPoint(x: 0.852, y: 0.225), size: 0.34)
        case .sideBySide:
            out.arrangement = .floatingPanel
            out.panel = StageFrame(center: CGPoint(x: 0.3, y: 0.53), size: 0.52)
            out.presenter = StageFrame(center: CGPoint(x: 0.76, y: 0.46), size: 0.92)
        }
        return out.clamped()
    }

    /// Whether `layout` is (near enough) this preset, for showing which one is chosen.
    func matches(_ layout: StageLayout) -> Bool {
        let made = apply(to: layout)
        guard made.arrangement == layout.arrangement, made.panel.isClose(to: layout.panel, tolerance: 0.004) else { return false }
        if made.arrangement == .presenter {
            return made.presenterStyle == layout.presenterStyle && made.presenter.isClose(to: layout.presenter, tolerance: 0.004)
        }
        return made.presenter.isClose(to: layout.presenter, tolerance: 0.004)
    }
}

/// The layout for each arrangement, remembered separately, so going back to the panel puts it where you left it.
struct StageMemory: Codable, Equatable {
    var current: StageLayout
    /// Keyed by `StageArrangement.rawValue`.
    var remembered: [String: StageLayout] = [:]

    init(current: StageLayout = StageLayout()) { self.current = current }

    private enum CodingKeys: String, CodingKey { case current, remembered }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        current = (try? c.decodeIfPresent(StageLayout.self, forKey: .current)) ?? StageLayout()
        remembered = (try? c.decodeIfPresent([String: StageLayout].self, forKey: .remembered)) ?? [:]
    }

    /// What a fresh arrangement looks like before it has ever been moved.
    static func starting(_ arrangement: StageArrangement, from base: StageLayout) -> StageLayout {
        switch arrangement {
        case .backdrop:
            // Nothing moves in the plain backdrop: you are where the camera puts you.
            var out = base
            out.arrangement = .backdrop
            out.presenter = .identity
            out.presenterStyle = .cutout
            out.restorePanel = nil
            out.restorePresenter = nil
            return out
        case .floatingPanel:
            return StagePreset.left.apply(to: base)
        case .presenter:
            var out = base
            out.arrangement = .presenter
            out.presenterStyle = .cutout
            out.presenter = StageFrame(center: CGPoint(x: 0.78, y: 0.4), size: 0.8)
            out.restorePresenter = nil
            return out.clamped()
        }
    }

    /// Switches arrangement. Positions come from the last time that arrangement was used; the look (tilt, shadow, surround,
    /// snapping, hand control) carries over, since those are about taste rather than place.
    mutating func switchTo(_ arrangement: StageArrangement) {
        remembered[current.arrangement.rawValue] = current
        guard arrangement != current.arrangement else { return }
        var next = remembered[arrangement.rawValue] ?? Self.starting(arrangement, from: current)
        next.arrangement = arrangement
        next.tilt = current.tilt
        next.depth = current.depth
        next.roundness = current.roundness
        next.shadow = current.shadow
        next.showsLabel = current.showsLabel
        next.surround = current.surround
        next.surroundBackdrop = current.surroundBackdrop
        next.snapping = current.snapping
        next.handControl = current.handControl
        current = next.clamped()
    }

    /// Takes a new current layout (a slider, a preset, a drag) and remembers it for its arrangement.
    mutating func update(_ layout: StageLayout) {
        current = layout
        remembered[layout.arrangement.rawValue] = layout
    }
}

// MARK: - Geometry

/// Where things land in output pixels. Pure functions, shared by the composer that draws them, the controller that moves them,
/// and the Studio, which hit-tests the mouse against them.
enum StageGeometry {
    static let picture = CGSize(width: 1280, height: 720)
    /// Nothing is let go of closer than this to the edge of the picture, in pixels.
    static let safeMargin: CGFloat = 28

    /// The panel's width over its height, for content of aspect `aspect`, kept sane.
    static func saneAspect(_ aspect: Double) -> Double {
        guard aspect.isFinite, aspect > 0 else { return 16.0 / 10 }
        return min(4, max(0.4, aspect))
    }

    /// The panel's size in pixels, before any tilt.
    static func panelSize(_ frame: StageFrame, aspect: Double, in picture: CGSize = picture) -> CGSize {
        var width = picture.width * frame.size
        var height = width / saneAspect(aspect)
        // A tall window at full width would be taller than the picture; fit it instead.
        let maxHeight = picture.height * 0.96
        if height > maxHeight {
            height = maxHeight
            width = height * saneAspect(aspect)
        }
        return CGSize(width: width, height: height)
    }

    /// The panel's rectangle in pixels, before any tilt or depth.
    static func panelRect(_ frame: StageFrame, aspect: Double, in picture: CGSize = picture) -> CGRect {
        let size = panelSize(frame, aspect: aspect, in: picture)
        let c = point(frame.center, in: picture)
        return CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
    }

    /// Normalised to pixels.
    static func point(_ p: CGPoint, in picture: CGSize = picture) -> CGPoint {
        CGPoint(x: p.x * picture.width, y: p.y * picture.height)
    }

    /// Pixels to normalised.
    static func normalised(_ p: CGPoint, in picture: CGSize = picture) -> CGPoint {
        CGPoint(x: p.x / picture.width, y: p.y / picture.height)
    }

    /// Takes the camera picture (output pixels) to where your cutout sits.
    static func presenterTransform(_ frame: StageFrame, in picture: CGSize = picture) -> CGAffineTransform {
        let s = CGFloat(frame.size)
        let c = point(frame.center, in: picture)
        return CGAffineTransform(translationX: -picture.width / 2, y: -picture.height / 2)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: c.x, y: c.y))
    }

    /// The square a camera bubble fills, in pixels.
    static func bubbleRect(_ frame: StageFrame, in picture: CGSize = picture) -> CGRect {
        let side = picture.height * frame.size
        let c = point(frame.center, in: picture)
        return CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side)
    }

    /// The part of the picture taken up by your cutout: a box around where the cutout's middle is (`anchor`, in camera pixels, or
    /// the picture's middle when unknown), as wide as shoulders and as tall as a head and chest.
    static func cutoutRect(_ frame: StageFrame, anchor: CGPoint?, in picture: CGSize = picture) -> CGRect {
        let t = presenterTransform(frame, in: picture)
        let a = (anchor ?? CGPoint(x: picture.width / 2, y: picture.height * 0.42)).applying(t)
        let s = CGFloat(frame.size)
        let w = picture.width * 0.4 * s, h = picture.height * 0.86 * s
        return CGRect(x: a.x - w / 2, y: a.y - h * 0.42, width: w, height: h)
    }

    /// The panel's turn about its upright axis, in radians: it turns to face the middle of the picture as it moves to one side.
    /// Positive turns the right edge away.
    static func panelYaw(centerX: Double, tilt: Double, head: Double = 0, depth: Double = 0) -> Double {
        let off = max(-1, min(1, (0.5 - centerX) / 0.32))
        // Eased, so the turn builds gently away from the middle and levels off toward the edge.
        let eased = off * (1.5 - 0.5 * off * off)
        return tilt * 0.3 * eased + head * depth * 0.05
    }

    /// A slight look up at the panel, as at a screen on a wall.
    static func panelPitch(tilt: Double) -> Double { tilt * 0.045 }

    static let focalLength: Double = 1900

    /// The panel's four corners after its turn, depth shift and lift, in pixels: lower left, lower right, upper right, upper left.
    /// `head` is your offset from the middle of the picture, -1...1 each way, y up.
    static func panelQuad(_ layout: StageLayout, aspect: Double, head: CGPoint = .zero, lift: Double = 0,
                          in picture: CGSize = picture) -> [CGPoint] {
        let rect = panelRect(layout.panel, aspect: aspect, in: picture)
        let grow = 1 + 0.02 * lift
        let w = Double(rect.width) * grow, h = Double(rect.height) * grow
        let shift = CGPoint(x: -head.x * layout.depth * 16, y: -head.y * layout.depth * 8)
        let c = CGPoint(x: rect.midX + shift.x, y: rect.midY + shift.y)
        let yaw = panelYaw(centerX: layout.panel.center.x, tilt: layout.tilt, head: Double(head.x), depth: layout.depth)
        let pitch = panelPitch(tilt: layout.tilt)
        return project(center: c, width: w, height: h, yaw: yaw, pitch: pitch)
    }

    /// A flat rectangle turned in space and seen by a camera `focalLength` pixels away.
    static func project(center c: CGPoint, width w: Double, height h: Double, yaw: Double, pitch: Double, focal: Double = focalLength) -> [CGPoint] {
        let corners = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
        return corners.map { x, y in
            let x1 = x * cos(yaw), z1 = x * sin(yaw)
            let y2 = y * cos(pitch) - z1 * sin(pitch), z2 = y * sin(pitch) + z1 * cos(pitch)
            let s = focal / (focal + z2)
            return CGPoint(x: Double(c.x) + x1 * s, y: Double(c.y) + y2 * s)
        }
    }

    static func bounds(of quad: [CGPoint]) -> CGRect {
        let xs = quad.map(\.x), ys = quad.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return .zero }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// The panel's corner radius in pixels, for a panel `height` pixels tall.
    static func cornerRadius(roundness: Double, height: Double) -> Double {
        let r = 4 + roundness * 30
        return min(r, height * 0.22)
    }

    /// The item's outline in pixels: the panel's turned corners, the bubble's square, or the box round your cutout.
    static func itemQuad(_ item: StageItem, layout: StageLayout, aspect: Double, head: CGPoint = .zero, lift: Double = 0,
                         anchor: CGPoint? = nil, in picture: CGSize = picture) -> [CGPoint] {
        switch item {
        case .panel:
            return panelQuad(layout, aspect: aspect, head: head, lift: lift, in: picture)
        case .presenter:
            var r = layout.showsBubble ? bubbleRect(layout.presenter, in: picture) : cutoutRect(layout.presenter, anchor: anchor, in: picture)
            let grow = CGFloat(0.02 * lift)
            r = r.insetBy(dx: -r.width * grow / 2, dy: -r.height * grow / 2)
            return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        }
    }

    /// The front-most item under a point in pixels, for the mouse. `slop` widens each item a little.
    static func item(at p: CGPoint, layout: StageLayout, aspect: Double, anchor: CGPoint? = nil, slop: CGFloat = 6) -> StageItem? {
        // You stand in front of the panel, but a click on the panel is far more likely meant for it, so it wins inside its outline.
        let order: [StageItem] = layout.arrangement == .floatingPanel ? [.panel, .presenter] : layout.movableItems
        for item in order {
            let r = bounds(of: itemQuad(item, layout: layout, aspect: aspect, anchor: anchor)).insetBy(dx: -slop, dy: -slop)
            if r.contains(p) { return item }
        }
        return nil
    }

    /// The panel's frame when maximised: as big as fits with a small margin.
    static func maximisedPanel(aspect: Double, in picture: CGSize = picture) -> StageFrame {
        let a = saneAspect(aspect)
        let maxW = 0.94, maxH = 0.94
        let widthFromHeight = Double(picture.height) * maxH * a / Double(picture.width)
        return StageFrame(center: CGPoint(x: 0.5, y: 0.5), size: min(maxW, widthFromHeight))
    }

    static func maximisedPresenter(bubble: Bool) -> StageFrame {
        bubble ? StageFrame(center: CGPoint(x: 0.5, y: 0.5), size: 0.62) : StageFrame(center: CGPoint(x: 0.5, y: 0.5), size: 1)
    }

    /// Whether the presenter transform moves you at all.
    static func isIdentity(_ frame: StageFrame) -> Bool { frame.isClose(to: .identity, tolerance: 1e-3) }
}
