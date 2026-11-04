import CoreGraphics
import Foundation

/// Something the mouse or trackpad did on the Studio preview, in normalised picture units (y up).
enum StagePointerEvent: Equatable {
    case down(CGPoint)
    case drag(CGPoint)
    case up(CGPoint)
    /// Where the pointer is over the preview, or nil once it has left.
    case hover(CGPoint?)
    /// A trackpad pinch: 0.1 is ten per cent bigger.
    case magnify(Double, at: CGPoint)
    /// A scroll, in points; up makes things bigger.
    case scroll(Double, at: CGPoint)
    case doubleClick(CGPoint)
}

/// What is going on right now that is not part of the saved layout: how far each item is lifted while it is held.
struct StageLive: Equatable {
    var panelLift = 0.0
    var presenterLift = 0.0

    func lift(of item: StageItem) -> Double { item == .panel ? panelLift : presenterLift }
}

/// Something worth knowing happened: for tests, and for anything that wants to react.
enum StageEvent: Equatable {
    case grabbed(StageItem, byHand: Bool)
    case resizing(StageItem)
    case released(StageItem)
    case snapped(StageItem, [StageGuide])
    case maximised(StageItem, Bool)
}

struct StageControlInput {
    /// Hands in output pixels, as the tracker gives them. The camera picture is mapped onto the whole picture, so wherever your cutout
    /// or bubble is, your hand works like a finger on a trackpad the size of the picture.
    var hands: [HandState] = []
    var dt: Double
    var pointer: [StagePointerEvent] = []
    /// The shared content's width over height, as the panel shows it right now.
    var aspect: Double = 16.0 / 10
    /// Your head's offset from the middle of the picture, -1...1 each way, y up. Drives the panel's depth shift.
    var head: CGPoint = .zero
    /// Where the middle of your cutout is in the camera picture (output pixels), when known.
    var anchor: CGPoint?
    /// A lens that uses hands is on too, so a grab must be held a little longer to be sure it was meant.
    var lensUsesHands = false
}

struct StageControlOutput {
    /// The layout as it should be drawn this frame.
    var layout: StageLayout
    var live: StageLive
    /// The chrome for the preview only: cursors, rings, guides.
    var overlay: StageOverlayState
    var events: [StageEvent]
    /// Something is held or still moving.
    var isActive: Bool
}

/// Grabbing, moving and resizing the panel or you, with your hands or the mouse.
///
/// A pure state machine: hands, pointer events and time in; the layout to draw, the preview's chrome and events out. It owns no
/// pictures and no clocks, so every behaviour can be checked with made-up hands.
///
/// It is built to be hard to set off by accident while you talk with your hands:
/// - Only a pinch (thumb tip to index tip, with the index finger reaching out of the hand) counts. An open hand, a fist, a pointing
///   finger, a wave or hands on a keyboard never read as one.
/// - The pinch must *start* on or near the item. A pinch made elsewhere and carried over it does nothing.
/// - It must be held still for `holdTime` (longer while a hand lens is on) before it takes hold, and the hand must have been open
///   just before, so a hand that comes into view already pinched does nothing.
/// - A hand that leaves the picture lets go gently where it is.
struct StageHandController {
    // MARK: Tuning

    /// Pinch closes below this (thumb tip to index tip over the palm) and opens above `pinchOpen`, the same edges the games use.
    static let pinchClose = HandGesture.Pose.pinchBelow
    static let pinchOpen = HandGesture.Pose.pinchReleaseAbove
    /// How long a pinch must be held before it takes hold.
    static let holdTime = 0.12
    /// The same while a lens that reads hands is on: long enough that the ring visibly fills.
    static let lensHoldTime = 0.32
    /// A second hand joining a grab to resize is already deliberate, so it may take hold sooner.
    static let secondHandHold = 0.08
    /// The hand must have been open at least this long before a pinch counts.
    static let armAfter = 0.1
    /// A pinch lets go once it has read open this long.
    static let releaseAfter = 0.06
    /// A hand the tracker has not actually seen for this long lets go.
    static let lostAfter = 0.15
    /// A pinch that wanders further than this (in palms) while it is being held to grab was not a grab.
    static let wanderLimit = 0.9
    /// A hand moving faster than this (palms a second) as it pinches is waving, not grabbing.
    static let maxStartSpeed = 4.5
    static let minConfidence = 0.45
    /// A pinch let go within this long without moving is a tap; two taps within `doubleWindow` toggle maximise.
    static let tapLongest = 0.42
    static let doubleWindow = 0.6
    /// Hands coming up into view from the bottom edge (or resting on a keyboard) are ignored.
    static let bottomBand: CGFloat = 34

