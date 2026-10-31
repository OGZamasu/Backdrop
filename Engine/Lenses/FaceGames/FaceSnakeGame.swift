import AppKit
import CoreGraphics
import simd

/// Snake with your nose. The snake's head is your face and it swims after your nose at a steady speed, turning as fast as a
/// snake can. Eat the fruit to grow; bite your own tail and it is over. The picture wraps around: swim off one edge and you
/// come back in at the other.
///
/// The score is the fruit eaten. Every piece makes the snake a little quicker.
struct FaceSnakeGame: FaceGame {
    static let title = "Face Snake"
    static let hint = "Steer with your nose. Eat the fruit, don't bite your tail!"
    static let presenceHint = "Look into the camera to play"
    static let wantsFaceCrop = true
    static let move = FaceGameMove.steerNose
    static let accent = FaceGamePalette.mint
    static let scoreLabel = "FRUIT"

    static let headRadius = 46.0
    static let bodyRadius = 25.0
    static let fruitRadius = 40.0
    static let segmentSpacing = 26.0
    /// The tightest circle it can turn in, whatever its speed.
    static let turnRadius = 100.0
    static let baseSpeed = 290.0
    static let topSpeed = 430.0
    static let startSegments = 6
    static let growth = 3
    /// The first few segments behind the head are its neck: the head can't bite them, so a tight turn is safe.
    static let neckSegments = 6
    /// How far the snake's goal moves for each eye-spacing your nose moves, so small movements of your head reach the whole picture.
    static let reachPerEyeSpacing = 150.0
    static let fruitKinds: [FaceGameFood.Kind] = [.apple, .banana, .grapes, .strawberry, .orange, .cherries, .watermelon, .pear]

    struct Fruit: Equatable {
        var position: SIMD2<Double>
        /// Which of `fruitKinds` it is.
        var variant: Int
        var age = 0.0
    }

    let size: CGSize
    private(set) var head: SIMD2<Double>
    private(set) var heading = 0.0
    private(set) var speed = FaceSnakeGame.baseSpeed
    /// Where the snake is heading for: your nose, mapped onto the picture and smoothed.
    private(set) var aim: SIMD2<Double>
    /// The middle of each segment from the neck back, in the same space as the head.
    private(set) var body: [SIMD2<Double>] = []
    private(set) var fruit: [Fruit] = []
    private(set) var score = 0
    private(set) var isOver = false
    private(set) var elapsed = 0.0

    /// Where the head has been, newest first. The body is laid along this.
    private var trail: [SIMD2<Double>] = []
    private var targetSegments = FaceSnakeGame.startSegments
    private var anchor: SIMD2<Double>?
    private var anchorSpacing = 1.0
    private var crop: CGImage?
    private var rng: SplitMix64
    private var gulp = 0.0
    private var juice = ParticleSystem(capacity: 300)
    private var floaters: [FaceGameFloater] = []

    var summary: String { "Length \(body.count + 1)" }

