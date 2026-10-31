import AppKit
import CoreGraphics
import simd

/// A big wall zooms toward the camera with a hole cut in it in the shape of a pose: stand left, stand right, arms up, arms out,
/// crouch. When the wall arrives, the part of your silhouette left over the solid wall is measured. Fit (nearly) all of yourself
/// through the hole and you pass, and the next wall comes faster; miss and the wall smashes into you and costs a life.
///
/// Every hole is made from how big you are and where you are standing when the wall starts to come, so it always fits.
struct HoleInTheWallGame: Game {
    static let title = "Hole in the Wall"
    static let hint = "A wall is coming! Strike the pose to fit through the hole."
    static let accent = SIMD3<Double>(0.42, 0.8, 1.0)
    /// The wall's own prompts teach the game ("Stand relaxed", "CROUCH!"), so the bottom of the picture is left to the fit meter.
    static let onboarding: [String] = []

    static let startingLives = 3
    static let firstApproach = 6.2
    static let fastestApproach = 3.4
    /// A breather between walls, when your normal shape is measured.
    static let readySeconds = 1.8
    /// How long before the next wall starts that it begins to be made.
    static let prepareSeconds = 1.0
    static let resultSeconds = 1.3
    static let tileColumns = 16
    static let tileRows = 9

    struct Wall {
        let hole: BodyHole
        let art: BodyWallArt
        var duration: Double
        /// 0 when it starts far away, 1 when it arrives.
        var progress = 0.0
        var age = 0.0

        var scale: Double { HoleInTheWallGame.scale(at: progress) }
    }

    /// A piece of a smashed wall.
    struct Chunk {
        var image: CGImage
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var rotation = 0.0
        var spin: Double
        var size: CGSize
        var age = 0.0
    }

    enum Stage: Equatable {
        /// Seconds until the next wall starts.
        case ready(Double)
        case approaching
        case result(passed: Bool, time: Double)
    }

    let size: CGSize
    private(set) var stage = Stage.ready(1.2)
    private(set) var wall: Wall?
    private(set) var lives = HoleInTheWallGame.startingLives
    private(set) var score = 0
    private(set) var passedWalls = 0
    private(set) var failedWalls = 0
    private(set) var streak = 0
    /// What your normal shape was when the last wall started.
    private(set) var reference: BodyFrame?
    /// How the body measures up against the wall on its way in, and finally when it arrives.
    private(set) var verdict: BodyHole.Verdict?
    private(set) var lastTemplate: BodyHole.Template?
    private(set) var wallsStarted = 0
    private(set) var finished = false

    /// The next wall, made during the breather a piece at a time so no single frame has to do all of it.
    private var pendingWall: Wall?
    private var candidates: [BodyHole.Template]?
    private var sinceScan = 1.0
    private var scan = BodyScan(matte: nil, size: CGSize(width: 16, height: 16))
    private var approach = HoleInTheWallGame.firstApproach
    private var chunks: [Chunk] = []
    private var confetti = ParticleSystem(capacity: 400)
    private var floaters: [BodyFloater] = []
    private var flash = 0.0
    private var shake = 0.0
    private var bannerText = ""
    private var bannerColor = NSColor.white
    private var bannerAge = 99.0
    private var sinceSmash = 99.0
    private var rng: SplitMix64

    var isOver: Bool { finished }
    var summary: String { "Lives \(lives) · Wall \(passedWalls + failedWalls + 1)" }

    var readout: GameUIReadout {
        GameUIReadout(score: score, lives: (max(0, lives), Self.startingLives), combo: streak >= 2 ? streak : 0, label: "Wall \(passedWalls + failedWalls + 1)")
    }

    var result: GameUIResult {
        let line: String
        switch passedWalls {
        case 0: line = "Copy the little figures: they show the pose"
        case 1..<6: line = "You fitted through \(passedWalls) \(passedWalls == 1 ? "wall" : "walls")"
        default: line = "Bendy! \(passedWalls) walls and counting"
        }
        return GameUIResult(headline: "Out of lives", line: line, stats: [("\(passedWalls)", "walls passed"), ("\(failedWalls)", "smashed"), ("\(score)", "points")])
    }
    /// Seconds a wall takes to come, now.
    var approachSeconds: Double { approach }