    /// How far from an item a pinch may start and still grab it, in pixels: generous, and bigger for a bigger (nearer) hand.
    static func reach(for hand: HandState) -> Double { max(48, hand.size * 0.8) }

    // MARK: State

    private(set) var layout: StageLayout
    let picture: CGSize
    private var motions: [StageItem: StageItemMotion] = [:]
    /// The layout as last handed to the interface, so its copy coming back (with a slider moved, say) is not mistaken for a new
    /// choice of place.
    private var sent: StageLayout
    private var time = 0.0

    private struct Grab {
        enum Holder: Equatable {
            case hand(Int)
            case pointer
            /// The mouse on a corner handle: resizing.
            case handle
        }

        var item: StageItem
        var holder: Holder
        /// Item centre minus the grip point, in pixels.
        var offset: CGVector
        var startedAt: Double
        /// Where the item was when it was taken hold of.
        var startCenter = CGPoint.zero
        /// A second hand resizing, and how things stood when it joined.
        var second: Int?
        var startDistance = 0.0
        var startSize = 0.0
        var startOffset = CGVector.zero
        /// For the mouse on a handle: the pointer's distance from the centre when it started.
        var handleDistance = 0.0
    }

    private var grab: Grab?

    private struct Track {
        var steady = HandFXSteady(calm: 1.5, eager: 0.012)
        var point = CGPoint.zero
        var size = 100.0
        var closed = false
        var openFor = 0.0
        var closedFor = 0.0
        var releaseFor = 0.0
        var closeAt = CGPoint.zero
        /// The item the pinch started near, if any.
        var nearAtClose: StageItem?
        /// The pinch broke a rule (not armed, too fast, wandered...) and cannot grab until it opens again.
        var disqualified = false
        var wandered = 0.0
        var closeness = HandFXLevel(rise: 0.06, fall: 0.12)
        var alpha = HandFXLevel(rise: 0.12, fall: 0.3)
        var trail: [(point: CGPoint, time: Double)] = []
        var lastPoint: CGPoint?
        var speed = 0.0
        var eligible = false
        var seen = true
    }

    private var tracks: [Int: Track] = [:]
    private var lastTap: (time: Double, point: CGPoint)?

    // Preview chrome, eased.
    private var hover = HandFXLevel(rise: 0.1, fall: 0.25)
    private var tighten = HandFXLevel(rise: 0.06, fall: 0.15)
    private var selected = HandFXLevel(rise: 0.1, fall: 0.35)
    private var stretchAlpha = HandFXLevel(rise: 0.08, fall: 0.2)
    private var lifts: [StageItem: HandFXLevel] = [.panel: HandFXLevel(rise: 0.1, fall: 0.25), .presenter: HandFXLevel(rise: 0.1, fall: 0.25)]
    private var chromeItem: StageItem?
    private var lastChromeQuad: [CGPoint] = []
    private var lingerSelected = 0.0
    private var pulseAge: Double?
    private var flashes: [(guide: StageGuide, age: Double)] = []
    private var lastStretch: StageOverlayState.Stretch?
    private var pointerHover: CGPoint?

    init(layout: StageLayout = StageLayout(), picture: CGSize = StageGeometry.picture) {
        self.layout = layout.clamped()
        self.picture = picture
        sent = self.layout
        for item in StageItem.allCases { place(item, layout.frame(of: item)) }
    }

    var isHolding: Bool { grab != nil }
    var heldItem: StageItem? { grab?.item }

    private mutating func place(_ item: StageItem, _ frame: StageFrame) {
        motions[item] = StageItemMotion(center: StageGeometry.point(frame.center, in: picture), size: frame.size)
    }

    // MARK: Taking a new layout

    /// A layout chosen in the interface: a slider, a preset, a style. Places that differ from what was last handed out are animated
    /// to; anything being held right now stays in the hand.
    mutating func adopt(_ new: StageLayout) {
        let new = new.clamped()
        let arrangementChanged = new.arrangement != layout.arrangement || new.showsBubble != layout.showsBubble
        let previous = sent
        layout = new
        sent = new
        if arrangementChanged {
            grab = nil
            for item in StageItem.allCases { place(item, new.frame(of: item)) }
            return
        }
        for item in StageItem.allCases {
            let wanted = new.frame(of: item)
            guard !wanted.isClose(to: previous.frame(of: item)) else { continue }
            if grab?.item == item { continue }
            let jump = HandState.distance(wanted.center, previous.frame(of: item).center) + abs(wanted.size - previous.frame(of: item).size)
            // A slider nudging the size follows closely; a preset or a reset glides across.
            let target = StageGeometry.point(wanted.center, in: picture)
            motions[item]?.spring(to: target, size: wanted.size, with: jump < 0.06 ? .follow : .zoom)
        }
    }