    var chips: [FaceGameChip] { [.text("LENGTH \(body.count + 1)")] }
    var ending: FaceGameEnding { .lost("TAIL BITTEN!") }
    var endLine: String { "You grew to \(body.count + 1) long" }
    var tip: String? { elapsed < 4.5 ? "Point your nose where to swim" : nil }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        head = SIMD2(size.width / 2, size.height / 2)
        aim = head
        juice.gravity = SIMD2(0, -500)
        juice.drag = 1.2
        layTrailBehindHead()
        refreshBody()
        for _ in 0..<2 { fruit.append(makeFruit()) }
    }

    // MARK: Rules

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.1)
        if let crop = world.faceCrop { self.crop = crop }
        guard !isOver else { return }
        // The snake waits for a face to steer it.
        guard let face = world.face else { return }

        elapsed += dt
        gulp = max(0, gulp - dt * 4)
        speed = min(Self.topSpeed, Self.baseSpeed + 5 * Double(score))
        steer(toward: face, dt: dt)

        var left = dt
        while left > 1e-9, !isOver {
            let h = min(left, 1.0 / 120)
            swim(h)
            left -= h
        }
        if !isOver { eatIfTouching() }
        for i in fruit.indices { fruit[i].age += dt }
        juice.step(dt)
        FaceGamePaint.advance(&floaters, by: dt)
    }

    /// Maps the nose onto the picture: wherever your nose was at the start is the middle, and a bit of movement goes a long way.
    private mutating func steer(toward face: FaceState, dt: Double) {
        let nose = SIMD2(Double(face.nose.x), Double(face.nose.y))
        if anchor == nil {
            anchor = nose
            anchorSpacing = max(face.interocular, 20)
        }
        let gain = min(3.2, max(1.2, Self.reachPerEyeSpacing / anchorSpacing))
        var want = SIMD2(size.width / 2, size.height / 2) + (nose - (anchor ?? nose)) * gain
        want.x = min(size.width - 30, max(30, want.x))
        want.y = min(size.height - 30, max(30, want.y))
        aim += (want - aim) * (1 - exp(-dt / 0.06))
    }

    private mutating func swim(_ h: Double) {
        let toAim = aim - head
        if simd_length(toAim) > 4 {
            let wanted = atan2(toAim.y, toAim.x)
            let turn = Self.angleBetween(heading, wanted)
            let most = speed / Self.turnRadius * h
            heading += max(-most, min(most, turn))
        }
        head += SIMD2(cos(heading), sin(heading)) * speed * h

        if let last = trail.first, simd_length(head - last) >= 6 { trail.insert(head, at: 0) }
        wrapIfNeeded()
        refreshBody()
        for (index, segment) in body.enumerated() where index >= Self.neckSegments {
            if simd_length(delta(head, segment)) < Self.headRadius * 0.55 + Self.bodyRadius * 0.8 {
                isOver = true
                burst(at: head, count: 30, variant: -1)
                return
            }
        }
    }

    /// Head and trail slide together when the head goes off an edge, so the body stays in one piece.
    private mutating func wrapIfNeeded() {
        var shift = SIMD2<Double>.zero
        if head.x < 0 { shift.x = size.width } else if head.x >= size.width { shift.x = -size.width }
        if head.y < 0 { shift.y = size.height } else if head.y >= size.height { shift.y = -size.height }
        guard shift != .zero else { return }
        head += shift
        for i in trail.indices { trail[i] += shift }
    }

    private mutating func layTrailBehindHead() {
        trail = (1...Int(Double(Self.startSegments + 4) * Self.segmentSpacing / 6)).map { SIMD2(head.x - Double($0) * 6, head.y) }
        trail.insert(head, at: 0)
    }

    /// Lays the segments along the trail, one spacing apart, and drops the trail beyond the tail.
    private mutating func refreshBody() {
        var points: [SIMD2<Double>] = []
        var previous = head
        var carried = 0.0
        var keep = trail.count
        let wanted = targetSegments
        for (index, p) in trail.enumerated() {
            var from = previous
            var run = simd_length(p - from)
            while carried + run >= Self.segmentSpacing, points.count < wanted {
                let used = Self.segmentSpacing - carried
                let dir = (p - from) / max(run, 1e-9)
                from += dir * used
                points.append(from)
                run -= used
                carried = 0
            }
            carried += run
            previous = p
            if points.count >= wanted { keep = index + 2; break }
        }
        body = points
        if keep < trail.count { trail.removeLast(trail.count - keep) }
    }

    private func delta(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> SIMD2<Double> {
        var d = a - b
        if d.x > size.width / 2 { d.x -= size.width } else if d.x < -size.width / 2 { d.x += size.width }
        if d.y > size.height / 2 { d.y -= size.height } else if d.y < -size.height / 2 { d.y += size.height }
        return d
    }

    static func angleBetween(_ from: Double, _ to: Double) -> Double {
        var d = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi } else if d < -.pi { d += 2 * .pi }
        return d
    }

    private mutating func eatIfTouching() {
        var kept: [Fruit] = []
        var ate = 0
        for piece in fruit {
            if simd_length(delta(head, piece.position)) < Self.headRadius * 0.7 + Self.fruitRadius {
                ate += 1
                score += 1
                targetSegments += Self.growth
                gulp = 1
                burst(at: piece.position, count: 22, variant: piece.variant)
                floaters.append(FaceGameFloater(text: "+1", position: piece.position + SIMD2(0, 60), tone: FaceGamePalette.sun))
            } else {
                kept.append(piece)
            }
        }
        fruit = kept
        speed = min(Self.topSpeed, Self.baseSpeed + 5 * Double(score))
        for _ in 0..<ate { fruit.append(makeFruit()) }
        if ate > 0 { refreshBody() }
    }

    /// A new piece of fruit somewhere open: away from the head, the body and the other fruit, and clear of the score.
    private mutating func makeFruit() -> Fruit {
        var spot = SIMD2(size.width / 2, size.height / 2)
        for _ in 0..<40 {
            spot = SIMD2(Double.random(in: 110...(size.width - 110), using: &rng), Double.random(in: 90...(size.height - 140), using: &rng))
            let clearOfHead = simd_length(delta(spot, head)) > 220
            let clearOfBody = body.allSatisfy { simd_length(delta(spot, $0)) > 80 }
            let clearOfFruit = fruit.allSatisfy { simd_length($0.position - spot) > 180 }
            if clearOfHead, clearOfBody, clearOfFruit { break }
        }
        return Fruit(position: spot, variant: Int.random(in: 0..<Self.fruitKinds.count, using: &rng))
    }

    /// Juice in the fruit's own colour; `variant` -1 is the red of a bite.
    private mutating func burst(at p: SIMD2<Double>, count: Int, variant: Int) {
        for _ in 0..<count {
            let a = Double.random(in: 0..<(2 * .pi), using: &rng), v = Double.random(in: 120...460, using: &rng)
            juice.emit(Particle(position: p, velocity: SIMD2(cos(a), sin(a)) * v, life: Double.random(in: 0.4...0.9, using: &rng),
                                size: Double.random(in: 5...15, using: &rng), hue: Double.random(in: 0...1, using: &rng), kind: variant))
        }
    }

    /// After the bite: the juice settles and the words fade.
    mutating func settle(_ dt: Double) {
        juice.step(dt)
        FaceGamePaint.advance(&floaters, by: dt)
    }

    // MARK: Test hooks

    /// Replaces the fruit with pieces at these points.
    mutating func place(fruitAt points: [CGPoint]) {
        fruit = points.enumerated().map { Fruit(position: SIMD2(Double($1.x), Double($1.y)), variant: $0 % Self.fruitKinds.count) }
    }

    /// Puts the head at a point facing a direction, with the body straight out behind it.
    mutating func place(head point: CGPoint, heading angle: Double) {
        head = SIMD2(Double(point.x), Double(point.y))
        heading = angle
        aim = head
        let back = SIMD2(-cos(angle), -sin(angle))
        trail = (0...Int(Double(targetSegments + 4) * Self.segmentSpacing / 6)).map { head + back * Double($0) * 6 }
        refreshBody()
    }

    /// Makes the snake `segments` longer at once.
    mutating func grow(by segments: Int) {
        targetSegments += segments
        var tail = trail.last ?? head
        let back = trail.count > 1 ? simd_normalize(tail - trail[trail.count - 2]) : SIMD2(-1, 0)
        for _ in 0..<Int(Double(segments) * Self.segmentSpacing / 6) {
            tail += back * 6
            trail.append(tail)
        }
        refreshBody()
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        drawRim(ctx, time: time)
        for piece in fruit { drawFruit(piece, ctx, time: time) }
        drawBody(ctx)
        drawHead(ctx, time: time)
        for p in juice.particles {
            let tone = p.kind >= 0 ? Self.fruitKinds[p.kind % Self.fruitKinds.count].juice : FaceGamePalette.coral
            FaceGamePaint.spark(ctx, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * (1 - 0.4 * p.progress),
                                tone: FaceGamePaint.mix(tone, FaceGamePalette.cream, p.hue * 0.3), alpha: 1 - p.progress)
        }
        if !isOver { drawAim(ctx, time: time) }
        FaceGamePaint.draw(floaters, in: ctx)
    }

    /// A quiet dotted border, so you can see where the picture ends and that it wraps.
    private func drawRim(_ ctx: CGContext, time: Double) {
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineDash(phase: CGFloat(time * 24), lengths: [1, 26])
        FaceGamePaint.stroke(ctx, rounded: rect, radius: 30, color: FaceGamePaint.cg(FaceGamePalette.mint, 0.8), width: 7)
        ctx.restoreGState()
    }

    /// Draws something where it is, and again on the far side if it straddles an edge.
    private func visit(_ p: SIMD2<Double>, radius: Double, _ draw: (CGPoint) -> Void) {
        let x = FaceGamePaint.wrap(p.x, size.width), y = FaceGamePaint.wrap(p.y, size.height)
        let dx: Double = x < radius ? size.width : (x > size.width - radius ? -size.width : 0)
        let dy: Double = y < radius ? size.height : (y > size.height - radius ? -size.height : 0)
        draw(CGPoint(x: x, y: y))
        if dx != 0 { draw(CGPoint(x: x + dx, y: y)) }
        if dy != 0 { draw(CGPoint(x: x, y: y + dy)) }
        if dx != 0, dy != 0 { draw(CGPoint(x: x + dx, y: y + dy)) }
    }

    private func drawFruit(_ piece: Fruit, _ ctx: CGContext, time: Double) {
        let pop = FaceGameEase.backOut(min(1, piece.age / 0.35), overshoot: 2.2)
        let bob = sin(time * 3 + Double(piece.variant)) * 5
        let c = CGPoint(x: piece.position.x, y: piece.position.y + bob)
        let kind = Self.fruitKinds[piece.variant % Self.fruitKinds.count]
        FaceGameArt.contactShadow(ctx, center: CGPoint(x: c.x + 6, y: piece.position.y - 40), width: 70 * pop, height: 16 * pop, alpha: 0.35)
        FaceGamePaint.spark(ctx, at: c, radius: 80 * pop, tone: kind.juice, alpha: 0.35)
        FaceGameArt.stamp(ctx, FaceGameFood.sprite(kind), at: c, height: 96 * max(0.01, pop), rotation: sin(time * 2 + Double(piece.variant)) * 0.14)
    }

    /// One bead of the body, lit, in one of a few shades from the neck to the tail, drawn at the exact size it is shown so it
    /// goes down without any resampling. With `edge` it is just the dark rim, a little larger, laid down first for the whole body
    /// so the body reads as one tube with scales rather than a stack of rings.
    private static func bead(_ shade: Int, band: Bool, radius: Int, edge: Bool) -> CGImage? {
        FaceGameArt.sprite("snake-bead-\(shade)-\(band)-\(radius)-\(edge)", width: radius * 2 + 8, height: radius * 2 + 8) { ctx, _ in
            let t = Double(shade) / 7
            var tone = FaceGamePaint.mix(FaceGamePalette.mint, FaceGamePalette.teal, t)
            if band { tone = tone * 0.88 }
            let r = Double(radius), c = CGPoint(x: r + 4, y: r + 4)
            if edge {
                ctx.setFillColor(FaceGamePaint.cg(FaceGameArt.edge(of: tone)))
                ctx.fillEllipse(in: CGRect(x: c.x - r - 3.5, y: c.y - r - 3.5, width: r * 2 + 7, height: r * 2 + 7))
            } else {
                FaceGameArt.litBall(ctx, center: c, radius: r, tone: tone, gloss: 0.4)
            }
        }
    }

    private func drawBody(_ ctx: CGContext) {
        guard !body.isEmpty else { return }
        // Points half way between segments make the body smooth instead of a string of beads.
        var points: [SIMD2<Double>] = [head]
        for p in body {
            points.append((points[points.count - 1] + p) / 2)
            points.append(p)
        }
        let count = points.count
        for edge in [true, false] {
            for i in stride(from: count - 1, through: 1, by: -1) {
                let t = Double(i) / Double(max(1, count - 1))
                let r = Int((Self.bodyRadius * (1 - 0.6 * FaceGamePaint.smoothstep(0.55, 1, t)) + 2).rounded())
                guard let sprite = Self.bead(min(7, Int(t * 8)), band: (i / 4) % 2 == 1, radius: r, edge: edge) else { continue }
                visit(points[i], radius: Double(r) + 4) { FaceGameArt.blit(ctx, sprite, at: CGPoint(x: $0.x - Double(r) - 4, y: $0.y - Double(r) - 4)) }
            }
        }
    }

    private func drawHead(_ ctx: CGContext, time: Double) {
        let scale = 1 + 0.16 * FaceGameEase.backOut(gulp, overshoot: 1.5)
        let r = Self.headRadius * scale
        visit(head, radius: r + 14) { c in
            // Tongue first, so the head sits over its root.
            let flick = isOver ? 0.4 : 0.55 + 0.45 * sin(time * 16)
            let tip = CGPoint(x: c.x + cos(heading) * (r + 26 * flick), y: c.y + sin(heading) * (r + 26 * flick))
            let root = CGPoint(x: c.x + cos(heading) * r * 0.8, y: c.y + sin(heading) * r * 0.8)
            ctx.setLineCap(.round)
            for (width, tone) in [(9.0, FaceGamePaint.Tone(0.45, 0.04, 0.12)), (5.5, FaceGamePalette.coral)] {
                ctx.setStrokeColor(FaceGamePaint.cg(tone))
                ctx.setLineWidth(CGFloat(width))
                ctx.move(to: root); ctx.addLine(to: tip)
                for side in [-1.0, 1.0] {
                    ctx.move(to: tip)
                    ctx.addLine(to: CGPoint(x: tip.x + cos(heading + side * 0.6) * 13, y: tip.y + sin(heading + side * 0.6) * 13))
                }
                ctx.strokePath()
            }
            FaceGameArt.contactShadow(ctx, center: CGPoint(x: c.x + 6, y: c.y - 8), width: r * 2.6, height: r * 2.4, alpha: 0.35)
            FaceGameArt.litBall(ctx, center: c, radius: r + 9, tone: isOver ? FaceGamePalette.coral : FaceGamePalette.mint, edgeWidth: 4, gloss: 0)
            let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            FaceGamePaint.drawFace(ctx, crop: crop, in: rect, corner: r, fallback: isOver ? "😵" : "🙂")
            ctx.setStrokeColor(FaceGamePaint.cg(FaceGameArt.edge(of: FaceGamePalette.mint)))
            ctx.setLineWidth(3)
            ctx.strokeEllipse(in: rect)
        }
    }

    /// A pulsing ring where the snake is headed: your nose, as the game sees it.
    private func drawAim(_ ctx: CGContext, time: Double) {
        let c = CGPoint(x: aim.x, y: aim.y)
        let r = 20 + 3 * sin(time * 6)
        ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.ink, 0.6))
        ctx.setLineWidth(10)
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.setStrokeColor(FaceGamePaint.cg(FaceGamePalette.cream))
        ctx.setLineWidth(4.5)
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.setFillColor(FaceGamePaint.cg(FaceGamePalette.mint))
        ctx.fillEllipse(in: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12))
    }
}
