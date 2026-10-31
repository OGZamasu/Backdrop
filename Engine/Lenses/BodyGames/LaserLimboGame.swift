import AppKit
import CoreGraphics
import simd

/// Laser beams sweep in from the edges in waves: a bar that comes down from the top (duck under it), a blade that slides in from
/// the side to where your head is (lean away from it), and two blades that close in leaving a gap (put your head in the gap).
///
/// Every wave is planned from where your head is and how big it is when the wave starts, so the move it asks for is always one a
/// seated person can make: duck about a head's height, or lean about a head's width. Each beam first shows, as a faint dashed
/// line, exactly where it will stop. Score is seconds survived plus a bonus for each wave you clear without a scratch.
struct LaserLimboGame: Game {
    static let title = "Laser Limbo"
    static let hint = "Duck and lean so the lasers miss you!"
    static let accent = SIMD3<Double>(1.0, 0.45, 0.5)

    static let startingLives = 3
    static let graceSeconds = 1.6
    static let cleanBonus = 5
    /// How many beam samples must land on you to count, so a speck of noise at your outline cannot zap you.
    static let hitSamples = 3

    enum Axis { case horizontal, vertical }

    enum Pattern: CaseIterable, Equatable {
        /// A bar across the whole picture comes down from the top: duck.
        case duck
        /// A blade from the top slides in from one side to where your head is: lean the other way.
        case lean
        /// Two blades close in from both sides, leaving a gap beside your head: move into it.
        case gap

        var prompt: String {
            switch self {
            case .duck: return "DUCK!"
            case .lean: return "LEAN!"
            case .gap: return "FIND THE GAP!"
            }
        }
    }

    struct Beam {
        var axis: Axis
        /// Where it starts and stops: a y for a horizontal bar, an x for a vertical blade.
        var start: Double
        var end: Double
        /// The lowest point a vertical blade reaches down to. Unused for a bar, which spans the picture.
        var reach: Double
        /// Seconds of warning, harmless, before it switches on and moves.
        var telegraph: Double
        var travel: Double
        var hold: Double
        var age = 0.0
        /// Whether it has already hit the player. A beam hits you once at most: going back the way it came, it can't hit again.
        var struck = false

        var retreat: Double { travel * 0.7 }
        var life: Double { telegraph + travel + hold + retreat }
        var isHot: Bool { age >= telegraph && age < life }
        var isDone: Bool { age >= life }
        var position: Double { position(at: age) }

        func position(at t: Double) -> Double {
            if t < telegraph { return start }
            if t < telegraph + travel { return start + (end - start) * BodyEase.inOutSine((t - telegraph) / travel) }
            if t < telegraph + travel + hold { return end }
            let back = bodyClamp((t - telegraph - travel - hold) / retreat, 0, 1)
            return end + (start - end) * back * back
        }
    }

    struct Zap {
        var position: SIMD2<Double>
        var age = 0.0
    }

    let size: CGSize
    private(set) var beams: [Beam] = []
    private(set) var pattern: Pattern?
    private(set) var lives = LaserLimboGame.startingLives
    private(set) var bonus = 0
    private(set) var elapsed = 0.0
    private(set) var graceLeft = 0.0
    private(set) var hits = 0
    private(set) var waves = 0
    private(set) var cleanWaves = 0
    /// Which way to lean for the current wave: -1 left, +1 right, 0 for none.
    private(set) var leanWay = 0
    /// The player as last measured: smoothed, so one noisy frame doesn't move a wave.
    private(set) var reference: BodyFrame?
    private(set) var headX: Double?

    private var rng: SplitMix64
    private var breather = 1.4
    private var waveHit = false
    private var spawning = true
    private var sinceScan = 9.0
    private var sinceHit = 99.0
    private var flash = 0.0
    private var shake = 0.0
    private var zaps: [Zap] = []
    private var sparks = ParticleSystem(capacity: 300)
    private var floaters: [BodyFloater] = []
    private var head: CGRect?
    private var promptAge = 99.0

