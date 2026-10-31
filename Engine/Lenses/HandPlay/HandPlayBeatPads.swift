import AppKit
import CoreGraphics
import simd

/// Beat Pads: a rhythm game with no sound. Four glowing drum pads sit along the bottom of the picture. For every note a ring appears round
/// a pad and closes in on it in time with the beat; tap the pad (a fingertip or the flat of your hand dipping into it) just as the ring
/// meets the edge. Right on time is PERFECT, near enough is GOOD, and a run of hits builds a multiplier. The beat itself shows in the
/// row of lights at the top and in the pads, which pulse on every beat. The song lasts about a minute.
///
/// A tap is a hand part coming into a pad (with a wider edge for leaving than for entering, so a hand resting on the rim does not
/// drum), or a quick jab that crosses a pad between two frames. Tracking runs a little behind the hand, so taps are judged a touch early.
struct HandPlayBeatPads: Game {
    static let title = "Beat Pads"
    static let hint = "Tap each pad just as its ring closes in."
    static let presenceHint = "Hold up your hand to play"
    static let onboarding = ["Tap a pad just as its ring closes in", "Keep hitting the beat to build a combo"]
    static let accent = SIMD3<Double>(1.0, 0.58, 0.82)
    static let icon = GameUIIcon.hand(.point)

    static let beatsPerMinute = 100.0
    static var beat: Double { 60 / beatsPerMinute }
    /// How long a ring takes to close in.
    static let approach = 1.35
    static let perfectWindow = 0.1
    static let goodWindow = 0.22
    /// How far behind the hand tracking runs, taken off every tap.
    static let latency = 0.05
    static let padRadius = 72.0

    /// The four pads' colours, left to right, and the light of the HUD.
    enum Colours {
        static let pads: [HandPlayTone] = [HandPlayPalette.coral, HandPlayPalette.gold, HandPlayPalette.mint, HandPlayPalette.sky]
        /// The unlit rubber of each pad: a deep shade of its own hue, not a muddy darkening.
        static let faces: [HandPlayTone] = [HandPlayTone(0.44, 0.1, 0.17), HandPlayTone(0.5, 0.27, 0.04), HandPlayTone(0.04, 0.33, 0.3),
                                            HandPlayTone(0.06, 0.2, 0.48)]
        static let bezel = HandPlayTone(0.2, 0.19, 0.28)
        static let perfect = HandPlayPalette.gold
        static let good = HandPlayPalette.mint
        static let miss = HandPlayTone(0.86, 0.5, 0.55)
    }

    enum Judgement: Equatable { case perfect, good, miss }

    struct Note: Equatable {
        var pad: Int
        /// When the ring meets the pad, in seconds from the start.
        var time: Double
        var judgement: Judgement? = nil
        var judgedAt = 0.0
    }

    struct PadLight: Equatable {
        /// 1 the moment the pad is struck, fading.
        var flash = 0.0
        var judgement: Judgement? = nil
        /// Seconds since the last shock ring started, or nil.
        var ring: Double? = nil
    }

    let size: CGSize
    let pads: [CGPoint]
    private(set) var notes: [Note]
    private(set) var score = 0
    private(set) var elapsed = 0.0
    private(set) var combo = 0
    private(set) var bestCombo = 0
    private(set) var perfects = 0
    private(set) var goods = 0
    private(set) var misses = 0
    private(set) var taps = 0
    private(set) var lights: [PadLight]
    private var touches = HandPlayTouches()
    private var inside = Set<InsideKey>()
    /// When each hand was last seen, so a hand that drops out for a moment while resting in a pad does not strike it again on its return.
    private var lastSeen: [Int: Double] = [:]
    private var lastTap: [Double]
    private var fx: SplitMix64
    private var particles = ParticleSystem(capacity: 300)
    private var floaters: [HandPlayFloater] = []
    private var heldTips: [HandPlayTouches.Touch] = []

    private struct InsideKey: Hashable { var hand: Int; var slot: Int; var pad: Int }

    /// When the song is done: a little after the last note.
    var songLength: Double { (notes.map(\.time).max() ?? 0) + 1.6 }
    var isOver: Bool { elapsed >= songLength }
    var multiplier: Int { 1 + min(3, combo / 8) }
    /// How well the song was played, 0...1: a perfect counts in full and a good counts for most of one.
    var accuracy: Double {
        let judged = perfects + goods + misses
        return judged == 0 ? 0 : (Double(perfects) + 0.6 * Double(goods)) / Double(judged)
    }
    var grade: String {
        switch accuracy {
        case 0.95...: return "S"
        case 0.85..<0.95: return "A"
        case 0.7..<0.85: return "B"
        case 0.5..<0.7: return "C"
        default: return "D"
        }
    }
    var summary: String {
        let left = "\(Int(max(0, songLength - elapsed).rounded(.up)))s"
        return multiplier > 1 ? "x\(multiplier) · \(left)" : left
    }
    private var unit: Double { Double(size.width) / 1280 }

