import CoreGraphics
import Foundation

/// Reads both fists and the face and decides the form.
///
/// Hold both fists up and still and a charge fills; at full, the form steps up one level with a flash, and if the fists are still held the
/// next charge starts at once, up to the top form, where it holds. Opening your mouth wide while you hold them (the scream) fills it about
/// 1.6 times faster. Both open palms held still, low and apart, for a moment calm you back down to base.
///
/// Nothing here trusts one frame. Poses come from the gesture recogniser's steady reading; a hand the tracker loses for a moment, or a
/// fist it misreads for a frame or two, keeps the charge instead of draining it; and fists that are moving (waving, gesturing, crossing
/// the picture) never fill it. Without a face nothing charges, and a face lost for five seconds drops you back to base without a word.
final class SaiyanTransformation {
    // MARK: Tuning

    /// Seconds of held fists for the first step (base to Super Saiyan), and for every step after it.
    static let firstStep = 0.8
    static let laterStep = 1.4
    /// How much faster the charge fills while you scream.
    static let screamBoost = 1.6
    /// `FaceState.mouthOpen` over this is a scream; it ends again under `screamOff`, so a mouth hovering at the edge does not flicker.
    static let screamOn = 0.55
    static let screamOff = 0.45
    /// A hand moving slower than this, in palm lengths a second, is held still: the charge fills. Up to `holdSpeed` it keeps the charge
    /// without filling it; faster, the pose is let go. The speed is the palm's velocity averaged over about a tenth of a second, so the
    /// trembling of tensed fists cancels out and a hand drifting across the picture does not.
    static let stillSpeed = 2.0
    static let holdSpeed = 3.2
    /// Both fists must have been still this long before the charge starts filling: a pair of fists swinging past each other stops for an
    /// instant at each end of the swing, and that is not a power-up.
    static let stillFor = 0.2
    /// Fists lost for less than this keep the charge (a tracker dropout, a misread frame); after it the charge drains over `drainSeconds`.
    static let grace = 0.25
    static let drainSeconds = 0.5
    /// After any change no move may begin from the same hands for this long.
    static let claimAfterChange = 0.35
    /// Open palms held this long, below the chin and at least `calmApart` palm lengths apart, calm you down to base. (Final Flash holds
    /// open palms close together at chest height, so the two never meet.)
    static let calmSeconds = 0.8
    static let calmApart = 2.5
    /// How far below the mouth the chin line is, in eye spacings (as `HeadwearFrame.chinY` has it).
    static let chinBelowMouth = 0.72
    /// A face seen within this long still counts for charging, so a head thrown back in a scream does not stop it.
    static let faceRecent = 0.6
    /// Seconds for a change to settle, for the strength to ease to the new form's, and for the flash to fade.
    static let transitionSeconds = 0.7
    static let levelSeconds = 0.6
    static let flashSeconds = 0.6
    /// How bright the flash of calming down is, against a step up's 1.
    static let calmFlash = 0.35
    /// The face lost this long drops you back to base, silently. Presence fades over `presenceFade` once it is lost and comes back
    /// over `presenceRise`.
    static let forgetSeconds = 5.0
    static let presenceFade = 0.4
    static let presenceRise = 0.25
    /// How long the "<form>!" line stays up after a step up.
    static let announceSeconds = 0.9

    /// The status line in base when nothing is happening. The lens shows it itself (with a tip about the moves), so `status` is nil then.
    static let idleLine = "Hold both fists up to power up"

    // MARK: State

    private(set) var state = SaiyanBodyState()

    var form: SaiyanForm { state.form }

    /// Both fists are held, a power-up is under way, or the form has only just changed: no move may begin.
    var isClaiming: Bool { fistsHeld || state.charge > 0.001 || state.sinceChange < Self.claimAfterChange }

    /// Both hands read as fists this frame (or a moment ago, through a dropout).
    private(set) var fistsHeld = false
    /// 0...1 how far through calming down the open palms are.
    var calming: Double { min(1, calmFor / Self.calmSeconds) }
    /// How many times the form has changed, up or down. For tests.
    private(set) var changes = 0

