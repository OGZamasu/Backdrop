import AppKit
import CoreGraphics
import simd

/// Whack-a-Mole with your hands. Moles pop out of holes in a lawn; poke one with a fingertip or the flat of your hand before it ducks
/// back down. Gold moles are worth five. Bunnies and bombs are not to be touched. A run of hits without a miss builds a multiplier.
///
/// A touch only counts if the hand is moving (see `HandPokeTracker`), so a hand resting over a hole does not win it for you.
struct WhackAMoleGame: HandGameScreens {
    static let title = "Whack-a-Mole"
    static let hint = "Poke the moles! Leave the bunnies and bombs alone."
    static let presenceHint = "Hold up your hand to play"
    static let onboarding = ["Poke a mole with a finger, or slap it", "Gold moles are worth five", "Leave the bunnies and bombs alone"]
    static let accent = SIMD3<Double>(0.5, 0.9, 0.48)
    static let icon = GameUIIcon.hand(.point)
    static let roundSeconds = 45.0

    enum Kind: Equatable {
        case mole, golden, bunny, bomb

        /// Whether poking it is what you want.
        var isTarget: Bool { self == .mole || self == .golden }
    }

    struct Mole: Equatable {
        var hole: Int
        var kind: Kind
        /// Seconds since it started to come up.
        var age = 0.0
        /// How long it stays all the way up.
        var stay: Double
        /// Seconds since it was poked, or nil if it has not been.
        var whacked: Double? = nil
    }

    struct Floater { var text: String; var position: SIMD2<Double>; var age = 0.0; var good: Bool }

    // The shape of a mole's life, in seconds.
    static let riseTime = 0.14
    static let sinkTime = 0.2
    /// How long a whacked mole stays squashed before it slides back down, and when it is gone.
    static let squashHold = 0.32
    static let squashTotal = 0.62
    /// How big a mole is to a poke, in pixels on a 1280-wide picture.
    static let hitRadius = 64.0
    /// How far a mole's head travels between hidden and fully up, and where it is when hidden, relative to its hole.
    static let headTravel = 146.0
    static let headHidden = -90.0
    /// How big the holes and everything in them are drawn, against a 1280-wide picture.
    static let holeScale = 0.85

    let size: CGSize
    let holes: [CGPoint]
    private(set) var moles: [Mole] = []
    private(set) var score = 0
    private(set) var timeLeft = WhackAMoleGame.roundSeconds
    private(set) var elapsed = 0.0
    /// Moles and gold moles whacked.
    private(set) var whacks = 0
    /// Moles that got away.
    private(set) var escaped = 0
    /// Moles sent up so far, of every kind.
    private(set) var spawned = 0
    private(set) var bunniesHit = 0
    private(set) var bombsHit = 0
    private(set) var combo = 0
    private(set) var bestMultiplier = 1
    private(set) var spawnsPaused = false
    private var sparks = ParticleSystem(capacity: 300)
    private var floaters: [Floater] = []
    private var tracker = HandPokeTracker()
    private var armed: [HandPokeTracker.Hitter] = []
    private var rng: SplitMix64
    private var nextSpawn = 0.5
    private var lastHole = -1
    private var flash = 0.0

    var isOver: Bool { timeLeft <= 0 }
    var multiplier: Int { 1 + min(3, combo / 3) }
    var summary: String { multiplier > 1 ? "x\(multiplier) · \(Int(timeLeft.rounded(.up)))s" : "\(Int(timeLeft.rounded(.up)))s" }
    private var unit: Double { Double(size.width) / 1280 }
    /// One point of mole art in pixels.
    private var art: Double { unit * Self.holeScale }

    var readout: GameUIReadout {
        GameUIReadout(score: score, time: (timeLeft, Self.roundSeconds), combo: multiplier > 1 ? multiplier : 0)
    }

    var result: GameUIResult {
        let line: String
        switch whacks {
        case 0: line = "Give them a quick poke when they pop up"
        case 1..<15: line = "The moles are getting away. Keep at it!"
        case 15..<30: line = "Quick hands!"
        default: line = "Mole patrol champion"
        }
        return GameUIResult(headline: "Time's up!", line: line,
                            stats: [("\(whacks)", "whacked"), ("\(escaped)", "got away"), ("x\(bestMultiplier)", "best run")], kind: .timeUp)
    }