    var readout: GameUIReadout {
        GameUIReadout(score: score, time: (max(0, songLength - elapsed), songLength), combo: multiplier > 1 ? multiplier : 0)
    }

    /// The song's grade and how much of it was on the beat. A top grade counts as a win.
    var result: GameUIResult {
        let percent = Int((accuracy * 100).rounded())
        let line: String
        switch grade {
        case "S": line = "Grade S: \(percent)% on the beat. Flawless!"
        case "A": line = "Grade A: \(percent)% on the beat"
        case "B": line = "Grade B: \(percent)% on the beat"
        default: line = "Grade \(grade): watch the rings and tap as they close"
        }
        return GameUIResult(headline: "Song complete", line: line,
                            stats: [("\(perfects)", "perfect"), ("\(goods)", "good"), ("\(bestCombo)", "best combo")],
                            kind: grade == "S" || grade == "A" ? .won : .timeUp)
    }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        let w = Double(size.width), h = Double(size.height)
        pads = [(0.17, 0.33), (0.39, 0.24), (0.61, 0.24), (0.83, 0.33)].map { CGPoint(x: w * $0.0, y: h * $0.1) }
        var rng = SplitMix64(seed: seed)
        notes = Self.chart(&rng)
        lights = Array(repeating: PadLight(), count: 4)
        lastTap = Array(repeating: -9, count: 4)
        fx = SplitMix64(seed: seed ^ 0xBEA7_5)
        particles.gravity = SIMD2(0, -500)
    }

    /// The song: an easy start with a note every other beat, then every beat, then off-beats and both hands at once, and a quick roll
    /// to finish. Never the same pad twice within half a second, so a hand always has time to lift and come back.
    static func chart(_ rng: inout SplitMix64) -> [Note] {
        var out: [Note] = []
        let walks: [[Int]] = [[0, 1, 2, 3], [3, 2, 1, 0], [0, 2, 1, 3], [3, 1, 2, 0], [1, 0, 2, 3], [2, 3, 1, 0], [0, 3, 1, 2]]
        func add(_ pad: Int, _ beatNumber: Double) {
            let time = beatNumber * beat
            guard !out.contains(where: { $0.pad == pad && abs($0.time - time) < 0.45 }) else { return }
            out.append(Note(pad: pad, time: time))
        }
        func walk() -> [Int] { walks[Int.random(in: 0..<walks.count, using: &rng)] }

        // Warm up: every other beat.
        var b = 4.0
        while b < 20 { let w = walk(); for p in w where b < 20 { add(p, b); b += 2 } }
        // Every beat.
        while b < 52 { let w = walk(); for p in w where b < 52 { add(p, b); b += 1 } }
        // Every beat, with off-beats between and a double at the top of each bar.
        while b < 84 {
            let w = walk()
            for (k, p) in w.enumerated() where b < 84 {
                add(p, b)
                if k == 0 && Int(b) % 8 == 4 { add(3 - p, b) }
                if k == 2 && Bool.random(using: &rng) { add((p + 2) % 4, b + 0.5) }
                b += 1
            }
        }
        // The roll, then both ends together to finish.
        let roll = [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0, 1]
        for (k, p) in roll.enumerated() { add(p, 84 + Double(k) * 0.5) }
        add(0, 92)
        add(3, 92)
        return out.sorted { $0.time < $1.time }
    }

    // MARK: Step

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.25)
        guard !isOver else { return }
        elapsed += dt
        for i in lights.indices {
            lights[i].flash = max(0, lights[i].flash - dt / 0.3)
            if let r = lights[i].ring { lights[i].ring = r + dt > 0.4 ? nil : r + dt }
        }

        let found = touches.update(world.hands, now: elapsed)
        heldTips = found
        detectTaps(found)

        // Notes that went by untouched.
        for i in notes.indices where notes[i].judgement == nil && elapsed - Self.latency > notes[i].time + Self.goodWindow {
            notes[i].judgement = .miss
            notes[i].judgedAt = elapsed
            misses += 1
            combo = 0
            lights[notes[i].pad].judgement = .miss
            floaters.append(HandPlayFloater(text: "MISS", origin: pads[notes[i].pad].handPlayVector + SIMD2(0, (Self.padRadius + 30) * unit),
                                            tone: Colours.miss, size: 34, life: 0.7, rise: -30))
        }

        particles.step(dt)
        for i in floaters.indices { floaters[i].advance(dt) }
        floaters.removeAll(where: \.isDone)

        if isOver {
            particles.removeAll()
            floaters.removeAll()
        }
    }

    private mutating func detectTaps(_ found: [HandPlayTouches.Touch]) {
        let r = Self.padRadius * unit
        for touch in found { lastSeen[touch.hand] = elapsed }
        let now = elapsed
        lastSeen = lastSeen.filter { now - $0.value < HandPlayRoster.dropout }
        let seen = lastSeen
        inside = inside.filter { seen[$0.hand] != nil }
        for touch in found {
            let enter = r + touch.radius * 0.5
            let leave = enter * 1.3 + 10 * unit
            for (index, pad) in pads.enumerated() {
                let key = InsideKey(hand: touch.hand, slot: touch.slot, pad: index)
                let distance = HandState.distance(touch.position, pad)
                if inside.contains(key) {
                    if distance > leave { inside.remove(key) }
                    continue
                }
                if distance < enter {
                    inside.insert(key)
                    tap(index)
                } else if touch.isQuick && HandGeometry.segment(from: touch.previous.handPlayVector, to: touch.position.handPlayVector,
                                                                hits: pad.handPlayVector, radius: enter) {
                    tap(index)
                }
            }
        }
    }

    /// A pad was struck: judge the nearest note on it, if one is close enough in time.
    private mutating func tap(_ pad: Int) {
        guard elapsed - lastTap[pad] > 0.16 else { return }
        lastTap[pad] = elapsed
        taps += 1
        lights[pad].flash = 1
        lights[pad].ring = 0
        let at = elapsed - Self.latency
        let candidates = notes.indices.filter { notes[$0].pad == pad && notes[$0].judgement == nil && abs(notes[$0].time - at) <= Self.goodWindow }
        guard let i = candidates.min(by: { abs(notes[$0].time - at) < abs(notes[$1].time - at) }) else {
            lights[pad].judgement = nil
            return
        }
        let judgement: Judgement = abs(notes[i].time - at) <= Self.perfectWindow ? .perfect : .good
        notes[i].judgement = judgement
        notes[i].judgedAt = elapsed
        lights[pad].judgement = judgement
        combo += 1
        bestCombo = max(bestCombo, combo)
        let points = (judgement == .perfect ? 3 : 1) * multiplier
        score += points
        if judgement == .perfect { perfects += 1 } else { goods += 1 }
        let tone = Colours.pads[pad]
        floaters.append(HandPlayFloater(text: judgement == .perfect ? "PERFECT" : "GOOD", origin: pads[pad].handPlayVector + SIMD2(0, (Self.padRadius + 34) * unit),
                                        tone: judgement == .perfect ? Colours.perfect : Colours.good, size: judgement == .perfect ? 40 : 34, life: 0.75, rise: 60))
        for _ in 0..<(judgement == .perfect ? 16 : 9) {
            let a = Double.random(in: 0..<(2 * .pi), using: &fx)
            let from = pads[pad].handPlayVector + SIMD2(cos(a), sin(a)) * Self.padRadius * 0.8 * unit
            particles.emit(Particle(position: from, velocity: SIMD2(cos(a), sin(a) + 0.6) * Double.random(in: 140...380, using: &fx),
                                    life: Double.random(in: 0.3...0.6, using: &fx), size: Double.random(in: 3...7, using: &fx), hue: Double(pad),
                                    kind: tone == HandPlayPalette.gold ? 1 : 0))
        }
    }

    // MARK: Test hooks

    /// Replaces the song with these notes (pad, time).
    mutating func setNotes(_ list: [(Int, Double)]) { notes = list.map { Note(pad: $0.0, time: $0.1) }.sorted { $0.time < $1.time } }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        let beatPhase = (elapsed / Self.beat).truncatingRemainder(dividingBy: 1)
        let pulse = isOver ? 0 : exp(-beatPhase * 7)
        for (i, p) in pads.enumerated() { drawPad(ctx, i, at: p, pulse: pulse) }
        guard !isOver else { return }
        drawRings(ctx)
        for tip in heldTips where !tip.isPalm && tip.slot != 1 {
            // A small light on each fingertip, so you can see what will strike.
            HandPlayDraw.glow(ctx, at: tip.position, radius: tip.radius * 0.9, tone: HandPlayPalette.cream, alpha: 0.35)
        }
        for p in particles.particles {
            let t = p.progress
            let tone = Colours.pads[min(3, max(0, Int(p.hue)))].lighter(0.3)
            ctx.fillCircle(center: p.position.handPlayPoint, radius: CGFloat(p.size * unit * (1 - 0.6 * t)), color: tone.cg(1 - t))
        }
        for f in floaters { f.draw(ctx) }
        drawBeatBar(ctx, beatPhase: beatPhase)
    }

    private func drawPad(_ ctx: CGContext, _ index: Int, at p: CGPoint, pulse: Double) {
        let u = CGFloat(unit)
        let tone = Colours.pads[index]
        let light = lights[index]
        let r = Self.padRadius * unit
        let dim = isOver ? 0.8 : 1.0
        // Pads that have a note coming glow a little in anticipation.
        let next = notes.filter { $0.pad == index && $0.judgement == nil && $0.time > elapsed - 0.1 }.map(\.time).min() ?? .infinity
        let anticipation = HandPlayEase.clamp(1 - (next - elapsed) / Self.approach)
        HandPlayDraw.shadow(ctx, at: CGPoint(x: p.x + 8 * u, y: p.y - 12 * u), width: r * 2.5, height: r * 1.2, alpha: 0.45 * dim)
        // The beat shows as a breath of light round every pad; a strike pops the pad itself for a moment.
        HandPlayDraw.glow(ctx, at: p, radius: r * (1.5 + 0.5 * light.flash), tone: tone,
                          alpha: (0.16 + 0.12 * pulse + 0.25 * anticipation + 0.6 * light.flash) * dim)
        let scale = CGFloat(1 + 0.08 * light.flash)
        let face = Colours.faces[index]
        HandPlayDraw.stamp(ctx, HandPlayBeatPadsArt.pad(tone, face: face, lit: false, unit: u), at: p, scale: scale, alpha: CGFloat(dim))
        if light.flash > 0 {
            HandPlayDraw.stamp(ctx, HandPlayBeatPadsArt.pad(tone, face: face, lit: true, unit: u), at: p, scale: scale,
                               alpha: CGFloat(HandPlayEase.outCubic(light.flash)))
        }
        if let age = light.ring {
            let t = age / 0.4
            let ringTone = light.judgement == .perfect ? Colours.perfect : light.judgement == .good ? Colours.good : HandPlayPalette.cream
            HandPlayDraw.ring(ctx, at: p, radius: r * (1 + 0.8 * HandPlayEase.outCubic(t)), width: 8 * unit * (1 - t), tone: ringTone,
                              alpha: (light.judgement == nil ? 0.4 : 0.95) * (1 - t))
        }
    }

    /// The closing rings: one per note on its way, shrinking onto its pad and brightening as it comes.
    private func drawRings(_ ctx: CGContext) {
        let r = Self.padRadius * unit
        for note in notes where note.judgement == nil {
            let ahead = note.time - elapsed
            guard ahead < Self.approach, ahead > -Self.goodWindow else { continue }
            let t = HandPlayEase.clamp(1 - ahead / Self.approach)
            let tone = Colours.pads[note.pad]
            let radius = r * (1 + 1.5 * (1 - t))
            let alpha = HandPlayEase.clamp(t / 0.25) * (ahead < 0 ? max(0, 1 + ahead / Self.goodWindow) : 1)
            HandPlayDraw.ring(ctx, at: pads[note.pad], radius: radius, width: (6 + 4 * t) * unit, tone: tone.lighter(0.4), alpha: 0.95 * alpha, outlined: true)
        }
    }

    /// The beat, shown at the top: four lights for the beats of the bar, the song's progress under them, and the combo.
    private func drawBeatBar(_ ctx: CGContext, beatPhase: Double) {
        let u = unit
        let w = Double(size.width), h = Double(size.height)
        let beatNumber = Int((elapsed / Self.beat).rounded(.down))
        let y = h - 50 * u
        for k in 0..<4 {
            let x = w / 2 + (Double(k) - 1.5) * 40 * u
            let on = beatNumber % 4 == k
            let flash = on ? exp(-beatPhase * 4) : 0
            let tone = k == 0 ? HandPlayPalette.gold : HandPlayPalette.cream
            if on { HandPlayDraw.glow(ctx, at: CGPoint(x: x, y: y), radius: 26 * u, tone: tone, alpha: 0.8 * flash) }
            ctx.fillCircle(center: CGPoint(x: x, y: y), radius: CGFloat((9 + 4 * flash) * u), color: HandPlayPalette.ink.cg(0.55))
            ctx.fillCircle(center: CGPoint(x: x, y: y), radius: CGFloat((7 + 4 * flash) * u), color: tone.cg(on ? 0.6 + 0.4 * flash : 0.3))
        }
        let barW = 200 * u, barH = 8 * u
        let bar = CGRect(x: w / 2 - barW / 2, y: y - 34 * u, width: barW, height: barH)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil))
        ctx.setFillColor(HandPlayPalette.ink.cg(0.5))
        ctx.fillPath()
        let done = HandPlayEase.clamp(elapsed / songLength)
        if done > 0.01 {
            ctx.addPath(CGPath(roundedRect: CGRect(x: bar.minX, y: bar.minY, width: max(barH, barW * done), height: barH), cornerWidth: barH / 2,
                               cornerHeight: barH / 2, transform: nil))
            ctx.setFillColor(HandPlayPalette.gold.cg(0.9))
            ctx.fillPath()
        }
    }
}