    /// The pipeline handed `layout` to the interface.
    mutating func didReport(_ layout: StageLayout) { sent = layout }

    // MARK: A frame

    mutating func step(_ input: StageControlInput) -> StageControlOutput {
        let dt = min(max(input.dt, 0), 0.25)
        time += dt
        var events: [StageEvent] = []

        for event in input.pointer { handle(event, input: input, events: &events) }
        if layout.handControl, layout.handItem != nil {
            readHands(input, dt: dt, events: &events)
        } else if !tracks.isEmpty {
            if case .hand? = grab?.holder { release(velocity: .zero, input: input, events: &events) }
            tracks.removeAll()
        }
        followGrab(input)

        var active = grab != nil
        for item in StageItem.allCases {
            if motions[item]?.step(dt: dt) == true { active = true }
            lifts[item]?.approach(grab?.item == item ? 1 : 0, dt: dt)
        }

        var out = layout
        for item in StageItem.allCases {
            guard let m = motions[item] else { continue }
            let shown = displayed(item, center: m.center, size: m.size, input: input)
            out.setFrame(StageFrame(center: StageGeometry.normalised(shown, in: picture), size: m.size), of: item)
        }
        out = out.clamped()
        layout.panel = out.panel
        layout.presenter = out.presenter
        let live = StageLive(panelLift: lifts[.panel]?.value ?? 0, presenterLift: lifts[.presenter]?.value ?? 0)
        let overlay = makeOverlay(out, live: live, input: input, dt: dt)
        return StageControlOutput(layout: out, live: live, overlay: overlay, events: events, isActive: active)
    }

    // MARK: Geometry helpers

    private func box(_ item: StageItem, _ frame: StageFrame, input: StageControlInput) -> CGRect {
        switch item {
        case .panel: return StageGeometry.panelRect(frame, aspect: input.aspect, in: picture)
        case .presenter:
            return layout.showsBubble ? StageGeometry.bubbleRect(frame, in: picture) : StageGeometry.cutoutRect(frame, anchor: input.anchor, in: picture)
        }
    }

    private func isCutout(_ item: StageItem) -> Bool { item == .presenter && !layout.showsBubble }

    /// Where an item's box must stay. Your cutout may lean off the sides and run off the bottom as a body does, but never leave.
    private func area(_ item: StageItem, box b: CGRect) -> CGRect {
        let m = StageGeometry.safeMargin
        if isCutout(item) {
            return CGRect(x: -b.width * 0.25, y: -b.height * 0.35, width: picture.width + b.width * 0.5,
                          height: picture.height + b.height * 0.35 - m)
        }
        return CGRect(origin: .zero, size: picture).insetBy(dx: m, dy: m)
    }

    private func frame(_ item: StageItem, center c: CGPoint, size s: Double) -> StageFrame {
        StageFrame(center: StageGeometry.normalised(c, in: picture), size: s)
    }

    /// The centre (pixels) an item heading for `c` should come to rest at: kept on the picture, and on a guide if one is near.
    private func settled(_ item: StageItem, center c: CGPoint, size s: Double, snap: Bool, input: StageControlInput) -> (CGPoint, [StageGuide]) {
        let b = box(item, frame(item, center: c, size: s), input: input)
        let delta = CGVector(dx: c.x - b.midX, dy: c.y - b.midY)
        let half = CGSize(width: b.width / 2, height: b.height / 2)
        let a = area(item, box: b)
        var bc = StageMotion.clampCentre(CGPoint(x: b.midX, y: b.midY), half: half, area: a)
        var guides: [StageGuide] = []
        if snap, layout.snapping {
            let result = StageSnap.snap(bc, half: half, picture: picture)
            if isCutout(item) {
                // A cutout lines up across the picture; up and down it belongs where your body puts it.
                if let g = result.guides.first(where: \.vertical) { bc.x = result.center.x; guides = [g] }
            } else {
                bc = result.center
                guides = result.guides
            }
            bc = StageMotion.clampCentre(bc, half: half, area: a)
        }
        return (CGPoint(x: bc.x + delta.dx, y: bc.y + delta.dy), guides)
    }