    var score: Int { Int(elapsed) + bonus }
    var isOver: Bool { lives <= 0 }
    var summary: String { "Lives \(lives) · Wave \(max(1, waves))" }

    var readout: GameUIReadout { GameUIReadout(score: score, lives: (max(0, lives), Self.startingLives), label: "Wave \(max(1, waves))") }

    var result: GameUIResult {
        let line: String
        switch waves {
        case ..<4: line = "Watch the warning lines, then duck or lean"
        case 4..<12: line = "You made it to wave \(waves)"
        default: line = "Bendy as a limbo champion"
        }
        return GameUIResult(headline: "Out of lives", line: line,
                            stats: [("\(waves)", "waves"), ("\(cleanWaves)", "clean"), (String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60), "survived")])
    }
    /// 0 at the start, 1 by the twelfth wave.
    var difficulty: Double { min(1, Double(max(0, waves - 1)) / 11) }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        sparks.gravity = SIMD2(0, -700)
        sparks.drag = 0.8
        BodyArtCache.warm("laser") { _ = LaserArt.emitter() }
    }

    // MARK: Rules

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = bodyClamp(dt, 0, 0.1)
        elapsed += dt
        graceLeft = max(0, graceLeft - dt)
        sinceHit += dt
        flash = max(0, flash - dt)
        shake = max(0, shake - dt)
        promptAge += dt
        look(at: world.matte, dt)

        if beams.isEmpty, spawning {
            breather -= dt
            if breather <= 0 { startWave() }
        }

        var finished = false
        for i in beams.indices {
            let before = beams[i].position
            beams[i].age += dt
            if beams[i].isHot, let matte = world.matte, check(beams[i], from: before, matte: matte) { beams[i].struck = true }
            if beams[i].isDone { finished = true }
        }
        beams.removeAll(where: \.isDone)
        if finished, beams.isEmpty, pattern != nil { endWave() }

        sparks.step(dt)
        for i in zaps.indices { zaps[i].age += dt }
        zaps.removeAll { $0.age > 0.5 }
        for i in floaters.indices { floaters[i].advance(dt) }
        floaters.removeAll { $0.isDone }
    }

    /// Notes where the player and their head are, a few times a second.
    private mutating func look(at matte: MatteQuery?, _ dt: Double) {
        sinceScan += dt
        guard sinceScan >= 0.12 else { return }
        sinceScan = 0
        let scan = BodyScan(matte: matte, size: size, step: 24)
        head = scan.headZone
        guard let frame = BodyFrame(scan: scan) else { return }
        let k = reference == nil ? 1 : 0.35
        reference = reference.map { $0.blended(toward: frame, by: k) } ?? frame
        if let zone = head {
            let x = Double(zone.midX)
            headX = headX.map { $0 + (x - $0) * k } ?? x
        }
    }

    /// Where the player is assumed to be when nobody has been seen yet.
    private var plan: (frame: BodyFrame, headX: Double) {
        let fallback = BodyFrame(left: size.width / 2 - 260, right: size.width / 2 + 260, top: size.height * 0.8, bottom: 0,
                                 headWidth: 160, shoulderY: size.height * 0.8 - 240)
        let frame = reference ?? fallback
        return (frame, headX ?? frame.centerX)
    }

    private mutating func startWave() {
        waves += 1
        waveHit = false
        promptAge = 0
        let choice: Pattern
        switch waves {
        case 1: choice = .duck
        case 2: choice = .lean
        default:
            let pool = Pattern.allCases.filter { $0 != pattern }
            choice = pool[Int.random(in: 0..<pool.count, using: &rng)]
        }
        start(choice)
    }

    /// Lays out the beams for a pattern, sized from the player's head.
    private mutating func start(_ choice: Pattern) {
        let (frame, hx) = plan
        let u = max(90, frame.headWidth)
        let d = difficulty
        let telegraph = 1.5 - 0.6 * d, travel = 1.0 - 0.35 * d, hold = 0.8 + 0.4 * d
        // Blades stop well above the shoulders, so leaning the head is enough.
        let reach = bodyClamp(frame.shoulderY + 0.6 * u, 90, size.height - 120)
        pattern = choice
        leanWay = 0
        switch choice {
        case .duck:
            // The bar settles about a head's height below the top of your head, above your shoulders.
            let end = bodyClamp(max(frame.top - 1.05 * u, frame.shoulderY + 0.55 * u), 150, size.height - 90)
            beams = [Beam(axis: .horizontal, start: size.height + 30, end: end, reach: 0, telegraph: telegraph, travel: travel * 1.2, hold: hold)]
        case .lean:
            // Come in from the side with more room behind the head, so there is always somewhere to lean to.
            let roomRight = size.width - hx, roomLeft = hx
            var from: Double = Bool.random(using: &rng) ? -1 : 1
            if roomRight < 2.2 * u { from = 1 } else if roomLeft < 2.2 * u { from = -1 }
            let end = hx - from * 0.2 * u
            leanWay = from < 0 ? 1 : -1
            beams = [Beam(axis: .vertical, start: from < 0 ? -30 : size.width + 30, end: end, reach: reach,
                          telegraph: telegraph, travel: travel, hold: hold)]
        case .gap:
            // A gap a little wider than a head, just to one side of where the head is now.
            let way: Double = Bool.random(using: &rng) ? -1 : 1
            var middle = hx + way * 0.9 * u
            if middle < 1.4 * u || middle > size.width - 1.4 * u { middle = hx - way * 0.9 * u }
            middle = bodyClamp(middle, 1.4 * u, size.width - 1.4 * u)
            let half = 0.95 * u
            leanWay = middle < hx ? -1 : 1
            beams = [Beam(axis: .vertical, start: -30, end: middle - half, reach: reach, telegraph: telegraph, travel: travel, hold: hold),
                     Beam(axis: .vertical, start: size.width + 30, end: middle + half, reach: reach, telegraph: telegraph, travel: travel, hold: hold)]
        }
    }

    private mutating func endWave() {
        if !waveHit {
            cleanWaves += 1
            bonus += Self.cleanBonus
            floaters.append(BodyFloater.placed("CLEAN +\(Self.cleanBonus)", at: SIMD2(size.width / 2, 170), size: size, color: BodyGamePalette.mint,
                                               fontSize: 54, life: 1.1, rise: 30))
        }
        pattern = nil
        breather = 0.9 - 0.4 * difficulty
    }

    /// Looks along the beam, where it is now and halfway back to where it was, for the player. True when it costs a life.
    private mutating func check(_ beam: Beam, from before: Double, matte: MatteQuery) -> Bool {
        var touching: [SIMD2<Double>] = []
        for at in [beam.position, (beam.position + before) / 2] {
            switch beam.axis {
            case .vertical:
                var y = beam.reach + 6
                while y < size.height {
                    if matte.coverage(x: at, y: y) > 0.5 { touching.append(SIMD2(at, y)) }
                    y += 12
                }
            case .horizontal:
                var x = 6.0
                while x < size.width {
                    if matte.coverage(x: x, y: at) > 0.5 { touching.append(SIMD2(x, at)) }
                    x += 12
                }
            }
            if touching.count >= Self.hitSamples { break }
        }
        guard touching.count >= Self.hitSamples else { return false }
        let spot = touching.reduce(SIMD2<Double>(0, 0), +) / Double(touching.count)
        if Int(elapsed * 30) % 3 == 0 {
            for _ in 0..<3 {
                let a = Double.random(in: 0..<(2 * .pi), using: &rng)
                sparks.emit(Particle(position: spot, velocity: SIMD2(cos(a), sin(a) * 0.8 + 0.4) * Double.random(in: 120...380, using: &rng),
                                     life: Double.random(in: 0.2...0.45, using: &rng), size: Double.random(in: 2...4, using: &rng)))
            }
        }
        guard graceLeft <= 0, !beam.struck else { return false }
        lives = max(0, lives - 1)
        hits += 1
        waveHit = true
        graceLeft = Self.graceSeconds
        sinceHit = 0
        flash = 0.5
        shake = 0.35
        zaps.append(Zap(position: spot))
        for _ in 0..<26 {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng)
            sparks.emit(Particle(position: spot, velocity: SIMD2(cos(a), sin(a)) * Double.random(in: 160...560, using: &rng),
                                 life: Double.random(in: 0.3...0.7, using: &rng), size: Double.random(in: 2.5...5.5, using: &rng), kind: 1))
        }
        floaters.append(BodyFloater.placed("ZAP!", at: spot + SIMD2(0, 60), size: size, color: BodyGamePalette.coral, fontSize: 62, avoiding: head))
        return true
    }

    // MARK: Test hooks

    /// Stops new waves from starting on their own.
    mutating func holdWaves() { spawning = false }

    /// Starts a wave of this pattern now, planned around `frame` and a head at `headAt`.
    mutating func startWave(_ choice: Pattern, around frame: BodyFrame, headAt x: Double) {
        reference = frame
        headX = x
        waves += 1
        waveHit = false
        promptAge = 0
        start(choice)
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        ctx.saveGState()
        let nudge = BodyGameHUD.shake(left: shake, total: 0.35, time: time, amplitude: 7)
        ctx.translateBy(x: nudge.width, y: nudge.height)
        for beam in beams where !beam.isHot { drawWarning(beam, in: ctx, time: time) }
        for beam in beams where beam.isHot { drawBeam(beam, in: ctx, time: time) }
        for beam in beams { drawEmitters(beam, in: ctx, time: time) }
        for zap in zaps {
            let t = zap.age / 0.5
            BodyGlow.stamp(ctx, at: CGPoint(x: zap.position.x, y: zap.position.y), radius: CGFloat(60 + 80 * t), color: BodyGamePalette.coral, alpha: 0.8 * (1 - t))
        }
        for p in sparks.particles {
            ctx.setAlpha(CGFloat(1 - p.progress))
            let colour = p.kind == 1 ? BodyGamePalette.coral.bodyShade(0.35) : CGColor(red: 1, green: 0.95, blue: 0.85, alpha: 1)
            ctx.fillCircle(center: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * (1 - 0.5 * p.progress), color: colour)
        }
        ctx.setAlpha(1)
        ctx.restoreGState()

        for floater in floaters { floater.draw(in: ctx) }
        BodyGameHUD.flash(ctx, size: size, strength: flash / 0.5 * 0.8)
        drawPrompt(in: ctx, time: time)
    }

    private func drawPrompt(in ctx: CGContext, time: Double) {
        guard !isOver, let pattern, let first = beams.first, first.age < first.telegraph + first.travel + 0.3 else { return }
        var text = pattern.prompt
        if pattern == .lean { text = leanWay < 0 ? "←  LEAN!" : "LEAN!  →" }
        let enter = BodyEase.outBack(promptAge / 0.3)
        BodyGameHUD.pill(ctx, text, center: BodyGameHUD.promptCenter(size), size: CGFloat(48 * (0.7 + 0.3 * enter)), color: BodyGamePalette.cream,
                         accent: BodyGamePalette.coral, alpha: CGFloat(min(1, promptAge / 0.15)))
    }

    /// The two ends of a beam at a given position.
    private func ends(_ beam: Beam, at position: Double) -> (CGPoint, CGPoint) {
        switch beam.axis {
        case .vertical: return (CGPoint(x: position, y: size.height), CGPoint(x: position, y: beam.reach))
        case .horizontal: return (CGPoint(x: 0, y: position), CGPoint(x: size.width, y: position))
        }
    }

    /// Before it switches on: a dashed ghost of the beam where it will stop, with chevrons showing which way it is coming.
    private func drawWarning(_ beam: Beam, in ctx: CGContext, time: Double) {
        let t = bodyClamp(beam.age / beam.telegraph, 0, 1)
        let (a, b) = ends(beam, at: beam.end)
        let pulse = 0.55 + 0.45 * sin(time * (5 + 6 * t))
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineDash(phase: CGFloat(-time * 60), lengths: [18, 14])
        ctx.setStrokeColor(BodyGamePalette.cg(BodyGamePalette.ink, 0.35))
        ctx.setLineWidth(9)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
        ctx.setStrokeColor(BodyGamePalette.cg(LaserArt.beam, CGFloat(0.45 + 0.4 * pulse * t)))
        ctx.setLineWidth(4)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
        ctx.restoreGState()
        // Chevrons along the ghost, pointing the way the beam will move.
        let way: CGFloat = beam.end > beam.start ? 1 : -1
        ctx.setStrokeColor(BodyGamePalette.cg(LaserArt.beam, CGFloat(0.8 * t)))
        ctx.setLineWidth(4)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for k in 0..<3 {
            let along = 0.25 + Double(k) * 0.25
            let p = CGPoint(x: a.x + (b.x - a.x) * along, y: a.y + (b.y - a.y) * along)
            let step = CGFloat(8 * sin(time * 6 + Double(k)))
            switch beam.axis {
            case .vertical:
                let x = p.x - way * (22 - step)
                ctx.move(to: CGPoint(x: x - way * 10, y: p.y + 12))
                ctx.addLine(to: CGPoint(x: x, y: p.y))
                ctx.addLine(to: CGPoint(x: x - way * 10, y: p.y - 12))
            case .horizontal:
                let y = p.y - way * (22 - step)
                ctx.move(to: CGPoint(x: p.x - 12, y: y - way * 10))
                ctx.addLine(to: CGPoint(x: p.x, y: y))
                ctx.addLine(to: CGPoint(x: p.x + 12, y: y - way * 10))
            }
        }
        ctx.strokePath()
    }

    private func drawBeam(_ beam: Beam, in ctx: CGContext, time: Double) {
        let (a, b) = ends(beam, at: beam.position)
        let on = bodyClamp((beam.age - beam.telegraph) / 0.12, 0, 1)
        let off = bodyClamp((beam.life - beam.age) / 0.15, 0, 1)
        let hum = 0.92 + 0.08 * sin(time * 53 + beam.start)
        let alpha = on * off * hum
        let harmless = graceLeft > 0 || beam.struck ? 0.55 : 1
        ctx.saveGState()
        ctx.setLineCap(.round)
        for (width, colour, a2) in [(CGFloat(34), LaserArt.beam, 0.14), (CGFloat(16), LaserArt.beam, 0.35), (CGFloat(7), LaserArt.beam, 0.95),
                                    (CGFloat(2.5), LaserArt.core, 1.0)] {
            ctx.setStrokeColor(BodyGamePalette.cg(colour, CGFloat(a2 * alpha * harmless)))
            ctx.setLineWidth(width * CGFloat(0.6 + 0.4 * on))
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.strokePath()
        }
        ctx.restoreGState()
        // Dust in the beam: motes that drift along it and twinkle.
        let length = hypot(b.x - a.x, b.y - a.y)
        for k in 0..<14 {
            let along = (Double(k) * 97.3 + time * (40 + Double(k % 3) * 25)).truncatingRemainder(dividingBy: Double(length))
            let p = CGPoint(x: a.x + (b.x - a.x) * along / length, y: a.y + (b.y - a.y) * along / length)
            let twinkle = 0.5 + 0.5 * sin(time * 9 + Double(k) * 1.7)
            BodyGlow.stamp(ctx, at: p, radius: CGFloat(6 + 4 * twinkle), red: 1, green: 0.92, blue: 0.9, alpha: 0.7 * twinkle * alpha)
        }
        if beam.axis == .vertical {
            // The blade's tip: a hot point where it ends in the air.
            BodyGlow.stamp(ctx, at: b, radius: 26, color: LaserArt.beam, alpha: 0.9 * alpha)
            BodyGlow.stamp(ctx, at: b, radius: 9, red: 1, green: 1, blue: 1, alpha: alpha)
        }
    }

    private func drawEmitters(_ beam: Beam, in ctx: CGContext, time: Double) {
        guard let housing = LaserArt.emitter() else { return }
        let charge = bodyClamp(beam.age / beam.telegraph, 0, 1)
        let enter = BodyEase.outBack(beam.age / 0.35)
        let leave = bodyClamp((beam.life - beam.age) / 0.25, 0, 1)
        let p = beam.position
        // An emitter slides into view at the edge as the beam's warning starts and slides away when it is done.
        var mounts: [(CGPoint, CGFloat)] = []
        switch beam.axis {
        case .vertical:
            let x = bodyClamp(p, 20, size.width - 20)
            mounts = [(CGPoint(x: x, y: size.height + 30 - 52 * enter * leave), 0)]
        case .horizontal:
            let y = min(p, size.height - 24)
            mounts = [(CGPoint(x: -30 + 52 * enter * leave, y: y), .pi / 2), (CGPoint(x: size.width + 30 - 52 * enter * leave, y: y), -.pi / 2)]
        }
        for (at, turn) in mounts {
            ctx.draw(housing, center: at, height: 64, rotation: turn)
            let lens = CGPoint(x: at.x + sin(turn) * 22, y: at.y - cos(turn) * 22)
            let glow = beam.isHot ? 1 : 0.3 + 0.7 * charge * (0.6 + 0.4 * sin(time * 14))
            BodyGlow.stamp(ctx, at: lens, radius: CGFloat(14 + 12 * glow), color: LaserArt.beam, alpha: 0.9 * glow)
        }
    }
}