    private var lostFor = 0.0
    private var stillTime = 0.0
    private var calmFor = 0.0
    private var calmLost = 0.0
    /// No face has been seen yet: nothing charges until one is.
    private var faceLostFor = SaiyanTransformation.forgetSeconds
    private var screamLatch = false
    private var flashPeak = 1.0
    private var lastWasUp = true
    /// Each hand's palm velocity, averaged, by hand id.
    private var velocity: [Int: CGVector] = [:]
    private var lastPalm: [Int: CGPoint] = [:]

    init() {}

    func reset() {
        state = SaiyanBodyState()
        fistsHeld = false
        lostFor = 0; stillTime = 0; calmFor = 0; calmLost = 0; faceLostFor = Self.forgetSeconds
        screamLatch = false
        velocity.removeAll()
        lastPalm.removeAll()
        changes = 0
    }

    /// One line for the status bar while powering up, just changed, at full power or calming down; nil otherwise.
    var status: LensStatus? {
        if !lastWasUp, state.sinceChange < Self.announceSeconds { return LensStatus("Calming down") }
        if calmFor > 0.1, !state.form.isBase { return LensStatus("Calming down") }
        if lastWasUp, changes > 0, state.sinceChange < Self.announceSeconds {
            let detail = state.form.next == nil ? "Both open palms, low and apart, to calm down" : "Keep holding to go further"
            return LensStatus("\(state.form.title)!", detail: detail)
        }
        if fistsHeld, let next = state.form.next, state.charge > 0.02 {
            return LensStatus("Powering up... \(next.title)", detail: state.screaming ? nil : "Open your mouth wide to go faster")
        }
        if fistsHeld, state.form.next == nil { return LensStatus("Full power", detail: "Both open palms, low and apart, to calm down") }
        return nil
    }

    // MARK: Frame

    /// `gestures` has already been updated for this frame's hands.
    func update(hands: [HandState], gestures: HandGestureRecognizer, face: FaceState?, dt rawDt: Double, time: Double) {
        let dt = min(0.1, max(0, rawDt))
        state.time = time
        steady(hands, dt: dt)

        // The face: presence follows it, and losing it for long enough forgets the form.
        if face != nil {
            faceLostFor = 0
            state.presence = min(1, state.presence + dt / Self.presenceRise)
        } else {
            faceLostFor += dt
            state.presence = max(0, state.presence - dt / Self.presenceFade)
        }
        if faceLostFor >= Self.forgetSeconds, state.form != .base || state.charge > 0 { forget() }

        // The clocks of the latest change.
        state.sinceChange += dt
        state.transition = min(1, state.transition + dt / Self.transitionSeconds)
        state.flash = max(0, state.flash - flashPeak * dt / Self.flashSeconds)
        state.level += (state.form.power - state.level) * (1 - exp(-dt / (Self.levelSeconds / 3)))
        if abs(state.level - state.form.power) < 1e-4 { state.level = state.form.power }

        let pair = Array(hands.prefix(2))
        let two = pair.count == 2
        powerUp(pair, two: two, gestures: gestures, face: face, dt: dt)
        calmDown(pair, two: two, gestures: gestures, face: face, dt: dt)
    }

    private func powerUp(_ pair: [HandState], two: Bool, gestures: HandGestureRecognizer, face: FaceState?, dt: Double) {
        // Steady fists fill the charge; a fist the recogniser has not confirmed yet (just back from a dropout) or one drifting a little keeps it.
        let steadyFists = two && pair.allSatisfy { gestures.pose(of: $0.id) == .fist }
        let looseFists = two && pair.allSatisfy { gestures.pose(of: $0.id) == .fist || $0.gesturePose == .fist }
        let still = pair.allSatisfy { speed($0) < Self.stillSpeed && $0.unseenFor <= 0 }
        let calm = pair.allSatisfy { speed($0) < Self.holdSpeed }
        fistsHeld = looseFists
        stillTime = two && still ? stillTime + dt : 0
        let filling = steadyFists && stillTime >= Self.stillFor - 1e-9 && faceLostFor < Self.faceRecent

        if fistsHeld, let face {
            if face.mouthOpen > Self.screamOn { screamLatch = true } else if face.mouthOpen < Self.screamOff { screamLatch = false }
        } else if !fistsHeld {
            screamLatch = false
        }
        state.screaming = screamLatch && filling && state.form.next != nil

        if filling {
            lostFor = 0
            guard let next = state.form.next else {
                // At the top: full power, held, never wrapping round.
                state.charge = 0
                return
            }
            let seconds = state.form.isBase ? Self.firstStep : Self.laterStep
            state.charge += dt / seconds * (state.screaming ? Self.screamBoost : 1)
            if state.charge >= 1 {
                change(to: next, up: true)
                state.charge = 0
            }
        } else if looseFists && calm {
            lostFor = 0
        } else {
            lostFor += dt
            if lostFor > Self.grace { state.charge = max(0, state.charge - dt / Self.drainSeconds) }
        }
    }