    /// How big the wall looks, 1 when it fills the picture. It comes at a steady speed, so it grows slowly at first and then fast.
    static func scale(at progress: Double) -> Double { 1 / (1 + 5 * (1 - bodyClamp(progress, 0, 1))) }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        confetti.gravity = SIMD2(0, -650)
        confetti.drag = 0.5
        let tile = (Int((size.width / Double(Self.tileColumns)).rounded()), Int((size.height / Double(Self.tileRows)).rounded()))
        BodyArtCache.warm("hole") { for style in 0..<BodyWallArt.styles { _ = BodyWallArt.cushion(style: style, width: tile.0, height: tile.1) } }
    }

    // MARK: Rules

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = bodyClamp(dt, 0, 0.1)
        advanceEffects(dt)

        // Looking at the whole picture is the costliest thing here, so while a wall is still far off, look every third frame or so.
        sinceScan += dt
        let close = (wall?.progress ?? 0) > 0.93
        var needsScan = sinceScan >= 0.1 || close
        switch stage {
        case .ready: needsScan = true
        case .result: needsScan = false
        case .approaching: break
        }
        if needsScan {
            scan = BodyScan(matte: world.matte, size: size, step: 16)
            sinceScan = 0
        }

        switch stage {
        case .ready(let left):
            if let frame = BodyFrame(scan: scan) {
                reference = reference.map { $0.blended(toward: frame, by: 1 - exp(-dt / 0.25)) } ?? frame
            }
            if left - dt <= Self.prepareSeconds { prepareNextWall() }
            if left - dt > 0 {
                stage = .ready(left - dt)
            } else if let next = pendingWall {
                wall = next
                lastTemplate = next.hole.template
                wallsStarted += 1
                pendingWall = nil
                candidates = nil
                verdict = nil
                stage = .approaching
            } else {
                stage = .ready(0.3)
            }

        case .approaching:
            guard var current = wall else { stage = .ready(0.5); return }
            // At the last moment, wait for someone to be there to judge.
            if current.progress >= 0.985, !scan.present { return }
            current.age += dt
            current.progress = min(1, current.progress + dt / current.duration)
            wall = current
            if current.scale > 0.4, scan.present, sinceScan == 0 { verdict = current.hole.judge(scan) }
            if current.progress >= 1 { resolve(scan) }

        case .result(let passed, let time):
            if time + dt >= Self.resultSeconds {
                wall = nil
                chunks.removeAll()
                if lives <= 0 {
                    finished = true
                } else {
                    stage = .ready(Self.readySeconds)
                }
            } else {
                stage = .result(passed: passed, time: time + dt)
            }
        }
    }

    private mutating func advanceEffects(_ dt: Double) {
        flash = max(0, flash - dt)
        shake = max(0, shake - dt)
        bannerAge += dt
        sinceSmash += dt
        confetti.step(dt)
        for i in chunks.indices {
            chunks[i].age += dt
            chunks[i].velocity.y -= 1500 * dt
            chunks[i].velocity *= max(0, 1 - 0.7 * dt)
            chunks[i].position += chunks[i].velocity * dt
            chunks[i].rotation += chunks[i].spin * dt
        }
        chunks.removeAll { $0.age > 1.2 }
        for i in floaters.indices { floaters[i].advance(dt) }
        floaters.removeAll { $0.isDone }
    }

    /// One small step toward the next wall: first the order to try shapes in, then one shape per call until one fits you, then
    /// its picture. Each call is cheap, so none of them is felt in a frame.
    private mutating func prepareNextWall() {
        guard let ref = reference else { return }
        if let pending = pendingWall {
            pending.art.prepare()
            return
        }
        guard var list = candidates else {
            // The first two walls ask for the easy things.
            let easy: [BodyHole.Template] = [.left, .right, .middle, .crouch]
            let pool = (passedWalls + failedWalls < 2 ? easy : BodyHole.Template.allCases).filter { $0 != lastTemplate }.shuffled(using: &rng)
            candidates = pool + BodyHole.Template.allCases.filter { !pool.contains($0) }.shuffled(using: &rng)
            return
        }
        guard !list.isEmpty else { return }
        let template = list.removeFirst()
        candidates = list
        guard let hole = BodyHole.make(template, around: ref, size: size, tight: min(1, Double(passedWalls) / 12)) else { return }
        let style = wallsStarted % BodyWallArt.styles
        pendingWall = Wall(hole: hole, art: BodyWallArt(hole: hole, style: style, size: size), duration: approach)
    }

    private mutating func resolve(_ scan: BodyScan) {
        guard let wall else { return }
        let result = wall.hole.judge(scan)
        verdict = result
        if result.passed {
            passedWalls += 1
            streak += 1
            let points = 10 + (result.perfect ? 5 : 0) + min(10, (streak - 1) * 2)
            score += points
            approach = max(Self.fastestApproach, approach * 0.93)
            cheer(points: points, perfect: result.perfect, scan: scan)
            stage = .result(passed: true, time: 0)
        } else {
            lives = max(0, lives - 1)
            failedWalls += 1
            streak = 0
            smash(wall, scan: scan)
            stage = .result(passed: false, time: 0)
        }
    }

    private mutating func cheer(points: Int, perfect: Bool, scan: BodyScan) {
        banner(perfect ? "PERFECT!  +\(points)" : "NICE!  +\(points)", color: perfect ? BodyGamePalette.gold : BodyGamePalette.mint)
        let spots = scan.solidPoints(every: 7)
        for _ in 0..<56 where !spots.isEmpty {
            let p = spots[Int.random(in: 0..<spots.count, using: &rng)]
            let angle = Double.random(in: 0.2..<(.pi - 0.2), using: &rng), speed = Double.random(in: 200...620, using: &rng)
            confetti.emit(Particle(position: SIMD2(Double(p.x), Double(p.y)), velocity: SIMD2(cos(angle) * speed * 0.8, sin(angle) * speed),
                                   life: Double.random(in: 0.8...1.4, using: &rng), size: Double.random(in: 4...8, using: &rng),
                                   hue: Double.random(in: 0..<1, using: &rng)))
        }
    }

    private mutating func smash(_ wall: Wall, scan: BodyScan) {
        flash = 0.6
        shake = 0.5
        sinceSmash = 0
        banner("SMASH!", color: BodyGamePalette.coral)

        // The wall breaks outward from where you hit it.
        var sumX = 0.0, sumY = 0.0, weight = 0.0
        for gy in 0..<scan.rows {
            for gx in 0..<scan.columns {
                let w = scan.weight(gx, gy), p = scan.center(gx, gy)
                if w > 0.3, !wall.hole.contains(p) { sumX += p.x * w; sumY += p.y * w; weight += w }
            }
        }
        let impact = weight > 0 ? CGPoint(x: sumX / weight, y: sumY / weight) : scan.centroid
        guard let image = wall.art.image else { return }
        let tileW = size.width / Double(Self.tileColumns), tileH = size.height / Double(Self.tileRows)
        for row in 0..<Self.tileRows {
            for column in 0..<Self.tileColumns {
                let tile = CGRect(x: Double(column) * tileW, y: Double(row) * tileH, width: tileW, height: tileH)
                let corners = [CGPoint(x: tile.minX, y: tile.minY), CGPoint(x: tile.maxX, y: tile.minY),
                               CGPoint(x: tile.minX, y: tile.maxY), CGPoint(x: tile.maxX, y: tile.maxY), CGPoint(x: tile.midX, y: tile.midY)]
                if corners.allSatisfy({ wall.hole.contains($0) }) { continue }
                // Pictures are cropped from the top left, but the wall was drawn from the bottom left.
                guard let piece = image.cropping(to: CGRect(x: tile.minX, y: size.height - tile.maxY, width: tileW, height: tileH)) else { continue }
                let away = SIMD2(tile.midX - impact.x, tile.midY - impact.y)
                let distance = max(1, simd_length(away))
                let speed = 500 + 1100 * exp(-distance / 380) + Double.random(in: 0...260, using: &rng)
                chunks.append(Chunk(image: piece, position: SIMD2(tile.midX, tile.midY),
                                    velocity: away / distance * speed + SIMD2(0, Double.random(in: 120...420, using: &rng)),
                                    spin: Double.random(in: -6...6, using: &rng), size: CGSize(width: tileW, height: tileH)))
            }
        }
        for _ in 0..<40 {
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng), speed = Double.random(in: 200...700, using: &rng)
            confetti.emit(Particle(position: SIMD2(impact.x, impact.y), velocity: SIMD2(cos(angle), sin(angle)) * speed,
                                   life: Double.random(in: 0.4...0.9, using: &rng), size: Double.random(in: 3...7, using: &rng), hue: 0.08, kind: 1))
        }
    }

    private mutating func banner(_ text: String, color: NSColor) {
        bannerText = text
        bannerColor = color
        bannerAge = 0
    }

    // MARK: Test hooks

    /// Starts a wall of this shape now, built around `reference` (or around the shape last measured).
    @discardableResult
    mutating func startWall(_ template: BodyHole.Template, around frame: BodyFrame? = nil, validate: Bool = true) -> Bool {
        if let frame { reference = frame }
        guard let ref = reference,
              let hole = BodyHole.make(template, around: ref, size: size, tight: min(1, Double(passedWalls) / 12), validate: validate) else { return false }
        wall = Wall(hole: hole, art: BodyWallArt(hole: hole, style: 0, size: size), duration: approach)
        lastTemplate = template
        wallsStarted += 1
        stage = .approaching
        return true
    }

    /// Makes the wall arrive on the next step.
    mutating func arriveNow() {
        guard var current = wall else { return }
        current.progress = 1 - 1e-6
        wall = current
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        ctx.saveGState()
        let nudge = BodyGameHUD.shake(left: shake, total: 0.5, time: time)
        ctx.translateBy(x: nudge.width, y: nudge.height)
        if let wall {
            switch stage {
            case .approaching: drawWall(wall, alpha: 1, grow: 1, in: ctx)
            case .result(let passed, let t) where passed:
                // The wall rushes past you: it swells and fades.
                let fade = max(0, 1 - t / 0.45)
                if fade > 0 { drawWall(wall, alpha: fade, grow: 1 + 0.12 * BodyEase.outCubic(t / 0.45), in: ctx) }
            default: break
            }
        }
        for chunk in chunks { drawChunk(chunk, in: ctx) }
        for p in confetti.particles {
            let fade = CGFloat(1 - p.progress * p.progress)
            if p.kind == 1 {
                ctx.setAlpha(fade)
                ctx.fillCircle(center: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * (1 - 0.4 * p.progress),
                               color: CGColor(red: 1, green: 0.78 - 0.3 * p.progress, blue: 0.4, alpha: 1))
            } else {
                // Confetti: little flat cards that flutter as they fall.
                let colour = HoleConfetti.colours[Int(p.hue * 100) % HoleConfetti.colours.count]
                let flutter = sin(p.age * 14 + p.hue * 40)
                ctx.saveGState()
                ctx.translateBy(x: p.position.x, y: p.position.y)
                ctx.rotate(by: CGFloat(p.age * 5 + p.hue * 20))
                ctx.setAlpha(fade)
                ctx.setFillColor(BodyGamePalette.cg(colour))
                ctx.fill(CGRect(x: -p.size, y: -p.size * 0.6 * abs(flutter) - 0.6, width: p.size * 2, height: p.size * 1.2 * abs(flutter) + 1.2))
                ctx.restoreGState()
            }
        }
        ctx.setAlpha(1)
        ctx.restoreGState()

        BodyGameHUD.flash(ctx, size: size, strength: flash / 0.6)
        drawLabel(in: ctx, time: time)
        if case .approaching = stage, let wall, wall.scale > 0.4, let verdict, verdict.hasBody { drawFit(verdict, in: ctx) }
        BodyGameHUD.banner(ctx, bannerText, age: bannerAge, size: size, color: bannerColor, life: 1.25)
        for floater in floaters { floater.draw(in: ctx) }
    }

    private func drawWall(_ wall: Wall, alpha: Double, grow: Double, in ctx: CGContext) {
        guard let image = wall.art.image else { return }
        let s = wall.scale * grow
        let w = size.width * s, h = size.height * s
        let rect = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
        // Far away it is see-through, so you can still see yourself while it grows; solid by the time it is close.
        let distance = bodyClamp(0.45 + s * 0.8, 0, 1)
        let appear = alpha * BodyEase.outCubic(wall.age / 0.5) * distance
        if s < 0.97 {
            // A soft shadow round a small wall so it stands out from any picture.
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -8 * s), blur: 30 * s + 6, color: CGColor(red: 0, green: 0, blue: 0.05, alpha: CGFloat(0.55 * appear)))
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: CGFloat(0.01)))
            ctx.fill(rect.insetBy(dx: 4, dy: 4))
            ctx.restoreGState()
        }
        ctx.setAlpha(CGFloat(appear))
        ctx.draw(image, in: rect)
        ctx.setAlpha(1)
    }

    private func drawChunk(_ chunk: Chunk, in ctx: CGContext) {
        let fade = bodyClamp((1.2 - chunk.age) / 0.6, 0, 1)
        let grow = 1 + chunk.age * 0.6
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(chunk.position.x), y: CGFloat(chunk.position.y))
        ctx.rotate(by: CGFloat(chunk.rotation))
        ctx.setAlpha(CGFloat(fade))
        let w = chunk.size.width * CGFloat(grow), h = chunk.size.height * CGFloat(grow)
        ctx.draw(chunk.image, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        ctx.restoreGState()
    }

    /// What the wall is asking for, at the top, with a little figure doing it on each side.
    private func drawLabel(in ctx: CGContext, time: Double) {
        guard !finished else { return }
        let middle = BodyGameHUD.promptCenter(size)
        switch stage {
        case .approaching:
            guard let wall else { return }
            let template = wall.hole.template
            let enter = BodyEase.outBack(wall.age / 0.35)
            let fontSize = CGFloat(52 * (0.7 + 0.3 * enter))
            BodyGameHUD.pill(ctx, template.label, center: middle, size: fontSize, color: BodyGamePalette.cream, accent: BodyGamePalette.gold,
                             alpha: CGFloat(min(1, wall.age / 0.2)))
            let half = BodyGameHUD.width(of: template.label, size: fontSize) / 2 + fontSize * 0.55 + 58
            let sway = CGFloat(sin(time * 4) * 3)
            Self.drawFigure(template, at: CGPoint(x: middle.x - half, y: middle.y + sway), in: ctx)
            Self.drawFigure(template, at: CGPoint(x: middle.x + half, y: middle.y - sway), in: ctx)
        case .ready:
            BodyGameHUD.pill(ctx, "Stand relaxed", center: middle, size: 40, color: BodyGamePalette.sky)
        case .result:
            break
        }
    }

    private func drawFit(_ verdict: BodyHole.Verdict, in ctx: CGContext) {
        let match = verdict.match
        let colour: NSColor = verdict.passed ? BodyGamePalette.mint : match >= 0.7 ? BodyGamePalette.gold : BodyGamePalette.coral
        var text = "FIT \(Int((match * 100).rounded()))%"
        if verdict.passed { text += "  ✓" } else if let advice = verdict.advice { text += "  \(advice)" }
        let middle = BodyGameHUD.meterCenter(size)
        BodyGameHUD.pill(ctx, text, center: CGPoint(x: middle.x, y: middle.y + 22), size: 32, color: colour)
        BodyGameHUD.meter(ctx, center: CGPoint(x: middle.x, y: middle.y - 22), width: 300, fraction: match, color: colour,
                          mark: 1 - BodyHole.allowedOutside, height: 12)
    }

    /// A little figure doing the pose, so the label can be read at a glance without reading.
    static func drawFigure(_ template: BodyHole.Template, at c: CGPoint, in ctx: CGContext) {
        var lines: [(CGPoint, CGPoint)] = []
        var headCenter = CGPoint(x: c.x, y: c.y + 30)
        var shift = CGFloat(0)
        switch template {
        case .left: shift = -14
        case .right: shift = 14
        default: break
        }
        let hip = CGPoint(x: c.x + shift, y: c.y - 8), neck = CGPoint(x: c.x + shift, y: c.y + 18)
        headCenter.x += shift
        var arrow: (CGPoint, CGPoint)?
        switch template {
        case .crouch:
            headCenter = CGPoint(x: c.x - 4, y: c.y + 2)
            let neckLow = CGPoint(x: c.x - 4, y: c.y - 10), hipLow = CGPoint(x: c.x - 4, y: c.y - 22)
            lines = [(neckLow, hipLow),
                     (hipLow, CGPoint(x: c.x - 18, y: c.y - 30)), (CGPoint(x: c.x - 18, y: c.y - 30), CGPoint(x: c.x - 12, y: c.y - 40)),
                     (hipLow, CGPoint(x: c.x + 10, y: c.y - 30)), (CGPoint(x: c.x + 10, y: c.y - 30), CGPoint(x: c.x + 4, y: c.y - 40)),
                     (neckLow, CGPoint(x: c.x - 20, y: c.y - 20)), (neckLow, CGPoint(x: c.x + 12, y: c.y - 20))]
            arrow = (CGPoint(x: c.x + 28, y: c.y + 26), CGPoint(x: c.x + 28, y: c.y - 6))
        default:
            lines = [(neck, hip), (hip, CGPoint(x: hip.x - 10, y: c.y - 38)), (hip, CGPoint(x: hip.x + 10, y: c.y - 38))]
            switch template {
            case .armsUp:
                lines += [(neck, CGPoint(x: neck.x - 18, y: c.y + 46)), (neck, CGPoint(x: neck.x + 18, y: c.y + 46))]
            case .armsOut:
                lines += [(CGPoint(x: neck.x, y: neck.y - 4), CGPoint(x: neck.x - 32, y: neck.y - 2)),
                          (CGPoint(x: neck.x, y: neck.y - 4), CGPoint(x: neck.x + 32, y: neck.y - 2))]
            default:
                lines += [(neck, CGPoint(x: neck.x - 13, y: c.y - 10)), (neck, CGPoint(x: neck.x + 13, y: c.y - 10))]
            }
        }
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for pass in 0..<2 {
            let ink = pass == 0
            ctx.setStrokeColor(ink ? BodyGamePalette.cg(BodyGamePalette.ink, 0.6) : BodyGamePalette.cg(BodyGamePalette.cream))
            ctx.setFillColor(ink ? BodyGamePalette.cg(BodyGamePalette.ink, 0.6) : BodyGamePalette.cg(BodyGamePalette.cream))
            ctx.setLineWidth(ink ? 13 : 7)
            for (a, b) in lines {
                ctx.move(to: a)
                ctx.addLine(to: b)
            }
            ctx.strokePath()
            let r: CGFloat = ink ? 13 : 10
            ctx.fillEllipse(in: CGRect(x: headCenter.x - r, y: headCenter.y - r, width: r * 2, height: r * 2))
        }
        if let (from, to) = arrow {
            ctx.setStrokeColor(BodyGamePalette.cg(BodyGamePalette.gold))
            ctx.setLineWidth(5)
            ctx.move(to: from)
            ctx.addLine(to: to)
            ctx.move(to: CGPoint(x: to.x - 8, y: to.y + 9))
            ctx.addLine(to: to)
            ctx.addLine(to: CGPoint(x: to.x + 8, y: to.y + 9))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}

/// The confetti colours for a wall you fit through.
private enum HoleConfetti {
    static let colours = [BodyGamePalette.gold, BodyGamePalette.mint, BodyGamePalette.sky, BodyGamePalette.coral, BodyGamePalette.violet,
                          BodyGamePalette.tangerine]
}

/// A wall's picture, drawn the first time it is needed: padded game-show cushions with a lit bevel, and the hole cut clean through.
/// Each cushion is drawn once per colour and stamped, so building a whole wall is cheap.
final class BodyWallArt {
    /// The wall colours, in turn: a named set so walls never come out muddy.
    static let palette: [NSColor] = [
        NSColor(red: 0.30, green: 0.62, blue: 0.98, alpha: 1),   // pool blue
        NSColor(red: 0.98, green: 0.45, blue: 0.42, alpha: 1),   // coral
        NSColor(red: 0.62, green: 0.46, blue: 0.98, alpha: 1),   // grape
        NSColor(red: 0.26, green: 0.80, blue: 0.62, alpha: 1),   // jade
        NSColor(red: 1.00, green: 0.66, blue: 0.26, alpha: 1),   // tangerine
        NSColor(red: 0.22, green: 0.76, blue: 0.86, alpha: 1),   // lagoon
    ]
    static var styles: Int { palette.count }

    private let hole: BodyHole
    private let style: Int
    private let size: CGSize
    private var made: CGImage?
    private var canvas: CGContext?
    /// How far the drawing has got: rows of cushions first, then the finish.
    private var stage = 0

    init(hole: BodyHole, style: Int, size: CGSize) {
        self.hole = hole
        self.style = ((style % Self.styles) + Self.styles) % Self.styles
        self.size = size
    }

    private var colour: NSColor { Self.palette[style] }

    /// Draws the next part of the picture: a few rows of cushions, or the finish. Called once a frame while the next wall is being
    /// readied, so no single frame pays for the whole picture.
    func prepare() {
        guard made == nil else { return }
        if canvas == nil {
            canvas = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: Sprites.bitmapInfo)
            canvas?.setAllowsAntialiasing(true)
            canvas?.interpolationQuality = .high
        }
        guard let ctx = canvas else { stage = 99; return }
        let rows = HoleInTheWallGame.tileRows, perStage = 3
        if stage * perStage < rows {
            layCushions(ctx, rows: (stage * perStage)..<min(rows, (stage + 1) * perStage))
            stage += 1
        } else {
            finish(ctx)
            made = ctx.makeImage()
            canvas = nil
        }
    }

    /// Whether the picture is done.
    var isReady: Bool { made != nil || stage >= 99 }

    var image: CGImage? {
        while !isReady { prepare() }
        return made
    }

    /// One padded cushion: lit from the top left, a button pulling the middle in, and soft creases running to it.
    static func cushion(style: Int, width: Int, height: Int) -> CGImage? {
        let colour = palette[((style % styles) + styles) % styles]
        return BodyArtCache.image("wall-cushion-\(style)-\(width)x\(height)", width: width, height: height) { ctx in
            let w = CGFloat(width), h = CGFloat(height)
            let rect = CGRect(x: 3, y: 3, width: w - 6, height: h - 6)
            let shape = CGPath(roundedRect: rect, cornerWidth: 16, cornerHeight: 16, transform: nil)
            // The seam between cushions, in shadow.
            ctx.setFillColor(colour.bodyShade(-0.72))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.saveGState()
            ctx.addPath(shape)
            ctx.clip()
            BodyShapes.fillLit(ctx, rect, light: colour.bodyShade(0.42), body: colour.bodyShade(0), shade: colour.bodyShade(-0.42),
                               lightAt: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.78))
            // The cushion pulled in toward its button: darker creases from the corners.
            let mid = CGPoint(x: rect.midX, y: rect.midY)
            ctx.setLineCap(.round)
            for (cx, cy) in [(rect.minX + 10, rect.minY + 10), (rect.maxX - 10, rect.minY + 10), (rect.minX + 10, rect.maxY - 10), (rect.maxX - 10, rect.maxY - 10)] {
                let lit = cx < mid.x && cy > mid.y
                ctx.setStrokeColor(lit ? CGColor(red: 1, green: 1, blue: 1, alpha: 0.18) : colour.bodyShade(-0.5).copy(alpha: 0.4) ?? colour.bodyShade(-0.5))
                ctx.setLineWidth(3)
                ctx.move(to: CGPoint(x: cx, y: cy))
                ctx.addQuadCurve(to: CGPoint(x: mid.x + (cx - mid.x) * 0.18, y: mid.y + (cy - mid.y) * 0.18),
                                 control: CGPoint(x: (cx + mid.x) / 2 + 3, y: (cy + mid.y) / 2 - 3))
                ctx.strokePath()
            }
            // A soft shade in the lower right, as cushions bulge toward the light.
            ctx.glow(center: CGPoint(x: rect.maxX - 6, y: rect.minY + 6), radius: rect.width * 0.5, red: 0, green: 0, blue: 0.08, alpha: 0.22)
            ctx.restoreGState()
            // The rim: bright along the top and left.
            ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 15, cornerHeight: 15, transform: nil))
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
            ctx.setLineWidth(2)
            ctx.strokePath()
            // The button.
            let b = CGRect(x: rect.midX - 7, y: rect.midY - 7, width: 14, height: 14)
            ctx.setFillColor(colour.bodyShade(-0.55))
            ctx.fillEllipse(in: b.offsetBy(dx: 1, dy: -1.5))
            ctx.saveGState()
            ctx.addEllipse(in: b)
            ctx.clip()
            BodyShapes.fillLit(ctx, b, light: colour.bodyShade(0.55), body: colour.bodyShade(0.05), shade: colour.bodyShade(-0.4))
            ctx.restoreGState()
        }
    }

    private func layCushions(_ ctx: CGContext, rows: Range<Int>) {
        let tileW = size.width / Double(HoleInTheWallGame.tileColumns), tileH = size.height / Double(HoleInTheWallGame.tileRows)
        guard let cushion = Self.cushion(style: style, width: Int(tileW.rounded()), height: Int(tileH.rounded())) else {
            ctx.setFillColor(colour.bodyShade(-0.2))
            ctx.fill(CGRect(x: 0, y: Double(rows.lowerBound) * tileH, width: size.width, height: Double(rows.count) * tileH))
            return
        }
        for row in rows {
            for column in 0..<HoleInTheWallGame.tileColumns {
                ctx.draw(cushion, in: CGRect(x: Double(column) * tileW, y: Double(row) * tileH, width: tileW, height: tileH))
            }
        }
    }

    private func finish(_ ctx: CGContext) {
        let all = CGRect(origin: .zero, size: size)
        // Darker toward the corners, so it feels like a thing with depth.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let shade = [CGColor(red: 0, green: 0, blue: 0, alpha: 0), CGColor(red: 0, green: 0, blue: 0.05, alpha: 0.3)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: shade, locations: [0, 1]) {
            let middle = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.drawRadialGradient(gradient, startCenter: middle, startRadius: size.height * 0.4, endCenter: middle,
                                   endRadius: hypot(size.width, size.height) / 2, options: [.drawsAfterEndLocation])
        }
        // The frame round the edge: a dark rail with a bright lip.
        ctx.setStrokeColor(colour.bodyShade(-0.68))
        ctx.setLineWidth(22)
        ctx.stroke(all.insetBy(dx: 11, dy: 11))
        ctx.setStrokeColor(colour.bodyShade(0.6).copy(alpha: 0.6) ?? colour.bodyShade(0.6))
        ctx.setLineWidth(3)
        ctx.stroke(all.insetBy(dx: 23, dy: 23))

        // The thickness of the wall seen at the edge of the hole: a shadow, a lit face, and a bright lip. The hole is cut after,
        // which removes the half of each stroke that falls inside it.
        for (width, shadeColour, alpha) in [(CGFloat(64), colour.bodyShade(-0.78), CGFloat(0.55)), (CGFloat(34), colour.bodyShade(0.5), CGFloat(0.95)),
                                            (CGFloat(10), CGColor(red: 1, green: 0.98, blue: 0.94, alpha: 1), CGFloat(0.9))] {
            for part in hole.parts {
                ctx.addPath(part.path)
                ctx.setStrokeColor(shadeColour.copy(alpha: alpha) ?? shadeColour)
                ctx.setLineWidth(width)
                ctx.setLineJoin(.round)
                ctx.strokePath()
            }
        }
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        for part in hole.parts {
            ctx.addPath(part.path)
            ctx.fillPath()
        }
        ctx.restoreGState()
    }
}