/// The laser's colours and its emitter, drawn once.
enum LaserArt {
    /// Hot pink-red: reads as danger on any backdrop without being a pure red.
    static let beam = NSColor(red: 1.0, green: 0.27, blue: 0.42, alpha: 1)
    static let core = NSColor(red: 1.0, green: 0.94, blue: 0.95, alpha: 1)

    /// A gunmetal housing pointing down, with a lens at its tip and two bolts.
    static func emitter() -> CGImage? {
        BodyArtCache.image("laser-emitter", width: 72, height: 72) { ctx in
            let body = CGRect(x: 12, y: 20, width: 48, height: 44)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 5, color: CGColor(red: 0, green: 0, blue: 0.05, alpha: 0.6))
            ctx.addPath(CGPath(roundedRect: body, cornerWidth: 10, cornerHeight: 10, transform: nil))
            ctx.setFillColor(CGColor(red: 0.3, green: 0.32, blue: 0.4, alpha: 1))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: body, cornerWidth: 10, cornerHeight: 10, transform: nil))
            ctx.clip()
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let metal = [CGColor(red: 0.74, green: 0.77, blue: 0.86, alpha: 1), CGColor(red: 0.38, green: 0.4, blue: 0.5, alpha: 1),
                         CGColor(red: 0.16, green: 0.17, blue: 0.24, alpha: 1)] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: metal, locations: [0, 0.45, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
            }
            ctx.restoreGState()
            // The nozzle.
            let nozzle = CGRect(x: 24, y: 8, width: 24, height: 16)
            ctx.addPath(CGPath(roundedRect: nozzle, cornerWidth: 5, cornerHeight: 5, transform: nil))
            ctx.setFillColor(CGColor(red: 0.18, green: 0.18, blue: 0.24, alpha: 1))
            ctx.fillPath()
            ctx.setFillColor(CGColor(red: 1, green: 0.55, blue: 0.62, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 30, y: 10, width: 12, height: 8))
            // Bolts and a bright edge along the top left.
            for x in [20.0, 52.0] {
                ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: x - 3.5, y: 52 - 3.5, width: 7, height: 7))
                ctx.setFillColor(CGColor(red: 0.85, green: 0.88, blue: 0.95, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: x - 2.5, y: 52 - 1.5, width: 3.5, height: 3.5))
            }
            ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1, dy: 1), cornerWidth: 9, cornerHeight: 9, transform: nil))
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.25))
            ctx.setLineWidth(1.5)
            ctx.strokePath()
        }
    }
}