/// The baked pictures for Beat Pads.
enum HandPlayBeatPadsArt {
    typealias C = HandPlayBeatPads.Colours

    /// A drum pad from above: a dark metal bezel, a soft rubber face tinted in its colour with a neon ring, and a gloss on the top left.
    /// The lit version is the same pad struck: the face glowing hot from the middle.
    static func pad(_ tone: HandPlayTone, face deep: HandPlayTone, lit: Bool, unit: CGFloat) -> CGImage? {
        let r = CGFloat(HandPlayBeatPads.padRadius) * unit
        return HandPlaySprites.image("bp.pad|\(tone.key)|\(lit)|\(Int(unit * 100))", side: Int(ceil(r * 2.6))) { ctx in
            let outer = CGRect(x: -r, y: -r, width: r * 2, height: r * 2)
            let face = outer.insetBy(dx: r * 0.14, dy: r * 0.14)
            if !lit {
                ctx.saveGState()
                ctx.addEllipse(in: outer)
                ctx.clip()
                HandPlayDraw.fill(ctx, [(C.bezel.lighter(0.35), 1), (C.bezel, 1), (C.bezel.darker(0.5), 1)], from: CGPoint(x: -r * 0.7, y: r * 0.7),
                                  to: CGPoint(x: r * 0.7, y: -r * 0.7), locations: [0, 0.5, 1])
                ctx.restoreGState()
            }
            ctx.saveGState()
            ctx.addEllipse(in: face)
            ctx.clip()
            if lit {
                HandPlayDraw.radial(ctx, [(HandPlayPalette.cream, 1), (tone.lighter(0.35), 1), (tone, 1)], center: .zero, radius: r * 0.86, locations: [0, 0.4, 1])
            } else {
                HandPlayDraw.radial(ctx, [(deep.mixed(with: tone, 0.35), 1), (deep, 1), (deep.darker(0.35), 1)], center: CGPoint(x: r * 0.1, y: -r * 0.1),
                                    radius: r * 0.9, from: CGPoint(x: -r * 0.2, y: r * 0.2), locations: [0, 0.55, 1])
                // The pad's texture: fine concentric grooves.
                ctx.setStrokeColor(tone.cg(0.12))
                ctx.setLineWidth(max(1, r * 0.02))
                for k in 1...4 {
                    let inset = r * 0.14 * CGFloat(k)
                    ctx.strokeEllipse(in: face.insetBy(dx: inset, dy: inset))
                }
            }
            HandPlayDraw.radial(ctx, [(HandPlayPalette.cream, lit ? 0.4 : 0.22), (HandPlayPalette.cream, 0)], center: CGPoint(x: -r * 0.35, y: r * 0.4), radius: r * 0.55)
            ctx.restoreGState()
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: r * 0.14, color: tone.cg(0.95))
            ctx.setStrokeColor(tone.lighter(lit ? 0.6 : 0.25).cg())
            ctx.setLineWidth(r * 0.07)
            ctx.strokeEllipse(in: face.insetBy(dx: r * 0.035, dy: r * 0.035))
            ctx.restoreGState()
            if !lit {
                ctx.setStrokeColor(HandPlayPalette.cream.cg(0.45))
                ctx.setLineWidth(r * 0.035)
                ctx.setLineCap(.round)
                ctx.addArc(center: .zero, radius: r * 0.94, startAngle: 1.9, endAngle: 2.8, clockwise: false)
                ctx.strokePath()
                ctx.setStrokeColor(HandPlayPalette.ink.cg(0.7))
                ctx.setLineWidth(r * 0.03)
                ctx.strokeEllipse(in: outer.insetBy(dx: r * 0.015, dy: r * 0.015))
            }
        }
    }
}