    /// Where an item at `c` is drawn: past an edge it is held back with resistance, so it can never be lost off the picture.
    private func displayed(_ item: StageItem, center c: CGPoint, size s: Double, input: StageControlInput) -> CGPoint {
        let b = box(item, frame(item, center: c, size: s), input: input)
        let delta = CGVector(dx: c.x - b.midX, dy: c.y - b.midY)
        let banded = StageMotion.rubberBanded(CGPoint(x: b.midX, y: b.midY), half: CGSize(width: b.width / 2, height: b.height / 2),
                                              area: area(item, box: b))
        return CGPoint(x: banded.x + delta.dx, y: banded.y + delta.dy)
    }

    private func quad(_ item: StageItem, layout l: StageLayout, input: StageControlInput, lift: Double) -> [CGPoint] {
        StageGeometry.itemQuad(item, layout: l, aspect: input.aspect, head: input.head, lift: lift, anchor: input.anchor, in: picture)
    }

    private func currentLayout() -> StageLayout {
        var l = layout
        for item in StageItem.allCases {
            if let m = motions[item] { l.setFrame(frame(item, center: m.center, size: m.size), of: item) }
        }
        return l
    }

    private func distance(from p: CGPoint, to r: CGRect) -> Double {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(Double(dx), Double(dy))
    }

    private func sizeRange(_ item: StageItem) -> ClosedRange<Double> {
        item == .panel ? StageLayout.panelSizes : layout.presenterSizes
    }

    // MARK: Hands

    private func holdNeeded(_ input: StageControlInput) -> Double { input.lensUsesHands ? Self.lensHoldTime : Self.holdTime }

    private mutating func readHands(_ input: StageControlInput, dt: Double, events: inout [StageEvent]) {
        guard let item = layout.handItem else { return }
        let l = currentLayout()
        let itemBox = StageGeometry.bounds(of: quad(item, layout: l, input: input, lift: lifts[item]?.value ?? 0))
        let present = Set(input.hands.map(\.id))

        for hand in input.hands {
            var t = tracks[hand.id] ?? Track()
            t.seen = hand.unseenFor <= Self.lostAfter
            t.trail.removeAll { time - $0.time > 0.16 }
            if hand.unseenFor > 0 {
                // The tracker is guessing where a hand went (a blur, a finger across the lens). Nothing moves or changes on a guess:
                // whatever it holds stays put, and if the hand stays gone it lets go where it is.
                t.eligible = false
                t.closeness.approach(t.closeness.value, dt: dt)
                tracks[hand.id] = t
                if !t.seen, case .hand(hand.id)? = grab?.holder { release(velocity: .zero, input: input, events: &events) }
                continue
            }

            t.point = t.steady.update(hand.pinchPoint, dt: dt, snap: 220)
            t.size = hand.size
            if let last = t.lastPoint, dt > 0 {
                let moved = HandState.distance(last, t.point) / max(hand.size, 1) / dt
                t.speed += (moved - t.speed) * min(1, dt / 0.06)
            }
            t.lastPoint = t.point
            t.trail.append((t.point, time))

            let reachIndex = hand.reach(of: .index) > 1.1
            let closedReading = hand.pinch < Self.pinchClose && reachIndex
            let openReading = hand.pinch > Self.pinchOpen || !reachIndex
            // A cursor is shown only for a hand shaped for pinching: index out, thumb toward it. Not for fists, and not for a flat hand
            // with every finger out (unless its fingertips really are together, as in an OK sign).
            t.eligible = reachIndex && hand.pinch < 0.95 && (hand.fingersUp < 4 || hand.pinch < Self.pinchClose)
            let closeness = 1 - min(1, max(0, (hand.pinch - Self.pinchClose) / (0.95 - Self.pinchClose)))
            t.closeness.approach(t.eligible ? closeness : 0, dt: dt)

            if !t.closed {
                if closedReading {
                    t.closed = true
                    t.closedFor = 0
                    t.releaseFor = 0
                    t.closeAt = t.point
                    t.wandered = 0
                    let reach = Self.reach(for: hand)
                    let near = distance(from: t.point, to: itemBox) <= reach
                    // The second hand of a resize may start a little further out: it is reaching for the far side.
                    let heldByOther = grab.map { $0.item == item && $0.holder != .hand(hand.id) } ?? false
                    let nearForSecond = heldByOther && distance(from: t.point, to: itemBox) <= reach * 1.8
                    t.nearAtClose = near || nearForSecond ? item : nil
                    // Right after a tap the hand only has to open briefly: that is the gap in a double pinch.
                    let doubling = lastTap.map { time - $0.time < Self.doubleWindow } ?? false
                    let armed = t.openFor + 1e-9 >= (doubling ? 0.03 : Self.armAfter)
                    t.disqualified = !armed || t.speed > Self.maxStartSpeed || hand.confidence < Self.minConfidence
                        || t.point.y < Self.bottomBand
                } else {
                    t.openFor += dt
                }
            } else {
                t.closedFor += dt
                t.wandered = max(t.wandered, HandState.distance(t.point, t.closeAt) / max(hand.size, 1))
                if openReading {
                    t.releaseFor += dt
                    if t.releaseFor + 1e-9 >= Self.releaseAfter {
                        t.closed = false
                        t.openFor = 0
                        tracks[hand.id] = t
                        let wasTap = t.closedFor <= Self.tapLongest && t.wandered < 0.6 && t.nearAtClose != nil && !t.disqualified
                        pinchOpened(hand.id, input: input, events: &events)
                        if wasTap { tapped(at: t.point, item: item, input: input, events: &events) }
                        t = tracks[hand.id] ?? t
                    }
                } else {
                    t.releaseFor = 0
                }
            }

            tracks[hand.id] = t
            if t.closed, !t.disqualified, t.nearAtClose == item { tryTakeHold(hand.id, item: item, input: input, events: &events) }
            if var again = tracks[hand.id], again.closed, grab?.holder != .hand(hand.id), grab?.second != hand.id,
               again.wandered > Self.wanderLimit {
                again.disqualified = true
                tracks[hand.id] = again
            }
        }

        // Hands that have gone let go, gently, where they are.
        for id in tracks.keys where !present.contains(id) {
            if case .hand(id)? = grab?.holder { release(velocity: .zero, input: input, events: &events) }
            if grab?.second == id { endResize(input) }
            tracks[id] = nil
        }
        for id in tracks.keys where tracks[id]?.seen == false {
            if case .hand(id)? = grab?.holder { release(velocity: .zero, input: input, events: &events) }
            if grab?.second == id { endResize(input) }
        }
    }