    private func calmDown(_ pair: [HandState], two: Bool, gestures: HandGestureRecognizer, face: FaceState?, dt: Double) {
        guard !state.form.isBase, !fistsHeld, let face else {
            calmFor = 0
            return
        }
        let open = two && pair.allSatisfy { gestures.pose(of: $0.id) == .openPalm }
        let looseOpen = two && pair.allSatisfy { gestures.pose(of: $0.id) == .openPalm || $0.gesturePose == .openPalm }
        let still = pair.allSatisfy { speed($0) < Self.stillSpeed }
        let zone = two && inCalmZone(pair[0], pair[1], face)
        if open && still && zone {
            calmFor += dt
            calmLost = 0
        } else if looseOpen && zone && calmFor > 0 {
            calmLost = 0
        } else {
            calmLost += dt
            if calmLost > Self.grace { calmFor = 0 }
        }
        if calmFor >= Self.calmSeconds {
            calmFor = 0
            change(to: .base, up: false)
        }
    }

    /// Both palms below the chin line and well apart: hands lowered and opened out, the opposite of a power-up.
    func inCalmZone(_ a: HandState, _ b: HandState, _ face: FaceState) -> Bool {
        let chin = SaiyanZones.local(face.mouth, face).y - Self.chinBelowMouth
        let pa = SaiyanZones.palm(a, face), pb = SaiyanZones.palm(b, face)
        guard pa.y < chin, pb.y < chin else { return false }
        return HandState.distance(a.palm, b.palm) >= max(a.size, b.size) * Self.calmApart
    }

    private func change(to form: SaiyanForm, up: Bool) {
        state.previousForm = state.form
        state.form = form
        state.transition = 0
        state.sinceChange = 0
        flashPeak = up ? 1 : Self.calmFlash
        state.flash = flashPeak
        lastWasUp = up
        changes += 1
    }

    /// Back to base with no flash and nothing to see: the face has been gone a long while.
    private func forget() {
        let time = state.time, presence = state.presence
        state = SaiyanBodyState()
        state.time = time
        state.presence = presence
        calmFor = 0
        lostFor = 0
    }

    // MARK: Hands

    /// Averages each hand's palm velocity over about a tenth of a second, and forgets hands that have gone. The tracker's own velocity is
    /// used, or how far the palm moved since the last frame when that is faster (a hand handed in without one still counts as moving).
    private func steady(_ hands: [HandState], dt: Double) {
        let k = 1 - exp(-dt / 0.1)
        for hand in hands {
            var now = hand.velocity
            if let before = lastPalm[hand.id], dt > 1e-4 {
                let moved = CGVector(dx: (hand.palm.x - before.x) / dt, dy: (hand.palm.y - before.y) / dt)
                if hypot(moved.dx, moved.dy) > hypot(now.dx, now.dy) { now = moved }
            }
            lastPalm[hand.id] = hand.palm
            let v = velocity[hand.id] ?? now
            velocity[hand.id] = CGVector(dx: v.dx + (now.dx - v.dx) * k, dy: v.dy + (now.dy - v.dy) * k)
        }
        let seen = Set(hands.map(\.id))
        for id in Array(velocity.keys) where !seen.contains(id) {
            velocity[id] = nil
            lastPalm[id] = nil
        }
    }

    /// How fast a hand is moving, in palm lengths a second.
    private func speed(_ hand: HandState) -> Double {
        let v = velocity[hand.id] ?? hand.velocity
        return hypot(Double(v.dx), Double(v.dy)) / hand.size
    }
}