    static func warmUp(_ step: Int) -> Bool {
        switch step {
        case 0: _ = holeBase()
        case 1: _ = lip()
        case 2...5: _ = moleSprite(golden: step >= 4, dazed: step % 2 == 1)
        case 6: _ = bunnySprite()
        case 7: _ = malletSprite()
        case 8: _ = HandGamePieces.bomb()
        case 9: _ = FingerGunsArt.flashSprite()
        default: return false
        }
        return true
    }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        holes = Self.holeLayout(in: size)
        rng = SplitMix64(seed: seed)
        sparks.gravity = SIMD2(0, -900)
    }

    /// Nine holes round the player, clear of the face: five along the bottom of the picture and two up each side, all inside a 5%
    /// border so none is cut off by the edge.
    static func holeLayout(in size: CGSize) -> [CGPoint] {
        // The front row sits just above the band the hints use, the top holes just below the plates.
        let front = [0.14, 0.32, 0.5, 0.68, 0.86].map { CGPoint(x: size.width * $0, y: size.height * 0.225) }
        let sides = [(0.14, 0.445), (0.14, 0.66), (0.86, 0.445), (0.86, 0.66)].map { CGPoint(x: size.width * $0.0, y: size.height * $0.1) }
        return front + sides
    }

    // MARK: A mole's life

    /// How far up a mole is: 0 hidden, 1 all the way.
    func rise(of mole: Mole) -> Double {
        if let w = mole.whacked {
            return w < Self.squashHold ? 1 : max(0, 1 - (w - Self.squashHold) / (Self.squashTotal - Self.squashHold))
        }
        if mole.age < Self.riseTime { let t = mole.age / Self.riseTime; return 1 - (1 - t) * (1 - t) }
        if mole.age < Self.riseTime + mole.stay { return 1 }
        return max(0, 1 - (mole.age - Self.riseTime - mole.stay) / Self.sinkTime)
    }

    /// Where the middle of a mole's head is.
    func head(of mole: Mole) -> CGPoint {
        let hole = holes[mole.hole]
        return CGPoint(x: hole.x, y: hole.y + (Self.headHidden + rise(of: mole) * Self.headTravel) * art)
    }

    /// Whether a mole is up far enough, and not already whacked, to be hit.
    func isHittable(_ mole: Mole) -> Bool { mole.whacked == nil && rise(of: mole) > 0.5 }

    /// How hard the round is, 0 at the start to 1 at the end.
    private var progress: Double { min(1, elapsed / Self.roundSeconds) }

    // MARK: Step

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.5)
        guard timeLeft > 0 else { return }
        elapsed += dt
        timeLeft = max(0, timeLeft - dt)
        flash = max(0, flash - dt)

        if !spawnsPaused {
            nextSpawn -= dt
            if nextSpawn <= 0 { spawn() }
        }

        for i in moles.indices {
            if let w = moles[i].whacked { moles[i].whacked = w + dt } else { moles[i].age += dt }
        }
        for mole in moles where mole.whacked == nil && mole.age >= Self.riseTime + mole.stay + Self.sinkTime && mole.kind.isTarget {
            escaped += 1
            combo = 0
        }
        moles.removeAll { $0.whacked.map { $0 >= Self.squashTotal } ?? ($0.age >= Self.riseTime + $0.stay + Self.sinkTime) }

        armed = tracker.update(world.hands, now: elapsed)
        poke(with: armed)

        sparks.step(dt)
        for i in floaters.indices { floaters[i].age += dt; floaters[i].position.y += 80 * dt }
        floaters.removeAll { $0.age > 0.9 }

        if timeLeft <= 0 {
            // Nothing is stepped once the round is over, so leave the lawn empty rather than frozen mid-pop.
            moles.removeAll()
            floaters.removeAll()
            sparks.removeAll()
            armed.removeAll()
            flash = 0
        }
    }

    private mutating func spawn() {
        let limit = min(3, 1 + Int(progress * 3.4))
        let up = moles.filter { $0.whacked == nil }.count
        let free = holes.indices.filter { hole in hole != lastHole && !moles.contains { $0.hole == hole } }
        guard up < limit, !free.isEmpty else { nextSpawn = 0.15; return }

        let hole = free[Int.random(in: 0..<free.count, using: &rng)]
        let roll = Double.random(in: 0..<1, using: &rng)
        let kind: Kind
        if elapsed < 3 { kind = .mole }
        else if roll < 0.09 + progress * 0.05 { kind = .bomb }
        else if roll < 0.19 + progress * 0.05 { kind = .bunny }
        else if roll < 0.26 + progress * 0.05 { kind = .golden }
        else { kind = .mole }
        let stay = HandGameArt.lerp(1.55, 0.7, progress) * Double.random(in: 0.85...1.15, using: &rng)
        moles.append(Mole(hole: hole, kind: kind, stay: kind == .golden ? stay * 0.8 : stay))
        lastHole = hole
        spawned += 1
        nextSpawn = HandGameArt.lerp(1.0, 0.4, progress) * Double.random(in: 0.75...1.25, using: &rng)
    }

    // MARK: Poking

    private mutating func poke(with hitters: [HandPokeTracker.Hitter]) {
        for i in moles.indices where isHittable(moles[i]) {
            let target = head(of: moles[i])
            let centre = SIMD2(Double(target.x), Double(target.y))
            for hitter in hitters where hitter.isPoking {
                let reach = Self.hitRadius * unit + hitter.radius
                let from = SIMD2(Double(hitter.previous.x), Double(hitter.previous.y)), to = SIMD2(Double(hitter.position.x), Double(hitter.position.y))
                if HandGeometry.segment(from: from, to: to, hits: centre, radius: reach) {
                    whack(i)
                    break
                }
            }
        }
    }

    private mutating func whack(_ index: Int) {
        moles[index].whacked = 0
        let kind = moles[index].kind
        let spot = head(of: moles[index])
        let at = SIMD2(Double(spot.x), Double(spot.y))
        switch kind {
        case .mole, .golden:
            combo += 1
            whacks += 1
            bestMultiplier = max(bestMultiplier, multiplier)
            let points = (kind == .golden ? 5 : 1) * multiplier
            score += points
            floaters.append(Floater(text: "+\(points)", position: at + SIMD2(0, 70), good: true))
            burst(at: at, kind: kind)
        case .bunny:
            combo = 0
            bunniesHit += 1
            score = max(0, score - 3)
            floaters.append(Floater(text: "-3", position: at + SIMD2(0, 70), good: false))
            burst(at: at, kind: kind)
        case .bomb:
            combo = 0
            bombsHit += 1
            score = max(0, score - 5)
            flash = 0.4
            floaters.append(Floater(text: "-5", position: at + SIMD2(0, 70), good: false))
            burst(at: at, kind: kind)
        }
    }

    private mutating func burst(at point: SIMD2<Double>, kind: Kind) {
        let count = kind == .bomb ? 34 : 18
        for n in 0..<count {
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng), speed = Double.random(in: 140...460, using: &rng)
            let particle: Int
            switch kind {
            case .bomb: particle = 2
            default: particle = n % 3 == 0 ? 0 : 1
            }
            sparks.emit(Particle(position: point, velocity: SIMD2(cos(angle), sin(angle) * 0.8 + 0.5) * speed,
                                 life: Double.random(in: 0.45...0.9, using: &rng), size: Double.random(in: 4...9, using: &rng),
                                 hue: Double.random(in: 0..<1, using: &rng), kind: particle))
        }
    }

    // MARK: Test hooks

    /// Stops new moles coming (or lets them again), so a test can place exactly what it wants.
    mutating func pauseSpawns(_ paused: Bool = true) { spawnsPaused = paused }

    /// Puts a mole fully up in a hole, staying there for `stay` seconds.
    mutating func place(_ kind: Kind, hole: Int, stay: Double = 10) {
        moles.removeAll { $0.hole == hole }
        moles.append(Mole(hole: hole, kind: kind, age: Self.riseTime, stay: stay))
    }

    mutating func clearMoles() { moles.removeAll() }

    /// Whacks whatever is up in a hole, as if it had been poked, and ages it by `age` seconds.
    mutating func whackMole(inHole hole: Int, age: Double = 0) {
        guard let index = moles.firstIndex(where: { $0.hole == hole && $0.whacked == nil }) else { return }
        whack(index)
        moles[index].whacked = age
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        let shake = flash > 0 ? 6 * flash * flash / 0.16 : 0
        ctx.saveGState()
        if shake > 0 { ctx.translateBy(x: CGFloat(sin(time * 67) * shake), y: CGFloat(cos(time * 51) * shake)) }
        for index in holes.indices.sorted(by: { holes[$0].y > holes[$1].y }) {
            let mole = moles.first { $0.hole == index }
            drawHole(ctx, at: holes[index], mole: mole, time: time)
        }
        ctx.restoreGState()
        drawSparks(ctx)
        drawArmed(ctx)
        for f in floaters {
            let pop = HandGameEase.outBack(f.age / 0.22)
            HandGameType.draw(ctx, f.text, at: CGPoint(x: f.position.x, y: f.position.y), size: 40,
                              color: HandGamePalette.color(f.good ? HandGamePalette.gold : HandGamePalette.coral),
                              alpha: CGFloat(min(1, (0.9 - f.age) / 0.3)), scale: CGFloat(pop))
        }
    }

    private func drawSparks(_ ctx: CGContext) {
        for p in sparks.particles {
            let at = CGPoint(x: p.position.x, y: p.position.y)
            let fade = CGFloat(1 - p.progress)
            switch p.kind {
            case 0: HandGameArt.star(ctx, at: at, radius: p.size * 1.6, rotation: CGFloat(p.age * 6), alpha: fade)
            case 2: HandGameArt.halo(ctx, at: at, radius: p.size * 2.4, red: 1, green: 0.55 + 0.4 * (1 - p.progress), blue: 0.2, alpha: Double(fade))
            default:
                // Clods of earth, lit on top.
                ctx.fillCircle(center: at, radius: p.size * 0.9, color: CGColor(srgbRed: 0.42, green: 0.27, blue: 0.16, alpha: fade))
                ctx.fillCircle(center: CGPoint(x: at.x - p.size * 0.25, y: at.y + p.size * 0.25), radius: p.size * 0.4,
                               color: CGColor(srgbRed: 0.66, green: 0.47, blue: 0.3, alpha: fade))
            }
        }
    }

    /// A soft ring on the fingertips that are moving fast enough to count, so you can see what will hit.
    private func drawArmed(_ ctx: CGContext) {
        for h in armed where h.isPoking && !h.isPalm {
            let r = CGFloat(h.radius) * 1.1
            HandGameArt.halo(ctx, at: h.position, radius: r * 1.6, red: 1, green: 0.9, blue: 0.55, alpha: 0.45)
            ctx.setStrokeColor(HandGamePalette.color(HandGamePalette.gold, 0.9))
            ctx.setLineWidth(3)
            ctx.strokeEllipse(in: CGRect(x: h.position.x - r, y: h.position.y - r, width: r * 2, height: r * 2))
        }
    }

    // MARK: A hole

    /// The lip of earth in front of the opening, in a hole's own units.
    private static let lipPath: CGPath = {
        let lip = CGMutablePath()
        for step in 0...24 {
            let t = Double.pi + Double(step) / 24 * Double.pi
            let p = CGPoint(x: cos(t) * 100, y: sin(t) * 44)
            if step == 0 { lip.move(to: p) } else { lip.addLine(to: p) }
        }
        for step in 0...24 {
            let t = 2 * Double.pi - Double(step) / 24 * Double.pi
            lip.addLine(to: CGPoint(x: cos(t) * 78, y: 3 + sin(t) * 30))
        }
        lip.closeSubpath()
        return lip
    }()

    private static let baseBox = CGSize(width: 290, height: 140)

    /// An empty hole: a mound of earth in a ring of grass round a dark opening, drawn once.
    private static func holeBase(_ scale: Double = holeScale) -> CGImage? {
        HandGameSprites.image("whack.hole.\(Int(scale * 1000))", size: baseBox, scale: CGFloat(scale)) { ctx in
            let grass = SIMD3<Double>(0.33, 0.68, 0.3), earth = SIMD3<Double>(0.6, 0.4, 0.24)
            HandGameSprites.contactShadow(ctx, center: CGPoint(x: 4, y: -10), width: 280, height: 112, alpha: 0.4)
            let turf = CGRect(x: -132, y: -56, width: 264, height: 112)
            ctx.saveGState()
            ctx.addEllipse(in: turf)
            ctx.clip()
            HandGameSprites.linear(ctx, [HandGameSprites.shade(grass, 1.2), HandGameSprites.shade(grass, 0.7)], from: CGPoint(x: -60, y: 56), to: CGPoint(x: 60, y: -56))
            ctx.restoreGState()
            // Tufts round the edge, two greens, leaning a little.
            var rng = SplitMix64(seed: 77)
            for k in 0..<26 {
                let a = Double(k) / 26 * 2 * .pi
                let p = CGPoint(x: cos(a) * 118, y: sin(a) * 47 - 6)
                let lean = CGFloat(Double.random(in: -0.4...0.4, using: &rng))
                tuft(ctx, at: p, height: CGFloat(Double.random(in: 12...22, using: &rng)), lean: lean,
                     color: HandGameSprites.shade(grass, k % 2 == 0 ? 1.25 : 0.95))
            }
            let mound = CGRect(x: -104, y: -46, width: 208, height: 92)
            ctx.saveGState()
            ctx.addEllipse(in: mound)
            ctx.clip()
            HandGameSprites.radial(ctx, [HandGameSprites.shade(earth, 1.25), HandGameSprites.shade(earth, 0.9), HandGameSprites.shade(earth, 0.62)], locations: [0, 0.5, 1],
                                   center: CGPoint(x: 0, y: -4), radius: 108, focus: CGPoint(x: -40, y: 30))
            ctx.restoreGState()
            // The opening, dark and deeper toward the back.
            let opening = CGRect(x: -78, y: -27, width: 156, height: 60)
            ctx.saveGState()
            ctx.addEllipse(in: opening)
            ctx.clip()
            HandGameSprites.linear(ctx, [CGColor(srgbRed: 0.05, green: 0.03, blue: 0.02, alpha: 1), CGColor(srgbRed: 0.2, green: 0.12, blue: 0.07, alpha: 1)],
                                   from: CGPoint(x: 0, y: 33), to: CGPoint(x: 0, y: -27))
            ctx.restoreGState()
        }
    }

    private static func tuft(_ ctx: CGContext, at p: CGPoint, height: CGFloat, lean: CGFloat, color: CGColor) {
        let path = CGMutablePath()
        for blade in [-1.0, 0.0, 1.0] {
            let b = CGFloat(blade)
            path.move(to: CGPoint(x: p.x + b * 4 - 3, y: p.y))
            path.addQuadCurve(to: CGPoint(x: p.x + b * 6 + lean * height, y: p.y + height * (blade == 0 ? 1 : 0.75)),
                              control: CGPoint(x: p.x + b * 3, y: p.y + height * 0.6))
            path.addQuadCurve(to: CGPoint(x: p.x + b * 4 + 3, y: p.y), control: CGPoint(x: p.x + b * 4 + 2, y: p.y + height * 0.5))
        }
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    /// The lip of earth in front of the opening, drawn once.
    private static func lip(_ scale: Double = holeScale) -> CGImage? {
        HandGameSprites.image("whack.lip.\(Int(scale * 1000))", size: CGSize(width: 220, height: 110), scale: CGFloat(scale)) { ctx in
            let earth = SIMD3<Double>(0.66, 0.45, 0.28)
            ctx.saveGState()
            ctx.addPath(lipPath)
            ctx.clip()
            HandGameSprites.linear(ctx, [HandGameSprites.shade(earth, 1.25), HandGameSprites.shade(earth, 0.75)], from: CGPoint(x: 0, y: 4), to: CGPoint(x: 0, y: -44))
            // Pebbles.
            var rng = SplitMix64(seed: 5)
            for _ in 0..<14 {
                let a = Double.random(in: Double.pi * 1.1...Double.pi * 1.9, using: &rng), d = Double.random(in: 0.82...0.97, using: &rng)
                let p = CGPoint(x: cos(a) * 92 * d, y: sin(a) * 38 * d)
                let r = CGFloat(Double.random(in: 2...4.5, using: &rng))
                ctx.setFillColor(HandGameSprites.shade(earth, 0.65))
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r * 0.7, width: r * 2, height: r * 1.4))
                ctx.setFillColor(HandGameSprites.shade(earth, 1.35, alpha: 0.8))
                ctx.fillEllipse(in: CGRect(x: p.x - r * 0.6, y: p.y, width: r, height: r * 0.6))
            }
            ctx.restoreGState()
            ctx.addPath(lipPath)
            ctx.setStrokeColor(HandGameSprites.shade(earth, 0.45, alpha: 0.8))
            ctx.setLineWidth(2)
            ctx.strokePath()
        }
    }

    /// Draws a sprite baked at the picture's own scale pixel for pixel, its centre at `center` snapped to whole pixels: no resampling,
    /// which keeps nine holes and their moles cheap to draw every frame.
    private static func blit(_ ctx: CGContext, _ image: CGImage, center: CGPoint, offset: CGPoint = .zero) {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        ctx.draw(image, in: CGRect(x: (center.x + offset.x - w / 2).rounded(), y: (center.y + offset.y - h / 2).rounded(), width: w, height: h))
    }

    private func drawHole(_ ctx: CGContext, at hole: CGPoint, mole: Mole?, time: Double) {
        if let base = Self.holeBase(art) { Self.blit(ctx, base, center: hole) }
        if let mole {
            let rise = rise(of: mole)
            if rise > 0 { drawFigure(ctx, at: hole, mole: mole, rise: rise, time: time) }
        }
        // The front lip of the hole, over the bottom of whatever is coming out.
        if let lip = Self.lip(art) { Self.blit(ctx, lip, center: hole) }
        if let mole { drawEffects(ctx, mole: mole, time: time) }
    }

    /// What comes out of the hole, cut off level with the bottom of the opening (the lip drawn after it covers the rest).
    private func drawFigure(_ ctx: CGContext, at hole: CGPoint, mole: Mole, rise: Double, time: Double) {
        let a = CGFloat(art)
        ctx.saveGState()
        ctx.clip(to: CGRect(x: hole.x - 170 * a, y: hole.y - 27 * a, width: 340 * a, height: 460 * a))
        let headY = CGFloat(Self.headHidden + rise * Self.headTravel) * a
        let head = CGPoint(x: hole.x, y: hole.y + headY)
        let sprite: CGImage?
        switch mole.kind {
        case .mole, .golden: sprite = Self.moleSprite(golden: mole.kind == .golden, dazed: mole.whacked != nil, scale: art)
        case .bunny: sprite = Self.bunnySprite(scale: art)
        case .bomb: sprite = nil
        }
        if mole.kind == .golden { HandGameArt.halo(ctx, at: CGPoint(x: head.x, y: head.y - 10 * a), radius: 110 * a, red: 1, green: 0.84, blue: 0.3, alpha: 0.7 + 0.15 * sin(time * 6)) }
        if let sprite {
            // A whacked one is squashed flat toward the ground and wobbles back; one coming up stretches a little as it pops. Only then is
            // it resampled; the rest of the time it is drawn pixel for pixel.
            var sx = 1.0, sy = 1.0
            if let w = mole.whacked {
                let squash = min(1, w / 0.05) * (1 - 0.35 * max(0, min(1, (w - 0.12) / 0.2)))
                let wobble = 0.06 * HandGameEase.wobble(w, frequency: 4, damping: 7)
                sx = 1 + 0.3 * squash + wobble
                sy = 1 - 0.42 * squash - wobble
            } else if mole.age < Self.riseTime + 0.15 {
                let pop = 0.08 * HandGameEase.wobble(mole.age, frequency: 3, damping: 9)
                sx = 1 - pop
                sy = 1 + pop
            }
            if abs(sx - 1) < 0.005 && abs(sy - 1) < 0.005 {
                Self.blit(ctx, sprite, center: head)
            } else {
                // Squash toward the bottom of the opening, so it stays planted in the hole.
                let ground = CGPoint(x: hole.x, y: hole.y - 27 * a)
                ctx.translateBy(x: ground.x, y: ground.y)
                ctx.scaleBy(x: CGFloat(sx), y: CGFloat(sy))
                ctx.translateBy(x: -ground.x, y: -ground.y)
                let w = CGFloat(sprite.width), h = CGFloat(sprite.height)
                ctx.draw(sprite, in: CGRect(x: head.x - w / 2, y: head.y - h / 2, width: w, height: h))
            }
        } else if mole.whacked == nil {
            let pulse = 0.5 + 0.5 * sin(time * 10)
            HandGameArt.halo(ctx, at: CGPoint(x: head.x, y: head.y - 4 * a), radius: 118 * a, red: 1, green: 0.25, blue: 0.2, alpha: 0.35 + 0.3 * pulse)
            if let bomb = HandGamePieces.bomb() {
                let height = 190 * a
                ctx.draw(bomb, center: CGPoint(x: head.x, y: head.y - 8 * a), height: height)
                let tip = HandGamePieces.bombFuseTip
                HandGamePieces.spark(ctx, at: CGPoint(x: head.x + tip.x * height, y: head.y - 8 * a + tip.y * height), size: 18 * a, time: time)
            }
        }
        ctx.restoreGState()
    }

    /// Stars round a whacked head, the mallet coming down, a bomb going off: things that are not clipped by the hole.
    private func drawEffects(_ ctx: CGContext, mole: Mole, time: Double) {
        guard let w = mole.whacked else { return }
        let head = self.head(of: mole)
        if mole.kind == .bomb {
            if w < 0.5 {
                let t = w / 0.5
                HandGameArt.halo(ctx, at: head, radius: CGFloat(90 + 120 * t) * CGFloat(unit), red: 1, green: 0.7, blue: 0.35, alpha: 0.8 * (1 - t))
                FingerGunsArt.muzzleFlash(ctx, at: head, angle: Double(mole.hole), age: min(0.099, w * 0.25))
                let ring = CGFloat(40 + 160 * HandGameEase.outCubic(t)) * CGFloat(unit)
                ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.9, blue: 0.7, alpha: CGFloat(0.6 * (1 - t))))
                ctx.setLineWidth(CGFloat(10 * (1 - t) + 2))
                ctx.strokeEllipse(in: CGRect(x: head.x - ring, y: head.y - ring, width: ring * 2, height: ring * 2))
            }
            return
        }
        if w < Self.squashHold + 0.1 {
            let fade = CGFloat(min(1, max(0, (Self.squashHold + 0.1 - w) / 0.15)))
            for k in 0..<3 {
                let a = w * 9 + Double(k) * 2 * .pi / 3
                let p = CGPoint(x: head.x + cos(a) * 58 * art, y: head.y + 50 * art + sin(a) * 15 * art)
                HandGameArt.star(ctx, at: p, radius: CGFloat(14 * art), rotation: CGFloat(a), alpha: fade)
            }
        }
        if w < 0.42, let mallet = Self.malletSprite() {
            // The mallet swings down from up and to the right, lands on the beat of the squash, bounces and lifts away.
            // The grip is up and to the right of the head; at 0.2 radians the head of the mallet lands on the mole's.
            let down = HandGameEase.outCubic(w / 0.07)
            let lift = HandGameEase.inOut(max(0, w - 0.18) / 0.24)
            let angle = HandGameArt.lerp(-1.0, 0.2, down) - 0.8 * lift - 0.06 * HandGameEase.wobble(w - 0.07, frequency: 6, damping: 12)
            let fade = max(0, 1 - max(0, w - 0.26) / 0.16)
            let pivot = CGPoint(x: head.x + 150 * art, y: head.y + 30 * art)
            ctx.saveGState()
            ctx.translateBy(x: pivot.x, y: pivot.y)
            ctx.rotate(by: CGFloat(angle))
            ctx.setAlpha(CGFloat(fade))
            ctx.draw(mallet, in: CGRect(x: -195 * art, y: -60 * art, width: 240 * art, height: 120 * art))
            ctx.restoreGState()
        }
    }

        // MARK: Characters

    /// Mole sprites are drawn in this box, centred on the middle of the head.
    private static let moleBox = CGSize(width: 220, height: 400)

    private struct Fur {
        let body: SIMD3<Double>, dark: SIMD3<Double>, snout: SIMD3<Double>, paw: SIMD3<Double>
    }

    private static let moleFur = Fur(body: SIMD3(0.56, 0.38, 0.27), dark: SIMD3(0.27, 0.16, 0.1), snout: SIMD3(0.98, 0.82, 0.7), paw: SIMD3(0.98, 0.72, 0.64))
    private static let goldFur = Fur(body: SIMD3(1, 0.78, 0.25), dark: SIMD3(0.58, 0.35, 0.06), snout: SIMD3(1, 0.95, 0.72), paw: SIMD3(1, 0.9, 0.6))

    private static func moleSprite(golden: Bool, dazed: Bool, scale: Double = holeScale) -> CGImage? {
        HandGameSprites.image("whack.mole.\(golden).\(dazed).\(Int(scale * 1000))", size: moleBox, scale: CGFloat(scale)) { ctx in
            drawMole(ctx, fur: golden ? goldFur : moleFur, dazed: dazed, crown: golden)
        }
    }

    private static func bunnySprite(scale: Double = holeScale) -> CGImage? {
        HandGameSprites.image("whack.bunny.\(Int(scale * 1000))", size: moleBox, scale: CGFloat(scale)) { ctx in drawBunny(ctx) }
    }

    /// A wooden mallet lying along x: a red barrel with brass bands on the left and a turned handle out to the grip on the right.
    private static func malletSprite() -> CGImage? {
        HandGameSprites.image("whack.mallet", size: CGSize(width: 240, height: 120), scale: 1) { ctx in
            // Barrel on the left, grip on the right, 150 points apart.
            ctx.translateBy(x: 45, y: 0)
            let wood = SIMD3<Double>(0.78, 0.55, 0.32), red = SIMD3<Double>(0.88, 0.26, 0.24), brass = SIMD3<Double>(0.98, 0.78, 0.36)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 3, height: -5), blur: 6, color: HandGamePalette.color(HandGamePalette.ink, 0.45))
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            let handle = CGPath(roundedRect: CGRect(x: -100, y: -7, width: 150, height: 14), cornerWidth: 7, cornerHeight: 7, transform: nil)
            ctx.saveGState()
            ctx.addPath(handle)
            ctx.clip()
            HandGameSprites.linear(ctx, [HandGameSprites.shade(wood, 1.2), HandGameSprites.shade(wood, 0.7)], from: CGPoint(x: 0, y: 7), to: CGPoint(x: 0, y: -7))
            ctx.restoreGState()
            let barrel = CGPath(roundedRect: CGRect(x: -153, y: -38, width: 66, height: 76), cornerWidth: 14, cornerHeight: 14, transform: nil)
            ctx.saveGState()
            ctx.addPath(barrel)
            ctx.clip()
            HandGameSprites.linear(ctx, [HandGameSprites.shade(red, 1.3), HandGameSprites.shade(red, 1.0), HandGameSprites.shade(red, 0.6)], locations: [0, 0.4, 1],
                                   from: CGPoint(x: -153, y: 38), to: CGPoint(x: -87, y: -38))
            for x in [-147.0, -101.0] {
                ctx.saveGState()
                ctx.clip(to: CGRect(x: x, y: -40, width: 8, height: 80))
                HandGameSprites.linear(ctx, [HandGameSprites.shade(brass, 1.25), HandGameSprites.shade(brass, 0.7)], from: CGPoint(x: 0, y: 38), to: CGPoint(x: 0, y: -38))
                ctx.restoreGState()
            }
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.35))
            ctx.fill(CGRect(x: -137, y: 22, width: 30, height: 8))
            ctx.restoreGState()
            ctx.addPath(barrel)
            ctx.setStrokeColor(HandGameSprites.shade(red, 0.45))
            ctx.setLineWidth(2)
            ctx.strokePath()
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
    }

    private static func c(_ v: SIMD3<Double>, _ light: Double = 1, _ alpha: Double = 1) -> CGColor { HandGameSprites.shade(v, light, alpha: alpha) }

    /// Fills `path` with a gradient lit from the top left and outlines it in the fur's dark colour.
    private static func lit(_ ctx: CGContext, _ path: CGPath, _ color: SIMD3<Double>, line: SIMD3<Double>, width: CGFloat = 3) {
        let box = path.boundingBox
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        HandGameSprites.radial(ctx, [c(color, 1.22), c(color), c(color, 0.72)], locations: [0, 0.5, 1], center: CGPoint(x: box.midX + box.width * 0.1, y: box.midY - box.height * 0.1),
                               radius: max(box.width, box.height) * 0.7, focus: CGPoint(x: box.midX - box.width * 0.22, y: box.midY + box.height * 0.25))
        ctx.restoreGState()
        ctx.addPath(path)
        ctx.setStrokeColor(c(line, 1, 0.9))
        ctx.setLineWidth(width)
        ctx.strokePath()
    }

    /// A mole seen from the front, centred on the middle of its head.
    private static func drawMole(_ ctx: CGContext, fur: Fur, dazed: Bool, crown: Bool) {
        lit(ctx, CGPath(roundedRect: CGRect(x: -56, y: -190, width: 112, height: 170), cornerWidth: 52, cornerHeight: 52, transform: nil), fur.body, line: fur.dark, width: 4)
        // A paler belly.
        ctx.setFillColor(c(fur.snout, 1, 0.35))
        ctx.fillEllipse(in: CGRect(x: -34, y: -150, width: 68, height: 96))
        for s in [CGFloat(-1), 1] {
            // Paws resting on the rim, with claws.
            lit(ctx, CGPath(ellipseIn: CGRect(x: s * 60 - 22, y: -80, width: 44, height: 36), transform: nil), fur.paw, line: fur.dark, width: 3)
            for k in -1...1 {
                ctx.setFillColor(c(SIMD3(1, 0.98, 0.94)))
                ctx.fillEllipse(in: CGRect(x: s * 60 + CGFloat(k) * 11 - 4, y: -88, width: 8, height: 13))
            }
            // Ears.
            lit(ctx, CGPath(ellipseIn: CGRect(x: s * 44 - 13, y: 34, width: 26, height: 24), transform: nil), fur.body, line: fur.dark, width: 3)
            ctx.setFillColor(c(fur.paw, 0.9))
            ctx.fillEllipse(in: CGRect(x: s * 44 - 6, y: 40, width: 12, height: 11))
        }
        // Head, with a shine.
        lit(ctx, CGPath(ellipseIn: CGRect(x: -62, y: -58, width: 124, height: 118), transform: nil), fur.body, line: fur.dark, width: 4)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.22))
        ctx.fillEllipse(in: CGRect(x: -40, y: 22, width: 34, height: 20))
        // Snout, nose and whiskers.
        lit(ctx, CGPath(ellipseIn: CGRect(x: -44, y: -48, width: 88, height: 60), transform: nil), fur.snout, line: fur.dark, width: 2.5)
        let nose = SIMD3<Double>(1, 0.45, 0.56)
        lit(ctx, CGPath(ellipseIn: CGRect(x: -18, y: -6, width: 36, height: 25), transform: nil), nose, line: fur.dark, width: 2.5)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.8))
        ctx.fillEllipse(in: CGRect(x: -10, y: 8, width: 10, height: 6))
        ctx.setStrokeColor(c(fur.dark, 1, 0.55))
        ctx.setLineWidth(1.6)
        ctx.setLineCap(.round)
        for s in [CGFloat(-1), 1] {
            for k in 0..<3 {
                let y = -14 + CGFloat(k) * 7
                ctx.move(to: CGPoint(x: s * 26, y: y))
                ctx.addLine(to: CGPoint(x: s * 60, y: y + CGFloat(k - 1) * 6))
            }
        }
        ctx.strokePath()
        // Cheeks.
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.45, blue: 0.55, alpha: 0.35))
        ctx.fillEllipse(in: CGRect(x: -58, y: -8, width: 22, height: 14))
        ctx.fillEllipse(in: CGRect(x: 36, y: -8, width: 22, height: 14))
        // Eyes: little beads with a glint, or dizzy crosses when it has been bonked.
        for s in [CGFloat(-1), 1] {
            let eye = CGPoint(x: s * 25, y: 28)
            if dazed {
                ctx.setStrokeColor(c(fur.dark))
                ctx.setLineWidth(5)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: eye.x - 8, y: eye.y - 8)); ctx.addLine(to: CGPoint(x: eye.x + 8, y: eye.y + 8))
                ctx.move(to: CGPoint(x: eye.x - 8, y: eye.y + 8)); ctx.addLine(to: CGPoint(x: eye.x + 8, y: eye.y - 8))
                ctx.strokePath()
            } else {
                ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.05, blue: 0.06, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: eye.x - 8, y: eye.y - 10, width: 16, height: 20))
                ctx.setFillColor(.white)
                ctx.fillEllipse(in: CGRect(x: eye.x - 3, y: eye.y + 2, width: 6, height: 7))
            }
        }
        // Buck teeth, or a wobbly open mouth.
        if dazed {
            lit(ctx, CGPath(ellipseIn: CGRect(x: -14, y: -44, width: 28, height: 22), transform: nil), SIMD3(0.36, 0.08, 0.12), line: fur.dark, width: 2.5)
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.5, blue: 0.58, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: -7, y: -42, width: 14, height: 9))
        } else {
            for s in [CGFloat(-1), 0] {
                let tooth = CGPath(roundedRect: CGRect(x: s * 13 + (s == 0 ? 0.5 : -0.5), y: -46, width: 12.5, height: 18), cornerWidth: 4, cornerHeight: 4, transform: nil)
                ctx.addPath(tooth)
                ctx.setFillColor(.white)
                ctx.fillPath()
                ctx.addPath(tooth)
                ctx.setStrokeColor(c(fur.dark))
                ctx.setLineWidth(2.2)
                ctx.strokePath()
            }
        }
        if crown {
            // A little gold crown for the mole worth five.
            let base = CGMutablePath()
            base.move(to: CGPoint(x: -26, y: 50)); base.addLine(to: CGPoint(x: -30, y: 80)); base.addLine(to: CGPoint(x: -14, y: 66))
            base.addLine(to: CGPoint(x: 0, y: 86)); base.addLine(to: CGPoint(x: 14, y: 66)); base.addLine(to: CGPoint(x: 30, y: 80))
            base.addLine(to: CGPoint(x: 26, y: 50)); base.closeSubpath()
            lit(ctx, base, SIMD3(1, 0.84, 0.3), line: SIMD3(0.55, 0.32, 0.05), width: 2.5)
            ctx.setFillColor(c(HandGamePalette.coral))
            ctx.fillEllipse(in: CGRect(x: -4, y: 60, width: 8, height: 8))
        }
    }

    /// The bunny that must be left alone: white fur, pink ears, the same face as the decoy in Finger Guns.
    private static func drawBunny(_ ctx: CGContext) {
        let fur = SIMD3<Double>(0.98, 0.95, 0.97), line = SIMD3<Double>(0.62, 0.45, 0.55)
        lit(ctx, CGPath(roundedRect: CGRect(x: -52, y: -190, width: 104, height: 160), cornerWidth: 48, cornerHeight: 48, transform: nil), fur, line: line, width: 3.5)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.82, blue: 0.88, alpha: 0.8))
        ctx.fillEllipse(in: CGRect(x: -28, y: -140, width: 56, height: 80))
        for s in [CGFloat(-1), 1] {
            lit(ctx, CGPath(ellipseIn: CGRect(x: s * 60 - 20, y: -80, width: 40, height: 32), transform: nil), fur, line: line, width: 2.5)
        }
        if let head = FingerGunsArt.sprite(.bunny, phase: 0) {
            ctx.draw(head, in: CGRect(x: -80, y: -64, width: 160, height: 160))
        }
    }
}