    private mutating func tryTakeHold(_ id: Int, item: StageItem, input: StageControlInput, events: inout [StageEvent]) {
        guard let t = tracks[id] else { return }
        if let g = grab {
            // A second hand on the held item: resize.
            guard g.item == item, case .hand(let first) = g.holder, first != id, g.second == nil,
                  t.closedFor + 1e-9 >= Self.secondHandHold, let a = tracks[first]?.point, let m = motions[item] else { return }
            var next = g
            next.second = id
            next.startDistance = max(20, HandState.distance(a, t.point))
            next.startSize = m.size
            let mid = CGPoint(x: (a.x + t.point.x) / 2, y: (a.y + t.point.y) / 2)
            next.startOffset = CGVector(dx: m.center.x - mid.x, dy: m.center.y - mid.y)
            grab = next
            events.append(.resizing(item))
            return
        }
        guard t.closedFor + 1e-9 >= holdNeeded(input), t.wandered <= Self.wanderLimit, var m = motions[item] else { return }
        m.hold()
        motions[item] = m
        grab = Grab(item: item, holder: .hand(id), offset: CGVector(dx: m.center.x - t.point.x, dy: m.center.y - t.point.y), startedAt: time,
                    startCenter: m.center, startSize: m.size)
        pulseAge = 0
        chromeItem = item
        events.append(.grabbed(item, byHand: true))
    }

    private mutating func pinchOpened(_ id: Int, input: StageControlInput, events: inout [StageEvent]) {
        guard let g = grab else { return }
        if case .hand(id) = g.holder {
            if let second = g.second, let other = tracks[second]?.point, let m = motions[g.item] {
                // One hand of a resize let go: the other carries on moving it.
                grab = Grab(item: g.item, holder: .hand(second), offset: CGVector(dx: m.center.x - other.x, dy: m.center.y - other.y),
                            startedAt: g.startedAt, startCenter: g.startCenter, startSize: g.startSize)
            } else {
                release(velocity: motions[g.item]?.velocity ?? .zero, input: input, events: &events)
            }
        } else if g.second == id {
            endResize(input)
        }
    }

    private mutating func endResize(_ input: StageControlInput) {
        guard var g = grab, g.second != nil else { return }
        g.second = nil
        if case .hand(let first) = g.holder, let p = tracks[first]?.point, let m = motions[g.item] {
            g.offset = CGVector(dx: m.center.x - p.x, dy: m.center.y - p.y)
        }
        grab = g
    }

    private mutating func tapped(at p: CGPoint, item: StageItem, input: StageControlInput, events: inout [StageEvent]) {
        if let last = lastTap, time - last.time <= Self.doubleWindow, HandState.distance(last.point, p) < 140 {
            lastTap = nil
            toggleMaximise(item, input: input, events: &events)
        } else {
            lastTap = (time, p)
        }
    }

    /// While held: the item goes where the hand (or mouse) puts it, keeping where it was grabbed; two hands scale it about their middle.
    private mutating func followGrab(_ input: StageControlInput) {
        guard let g = grab, var m = motions[g.item] else { return }
        switch g.holder {
        case .hand(let id):
            guard let a = tracks[id], a.seen else { return }
            if let second = g.second, let b = tracks[second], b.seen {
                let d = max(20, HandState.distance(a.point, b.point))
                let size = StageLayout.clamp(g.startSize * d / g.startDistance, sizeRange(g.item))
                let k = size / max(g.startSize, 1e-6)
                let mid = CGPoint(x: (a.point.x + b.point.x) / 2, y: (a.point.y + b.point.y) / 2)
                let c = CGPoint(x: mid.x + g.startOffset.dx * k, y: mid.y + g.startOffset.dy * k)
                m.follow(c, size: size)
                lastStretch = StageOverlayState.Stretch(a: a.point, b: b.point, label: percent(g.item, size), alpha: 1)
            } else {
                m.follow(CGPoint(x: a.point.x + g.offset.dx, y: a.point.y + g.offset.dy), size: m.size)
            }
        case .pointer, .handle:
            break
        }
        motions[g.item] = m
    }

    // MARK: Letting go and maximising

    private mutating func release(velocity v: CGVector, input: StageControlInput, events: inout [StageEvent]) {
        guard let g = grab, var m = motions[g.item] else { grab = nil; return }
        grab = nil
        let v = StageMotion.capped(v)
        let speed = hypot(Double(v.dx), Double(v.dy))
        // A slow release settles briskly onto a guide; a throw glides. Either way the spring starts with the speed the hand gave
        // it and only ever slows, so nothing lurches after you let go.
        let omega = 4.5 + 4.5 * (1 - min(1, speed / 600))
        let rest = CGPoint(x: Double(m.center.x) + Double(v.dx) / omega, y: Double(m.center.y) + Double(v.dy) / omega)
        let size = StageLayout.clamp(m.size, sizeRange(g.item))
        // Taken hold of and let go without being moved (a tap, half of a double pinch): it stays exactly where it was.
        let untouched = HandState.distance(m.center, g.startCenter) < 6 && speed < 80 && abs(size - g.startSize) < 1e-3
        let (target, guides) = untouched ? (g.startCenter, []) : settled(g.item, center: rest, size: size, snap: true, input: input)
        let clampedHard = HandState.distance(target, rest) > StageSnap.reach + 1
        m.velocity = v
        m.spring(to: target, size: size, with: StageMotion.Spring(omega: clampedHard ? 7 : omega, zeta: 0.86))
        motions[g.item] = m
        lingerSelected = 0.6
        events.append(.released(g.item))
        if !guides.isEmpty {
            events.append(.snapped(g.item, guides))
            flashes.removeAll()
            flashes = guides.map { ($0, 0) }
        }
    }

    private mutating func toggleMaximise(_ item: StageItem, input: StageControlInput, events: inout [StageEvent]) {
        guard var m = motions[item] else { return }
        if grab?.item == item { grab = nil }
        let restore = item == .panel ? layout.restorePanel : layout.restorePresenter
        // Where it is headed, if it is still settling from being let go: that is where it belongs.
        let current = m.mode == .springing ? frame(item, center: m.target, size: m.targetSize) : frame(item, center: m.center, size: m.size)
        let target: StageFrame
        if let restore {
            target = restore
            if item == .panel { layout.restorePanel = nil } else { layout.restorePresenter = nil }
            events.append(.maximised(item, false))
        } else {
            target = item == .panel ? StageGeometry.maximisedPanel(aspect: input.aspect, in: picture)
                : StageGeometry.maximisedPresenter(bubble: layout.showsBubble)
            if item == .panel { layout.restorePanel = current } else { layout.restorePresenter = current }
            events.append(.maximised(item, true))
        }
        m.velocity = .zero
        m.spring(to: StageGeometry.point(target.center, in: picture), size: StageLayout.clamp(target.size, sizeRange(item)), with: .zoom)
        motions[item] = m
        pulseAge = 0
        chromeItem = item
        lingerSelected = 0.8
    }

    // MARK: Mouse and trackpad

    private mutating func handle(_ event: StagePointerEvent, input: StageControlInput, events: inout [StageEvent]) {
        let pic = picture
        let px = { (p: CGPoint) in StageGeometry.point(p, in: pic) }
        let l = currentLayout()
        func hit(_ p: CGPoint) -> StageItem? {
            StageGeometry.item(at: px(p), layout: l, aspect: input.aspect, anchor: input.anchor)
        }
        switch event {
        case .hover(let p):
            pointerHover = p.map(px)
        case .down(let p):
            if case .hand? = grab?.holder { return }
            let at = px(p)
            // A corner handle of the item showing its chrome resizes it.
            if let item = chromeItem, selected.value > 0.3, let m = motions[item],
               quad(item, layout: l, input: input, lift: 0).contains(where: { HandState.distance($0, at) < 16 }) {
                var held = m
                held.hold()
                motions[item] = held
                grab = Grab(item: item, holder: .handle, offset: .zero, startedAt: time, startSize: m.size,
                            handleDistance: max(10, HandState.distance(at, m.center)))
                events.append(.resizing(item))
                return
            }
            guard let item = hit(p), var m = motions[item] else { return }
            m.hold()
            motions[item] = m
            grab = Grab(item: item, holder: .pointer, offset: CGVector(dx: m.center.x - at.x, dy: m.center.y - at.y), startedAt: time,
                        startCenter: m.center, startSize: m.size)
            pulseAge = 0
            chromeItem = item
            events.append(.grabbed(item, byHand: false))
        case .drag(let p):
            guard let g = grab, var m = motions[g.item] else { return }
            let at = px(p)
            switch g.holder {
            case .pointer:
                m.follow(CGPoint(x: at.x + g.offset.dx, y: at.y + g.offset.dy), size: m.size)
            case .handle:
                let size = StageLayout.clamp(g.startSize * HandState.distance(at, m.center) / g.handleDistance, sizeRange(g.item))
                m.follow(m.center, size: size)
                lastStretch = nil
            case .hand:
                return
            }
            motions[g.item] = m
        case .up:
            guard let g = grab, g.holder == .pointer || g.holder == .handle else { return }
            release(velocity: g.holder == .handle ? .zero : (motions[g.item]?.velocity ?? .zero), input: input, events: &events)
        case .magnify(let amount, let p):
            resize(by: 1 + amount, at: p, input: input, hit: hit)
        case .scroll(let delta, let p):
            resize(by: exp(delta * 0.006), at: p, input: input, hit: hit)
        case .doubleClick(let p):
            if let item = hit(p) { toggleMaximise(item, input: input, events: &events) }
        }
    }

    private mutating func resize(by factor: Double, at p: CGPoint, input: StageControlInput, hit: (CGPoint) -> StageItem?) {
        guard factor.isFinite, factor > 0 else { return }
        guard let item = grab?.item ?? hit(p) ?? layout.handItem, var m = motions[item] else { return }
        let base = m.mode == .springing ? m.targetSize : m.size
        let size = StageLayout.clamp(base * factor, sizeRange(item))
        if m.mode == .held {
            m.follow(m.center, size: size)
        } else {
            let (target, _) = settled(item, center: m.mode == .springing ? m.target : m.center, size: size, snap: false, input: input)
            m.spring(to: target, size: size, with: .follow)
        }
        motions[item] = m
        chromeItem = item
        lingerSelected = 0.8
    }

    // MARK: The preview's chrome

    private func percent(_ item: StageItem, _ size: Double) -> String { "\(Int((size * 100).rounded()))%" }

    private mutating func makeOverlay(_ l: StageLayout, live: StageLive, input: StageControlInput, dt: Double) -> StageOverlayState {
        var state = StageOverlayState()
        let handItem = layout.handControl ? layout.handItem : nil

        // Cursors.
        var bestProximity = 0.0, bestCloseness = 0.0, arming = 0.0
        var focus: StageItem? = grab?.item ?? chromeItem
        if let item = handItem {
            let box = StageGeometry.bounds(of: quad(item, layout: l, input: input, lift: live.lift(of: item)))
            for (id, var t) in tracks {
                let reach = max(48, t.size * 0.8)
                let d = distance(from: t.point, to: box)
                let proximity = t.eligible ? 1 - min(1, max(0, (d - reach) / (reach * 1.4))) : 0
                let holding = grab?.holder == .hand(id) || grab?.second == id
                t.alpha.approach(holding ? 1 : (t.eligible ? 0.5 + 0.5 * proximity : 0), dt: dt)
                tracks[id] = t
                if proximity > bestProximity { bestProximity = proximity; bestCloseness = t.closeness.value; focus = item }
                var progress = 0.0
                if t.closed, !t.disqualified, t.nearAtClose == item, !holding {
                    progress = min(1, t.closedFor / (grab == nil ? holdNeeded(input) : Self.secondHandHold))
                    arming = max(arming, progress)
                }
                guard t.alpha.value > 0.01 else { continue }
                let phase: StageOverlayState.Cursor.Phase = holding ? .holding : progress > 0 ? .arming(progress) : proximity > 0.5 ? .hovering : .free
                state.cursors.append(.init(point: t.point, closeness: t.closeness.value, phase: phase,
                                           trail: t.trail.map(\.point), alpha: t.alpha.value))
            }
            state.cursors.sort { $0.point.x < $1.point.x }
        }

        // The ring and the selection around the item.
        var mouseOver = 0.0
        if let p = pointerHover, let item = StageGeometry.item(at: p, layout: l, aspect: input.aspect, anchor: input.anchor) {
            mouseOver = 1
            if grab == nil { focus = item }
        }
        lingerSelected = max(0, lingerSelected - dt)
        hover.approach(max(bestProximity, mouseOver * 0.7, grab != nil ? 1 : 0), dt: dt)
        tighten.approach(grab != nil ? 1 : bestCloseness, dt: dt)
        selected.approach(grab != nil || lingerSelected > 0 ? 1 : 0, dt: dt)
        if let f = focus { chromeItem = f }
        if let p = pulseAge { pulseAge = p + dt > 0.5 ? nil : p + dt }

        if let item = chromeItem, max(hover.value, selected.value, arming) > 0.01 {
            let q = quad(item, layout: l, input: input, lift: live.lift(of: item))
            let radius: Double
            if item == .panel {
                radius = StageGeometry.cornerRadius(roundness: l.roundness, height: Double(StageGeometry.bounds(of: q).height))
            } else if l.showsBubble {
                radius = l.presenterStyle == .circle ? Double(StageGeometry.bounds(of: q).width) / 2 : Double(StageGeometry.bounds(of: q).width) * 0.24
            } else {
                radius = 18
            }
            state.item = .init(quad: q, cornerRadius: radius, hover: hover.value, tighten: tighten.value, arming: arming,
                               selected: selected.value, pulse: pulseAge.map { $0 / 0.5 },
                               // While two hands stretch it, the size rides on the stretch line instead.
                               readout: selected.value > 0.05 && grab?.second == nil ? percent(item, l.frame(of: item).size) : nil,
                               showsHandles: selected.value > 0.05)
            lastChromeQuad = q
        }

        // Guides: a faint preview of where a held item would settle, and a flash when it does.
        flashes = flashes.map { ($0.guide, $0.age + dt) }.filter { $0.age < 0.7 }
        for f in flashes {
            let k = 1 - f.age / 0.7
            state.guides.append(.init(guide: f.guide, alpha: k * k))
        }
        if let g = grab, l.snapping, let m = motions[g.item] {
            let (_, near) = settled(g.item, center: m.center, size: m.size, snap: true, input: input)
            for guide in near where !state.guides.contains(where: { $0.guide == guide }) {
                state.guides.append(.init(guide: guide, alpha: 0.32 * selected.value))
            }
        }

        // The stretch line between two pinching hands.
        let resizing = grab?.second != nil
        stretchAlpha.approach(resizing ? 1 : 0, dt: dt)
        if !resizing, let g = grab, case .hand = g.holder { lastStretch = nil }
        if var s = lastStretch, stretchAlpha.value > 0.01 {
            s.alpha = stretchAlpha.value
            if let g = grab, g.second == nil { s.label = percent(g.item, l.frame(of: g.item).size) }
            state.stretch = s
        }
        return state
    }
}
