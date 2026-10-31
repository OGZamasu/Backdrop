import CoreGraphics
import CoreImage
import Foundation
import simd

/// What the painter of a scene is told about the moment it is drawing.
struct VistaFrame {
    var time: Double
    var size: CGSize
    /// Where the person stands, -1 at the left edge to 1 at the right: shifts the layers a little as they move.
    var shift: CGPoint
    var person: VistaPerson?
}

/// One creature at the moment it is drawn: everything its painter needs, worked out once.
struct VistaRig {
    let creature: VistaCreature
    let species: VistaSpecies
    let time: Double
    /// Walking (or flapping along) right now, rather than standing.
    let moving: Bool
    /// The walk cycle, in radians; 0 when it stands.
    let stride: Double
    /// 0...1: how far into its show it is, rising at the start and falling away at the end.
    let act: Double
    /// Seconds into its show, or 0.
    let actTime: Double
    /// 0 eyes open, 1 shut.
    let blink: Double
    /// -1...1, slowly.
    let breath: Double
    /// Where it is looking, in its own frame (x forward, y up), as a direction; zero for straight ahead.
    let gaze: SIMD2<Double>
    /// 0 when it is minding its own business, 1 when it is looking right at you.
    let attention: Double
    /// 0 close up, 1 far away.
    let far: Double
    /// Pixels to a unit, as drawn.
    let scale: Double
    /// Far enough off to be drawn with the parts painted already hazed (see `VistaFigure`).
    var hazed = false
    /// Where its origin is drawn, in frame pixels (its feet, or its middle), with the bob of its gait.
    var anchor = CGPoint.zero
    /// The bend of the body this moment: stretch up, squash across, tip (radians).
    var stretch = 1.0
    var squash = 1.0
    var tilt = 0.0

    /// A point given in the creature's own units, in frame pixels, as it is drawn (ignoring its tip).
    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: Double(anchor.x) + x * scale * creature.turn * squash, y: Double(anchor.y) + y * scale * stretch)
    }

    var phase: VistaCreature.Phase { creature.phase }
    var quirk: Double { creature.quirk }

    /// A smooth swell over the length of its show: 0 before, up to 1 over `rise` seconds, back to 0 over the last `fall`.
    func hold(rise: Double, fall: Double) -> Double {
        guard phase == .acting else { return 0 }
        let t = actTime, end = species.actSeconds
        func e(_ k: Double) -> Double { let x = min(1, max(0, k)); return x * x * (3 - 2 * x) }
        return t < end - fall ? e(t / rise) : 1 - e((t - (end - fall)) / fall)
    }

    /// 1 between two moments of its show, easing in and out over `ease` seconds; 0 otherwise.
    func during(_ from: Double, _ to: Double, ease: Double = 0.15) -> Double {
        guard phase == .acting else { return 0 }
        let t = actTime
        return max(0, min(1, (t - from) / ease)) * max(0, min(1, (to - t) / ease))
    }
    /// Its own clock, offset so two of a kind do not move in step.
    var clock: Double { time + creature.quirk * 17 }
}

/// The colours of the little things the world throws about, for one scene.
struct VistaFXColors {
    var dust: UInt32 = 0xE8D8C0
    var snow: UInt32 = 0xF4FAFF
    var sparkle: UInt32 = 0xFFF0A0
    var ember: UInt32 = 0xFF9A3A
    var smoke: UInt32 = 0x9A90A0
    var water: UInt32 = 0xDDF2FF
    var notes: [UInt32] = [0xFFD166, 0x8FE3FF, 0xFF8FB8]
    var heart: UInt32 = 0xFF6F91
}

/// A place: who lives there and how it is painted. Painting is heavy, so it is done in steps on the first few frames
/// (on the video queue), never when the lens is made.
protocol VistaStage: AnyObject {
    var cast: VistaCast { get }
    /// The line shown in the interface: what to do here.
    var hint: String { get }
    /// The colour round the edge of the speech bubbles.
    var accent: UInt32 { get }
    var fx: VistaFXColors { get }
    /// The air between you and the far lane, and how much of it the far creatures take on.
    var haze: UInt32 { get }
    var hazeAmount: Double { get }
    /// How many pieces the painting is done in, and how many of the first ones make up the backdrop: the scene only fades in
    /// once those are done. The rest are the creatures, which appear as they are ready.
    var bakeSteps: Int { get }
    var backdropSteps: Int { get }
    func bake(step: Int)
    /// Whether the art for a kind of creature has been painted yet.
    func isReady(species: Int) -> Bool
    /// Everything behind the creatures: sky, hills, water, and the slow things that move in them.
    func paintBackdrop(_ ctx: CGContext, _ frame: VistaFrame)
    /// Things in front of everybody, the person included: plants at the edges, motes in the light.
    func paintForeground(_ ctx: CGContext, _ frame: VistaFrame)
    /// Draws a creature in its own units: origin at its feet (or its middle, if it flies), facing right, 1 unit tall.
    func paintCreature(_ ctx: CGContext, _ rig: VistaRig)
    /// Draws what a creature does to the world around it, in frame pixels, just before the creature: a beam, a breath of fire.
    func paintAura(_ ctx: CGContext, _ rig: VistaRig, _ world: VistaWorld, _ frame: VistaFrame)
}

extension VistaStage {
    func paintAura(_ ctx: CGContext, _ rig: VistaRig, _ world: VistaWorld, _ frame: VistaFrame) {}
}

/// A living backdrop in the Vista family. The person stands in front of a painted world and the creatures in it notice them, come
/// over, do something and run off when they are scared. Painted in layers: the world, the creatures far away, the person, the
/// creatures close up, the plants in front of everything, and the speech bubbles.
final class VistaLens: Lens {
    let needs: LensNeeds
    var wantsMatteGrid: Bool { true }
    var status: LensStatus? { published.value }

    private(set) var world: VistaWorld
    private let stage: VistaStage
    private var previousGrid: MatteGrid?
    private var shift = CGPoint.zero
    private let published = StatusBox()
    /// The next piece of painting to do.
    private(set) var baked = 0
    /// How long the scene has been on screen: it fades in from the room over the first moments.
    private var shown = 0.0

    init(stage: VistaStage, hands: Bool = true, seed: UInt64 = .random(in: .min ... .max)) {
        self.stage = stage
        needs = hands ? [.matte, .hands] : [.matte]
        world = VistaWorld(cast: stage.cast, seed: seed)
        published.value = LensStatus(stage.hint)
    }

    /// For tests: leaves the creatures out, or their distance haze, to see what they cost.
    var drawsCreatures = true
    var tintsDistance = true

    /// Whether all the painting is done.
    var isPainted: Bool { baked >= stage.bakeSteps }

    /// For tests and previews: sends the first creature of a kind over to the person.
    func attract(_ name: String) {
        if let id = world.creatures.first(where: { world.cast.species[$0.species].name == name })?.id { world.attract(id) }
    }

    /// For tests: puts creature `id` at rest at a place.
    func stage(_ id: Int, x: Double, depth: Double? = nil) { world.stage(id, x: x, depth: depth) }

    /// For tests and previews: does all the painting now.
    func paintEverything() {
        while baked < stage.bakeSteps { stage.bake(step: baked); baked += 1 }
    }

    func restart() {
        world = VistaWorld(cast: stage.cast, seed: .random(in: .min ... .max))
        previousGrid = nil
    }

    /// Paints the next piece or two of the scene, stopping once about 8 ms have gone, so that no single frame stalls the video.
    private func bakeSome() {
        guard baked < stage.bakeSteps else { return }
        let started = CFAbsoluteTimeGetCurrent()
        let budget = 0.008
        repeat {
            stage.bake(step: baked)
            baked += 1
        } while baked < stage.bakeSteps && CFAbsoluteTimeGetCurrent() - started < budget
    }

    func render(_ input: LensInput) -> CIImage {
        bakeSome()
        // Until the backdrop is painted, the room stays as it is; then the scene fades in over it.
        guard baked >= stage.backdropSteps else { return input.composed }
        let grid = input.matteGrid
        let motion = grid.flatMap { current in previousGrid.map { current.motion(since: $0) } }
        world.step(input.dt, context: VistaContext(size: input.rect.size, matte: grid, motion: motion, hands: input.hands))
        previousGrid = grid?.snapshot()
        shown += max(0, min(input.dt, 0.1))

        // The world slides a little the other way as the person moves across the picture.
        let wanted = world.person.map { (Double($0.box.midX) / Double(input.rect.width) - 0.5) * 2 } ?? 0
        let k = 1 - exp(-input.dt * 2.5)
        shift.x += (CGFloat(wanted) - shift.x) * CGFloat(k)
        let frame = VistaFrame(time: world.time, size: input.rect.size, shift: shift, person: world.person)

        published.value = LensStatus(world.person == nil ? "Step into view and they will come and find you" : stage.hint)

        let rigs = world.creatures.compactMap { c -> VistaRig? in
            guard drawsCreatures, c.phase != .away, stage.isReady(species: c.species) else { return nil }
            return rig(for: c)
        }
        guard let behind = input.services.overlay({ ctx in
            stage.paintBackdrop(ctx, frame)
            drawShadows(rigs, in: ctx)
            drawCreatures(rigs, front: false, in: ctx, frame: frame)
            drawEffects(world.effectsBehind, in: ctx, frame: frame, front: false)
        }) else { return input.composed }
        let withPerson = input.matte == nil ? behind : input.placingPerson(over: behind)

        let front = input.services.overlay { ctx in
            drawCreatures(rigs, front: true, in: ctx, frame: frame)
            drawEffects(world.effects, in: ctx, frame: frame, front: true)
            stage.paintForeground(ctx, frame)
            drawBubbles(in: ctx)
        }
        var out = front.map { $0.composited(over: withPerson) } ?? withPerson

        if world.shake > 0.3 {
            let t = world.time
            let move = CGAffineTransform(translationX: CGFloat(sin(t * 47) * world.shake), y: CGFloat(cos(t * 39) * world.shake * 0.7))
            out = out.clampedToExtent().transformed(by: move)
        }
        out = out.cropped(to: input.rect)
        if shown < 0.5 {
            // A soft dissolve from the room into the scene.
            let x = min(1, shown / 0.5)
            out = out.fading(x * x * (3 - 2 * x)).composited(over: input.composed).cropped(to: input.rect)
        }
        return out
    }

    // MARK: Working out a creature's moment

    private static func ease(_ k: Double) -> Double { let x = min(1, max(0, k)); return x * x * (3 - 2 * x) }

    private func rig(for c: VistaCreature) -> VistaRig {
        let sp = world.cast.species[c.species]
        let t = world.time
        let moving = abs(c.vel.x) > 8 || (sp.isAirborne && simd_length(c.vel) > 20)
        // The show rises in and falls away.
        var act = 0.0, actTime = 0.0
        if c.phase == .acting {
            actTime = c.phaseTime
            let end = sp.act == .perch ? 1e9 : sp.actSeconds
            act = actTime < end - 0.45 ? Self.ease(actTime / 0.3) : 1 - Self.ease((actTime - (end - 0.45)) / 0.45)
        }
        // Blinks: every few seconds, now and then two in a row.
        let period = 3.1 + c.quirk * 2.6
        let p = (t + c.quirk * 11).truncatingRemainder(dividingBy: period)
        var blink = p < 0.16 ? sin(p / 0.16 * .pi) : 0
        if c.quirk > 0.6, p > 0.3, p < 0.46 { blink = sin((p - 0.3) / 0.16 * .pi) }
        let breath = sin(t * (2.0 + c.quirk * 0.6) + c.quirk * 9)

        // Where it looks: at you when it cares, about the place when it does not.
        var attention = 0.0
        switch c.phase {
        case .noticing: attention = min(1, c.phaseTime / 0.2)
        case .approaching, .acting, .backingOff: attention = 1
        case .retreating: attention = max(0, 1 - c.phaseTime / 0.6)
        default: attention = 0
        }
        var gaze = SIMD2(cos(t * 0.37 + c.quirk * 13) * 0.5 + 0.4, sin(t * 0.29 + c.quirk * 7) * 0.4)
        if let person = world.person, attention > 0 {
            let h = world.height(c)
            let eye = sp.isGroundBound ? SIMD2(c.pos.x, c.pos.y + c.lift + h * 0.8) : c.pos
            var toward = SIMD2(Double(person.head.x), Double(person.head.y)) - eye
            toward.x *= c.dir
            let length = simd_length(toward)
            if length > 1 { gaze = gaze * (1 - attention) + toward / length * attention }
        }
        let far = 1 - min(1, max(0, (c.depth - 0.4) / 0.26))
        var r = VistaRig(creature: c, species: sp, time: t, moving: moving, stride: moving || c.sliding ? c.stride : 0, act: act, actTime: actTime,
                         blink: blink, breath: breath, gaze: gaze, attention: attention, far: far, scale: world.spriteHeight(c))
        pose(&r)
        return r
    }

    /// The bend of the body: a bob as it walks, a start when it notices you, a squash as it lands.
    private func pose(_ r: inout VistaRig) {
        let c = r.creature, sp = r.species
        let h = r.scale
        var stretch = 1 + 0.012 * r.breath, squash = 1 - 0.008 * r.breath, tilt = 0.0, lift = 0.0
        switch sp.body {
        case .walker:
            if r.moving, !c.sliding {
                switch sp.gait {
                case .walk: lift = abs(sin(c.stride)) * h * 0.025
                case .waddle: tilt = sin(c.stride) * 0.09; lift = abs(sin(c.stride)) * h * 0.02
                case .hop:
                    let air = max(0, sin(c.stride))
                    lift = air * h * 0.45; stretch += 0.1 * air; squash -= 0.07 * air; tilt = (air - 0.5) * 0.25
                case .scuttle: lift = abs(sin(c.stride)) * h * 0.03
                case .roll: tilt = sin(c.stride * 0.5) * 0.03
                }
            }
            if c.lift > 0.5 {
                // In the air: stretched going up, squashed coming down.
                let v = max(-1, min(1, c.vel.y / 500))
                stretch += 0.08 * v
                squash -= 0.05 * v
            }
        case .flier:
            lift = sin(r.time * 2.2 + c.quirk * 8) * h * 0.04
            tilt = max(-0.35, min(0.35, c.vel.y * 0.0012)) * c.dir
        case .floater:
            lift = sin(r.time * 1.1 + c.quirk * 8) * h * 0.05
            tilt = sin(r.time * 0.6 + c.quirk * 5) * 0.06
        case .soarer:
            lift = sin(r.time * 1.6 + c.quirk * 8) * h * 0.03
            tilt = max(-0.3, min(0.3, c.vel.y * 0.001)) * c.dir
        case .emerger, .prop:
            break
        }
        if c.phase == .noticing {
            let k = max(0, 1 - c.phaseTime / 0.3)
            stretch += 0.08 * k
            squash -= 0.05 * k
        }
        if c.phase == .fleeing { stretch -= 0.03; squash += 0.04 }
        switch sp.body {
        case .walker, .prop: r.anchor = CGPoint(x: c.pos.x, y: c.pos.y + c.lift + lift)
        case .emerger: r.anchor = CGPoint(x: c.pos.x, y: c.pos.y)
        case .flier, .floater, .soarer: r.anchor = CGPoint(x: c.pos.x, y: c.pos.y + lift)
        }
        r.stretch = stretch
        r.squash = squash
        r.tilt = tilt
    }

    // MARK: Drawing

    /// Soft shadows on the ground, painted with the backdrop so that the person (who is in front of the ground) covers them.
    private func drawShadows(_ rigs: [VistaRig], in ctx: CGContext) {
        guard let shadow = VistaSprites.shadow else { return }
        for r in rigs {
            let c = r.creature, sp = r.species
            guard sp.body != .emerger, sp.body != .floater else { continue }
            let w = world.width(c), h = world.height(c)
            let ground = world.layout.ground(c.depth)
            let altitude = sp.isGroundBound ? max(0, c.lift) : max(0, c.pos.y - h / 2 - ground)
            guard altitude < 260 else { continue }
            let fade = 1 / (1 + altitude / (h * 0.5 + 30))
            let width = w * (sp.isGroundBound ? 1.05 : 0.7) * (0.75 + 0.25 * fade)
            let height = max(8, w * 0.18) * (sp.isGroundBound ? 1 : 0.8)
            let alpha = 0.42 * fade * (0.6 + 0.4 * world.layout.scale(c.depth))
            ctx.setAlpha(CGFloat(alpha))
            ctx.draw(shadow, in: CGRect(x: c.pos.x - width / 2 - w * 0.06, y: ground - height * 0.45, width: width, height: height))
        }
        ctx.setAlpha(1)
    }

    private func drawCreatures(_ rigs: [VistaRig], front: Bool, in ctx: CGContext, frame: VistaFrame) {
        var order = rigs.filter { ($0.creature.depth >= world.layout.frontDepth) == front }
        order.sort { $0.creature.depth != $1.creature.depth ? $0.creature.depth < $1.creature.depth : $0.creature.pos.y > $1.creature.pos.y }
        ctx.interpolationQuality = .low
        for r in order {
            stage.paintAura(ctx, r, world, frame)
            draw(r, in: ctx)
        }
        ctx.interpolationQuality = .high
    }

    private func draw(_ r: VistaRig, in ctx: CGContext) {
        let c = r.creature, sp = r.species
        let h = r.scale
        let anchor = r.anchor, tilt = r.tilt, stretch = r.stretch, squash = r.squash
        ctx.saveGState()
        ctx.translateBy(x: anchor.x, y: anchor.y)
        if tilt != 0 {
            let pivot = sp.isGroundBound ? CGPoint(x: -c.turn * world.width(c) * 0.25, y: 0) : .zero
            ctx.translateBy(x: pivot.x, y: pivot.y)
            ctx.rotate(by: CGFloat(tilt * c.turn))
            ctx.translateBy(x: -pivot.x, y: -pivot.y)
        }
        // A turn squeezes it through edge-on rather than flipping it at once.
        let facing = abs(c.turn) < 0.12 ? (c.turn < 0 ? -0.12 : 0.12) : c.turn
        ctx.scaleBy(x: CGFloat(facing * squash * h), y: CGFloat(stretch * h))
        // Far off, a creature takes on the colour of the air. In its lane that is baked into its parts; on the way between lanes
        // it is drawn as one group and washed over, which costs more but only for a moment.
        var r = r
        r.hazed = tintsDistance && r.far >= 0.97
        let haze = tintsDistance && !r.hazed ? r.far * stage.hazeAmount : 0
        if haze > 0.02 {
            let box = CGRect(x: -sp.aspect * 0.8 - 0.3, y: sp.isGroundBound ? -0.2 : -0.85, width: sp.aspect * 1.6 + 0.6, height: 1.9)
            ctx.beginTransparencyLayer(in: box, auxiliaryInfo: nil)
            stage.paintCreature(ctx, r)
            ctx.saveGState()
            ctx.setBlendMode(.sourceAtop)
            ctx.setFillColor(VistaInk.color(stage.haze, haze))
            ctx.fill(box)
            ctx.restoreGState()
            ctx.endTransparencyLayer()
        } else {
            stage.paintCreature(ctx, r)
        }
        ctx.restoreGState()
    }

    // MARK: Effects

    private func drawEffects(_ system: ParticleSystem, in ctx: CGContext, frame: VistaFrame, front: Bool) {
        guard !system.particles.isEmpty else { return }
        let fx = stage.fx
        let zone = front ? frame.person?.faceZone : nil
        let (dr, dg, db) = VistaInk.components(fx.dust)
        let (wr, wg, wb) = VistaInk.components(fx.water)
        let snow = Sprites.dot(red: VistaInk.components(fx.snow).0, green: VistaInk.components(fx.snow).1, blue: VistaInk.components(fx.snow).2)
        let ember = VistaSprites.glow(fx.ember)
        let twinkle = VistaSprites.twinkle(fx.sparkle)
        let coin = VistaSprites.coin
        let heart = VistaSprites.heart(fx.heart)
        let smoke = Sprites.dot(red: VistaInk.components(fx.smoke).0, green: VistaInk.components(fx.smoke).1, blue: VistaInk.components(fx.smoke).2)
        for p in system.particles {
            let k = p.progress
            var alpha = 1.0
            // Nothing in front of you lingers over your face.
            if let zone, zone.contains(CGPoint(x: p.position.x, y: p.position.y)) { alpha = 0.2 }
            let x = p.position.x, y = p.position.y
            switch VistaFX(rawValue: p.kind) ?? .dust {
            case .dust:
                let r = p.size * (0.7 + 1.0 * k), fade = pow(1 - k, 1.4) * alpha
                ctx.setFillColor(CGColor(red: dr, green: dg, blue: db, alpha: 0.18 * fade))
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.85, width: r * 2, height: r * 1.7))
                ctx.setFillColor(CGColor(red: dr, green: dg, blue: db, alpha: 0.26 * fade))
                ctx.fillEllipse(in: CGRect(x: x - r * 0.55, y: y - r * 0.5, width: r * 1.1, height: r))
            case .snow:
                if let snow { ctx.stampDot(snow, at: CGPoint(x: x, y: y), radius: p.size * (0.5 + 0.6 * k), alpha: 0.75 * pow(1 - k, 1.2) * alpha) }
            case .sparkle:
                if let twinkle {
                    let s = p.size * (0.6 + 0.6 * sin(min(1, k * 1.4) * .pi))
                    ctx.saveGState()
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: CGFloat(p.age * 2 + p.hue * 6))
                    ctx.setAlpha(CGFloat(alpha * (1 - k * k)))
                    ctx.draw(twinkle, in: CGRect(x: -s, y: -s, width: s * 2, height: s * 2))
                    ctx.restoreGState()
                }
            case .ember:
                if let ember { ctx.stampDot(ember, at: CGPoint(x: x, y: y), radius: p.size * (1.4 - 0.8 * k), alpha: alpha * (1 - k)) }
            case .smoke:
                if let puff = smoke { ctx.stampDot(puff, at: CGPoint(x: x, y: y), radius: p.size * (0.5 + 1.1 * k), alpha: 0.42 * (1 - k) * alpha) }
            case .splash:
                ctx.setFillColor(CGColor(red: wr, green: wg, blue: wb, alpha: 0.9 * (1 - k * k * k) * alpha))
                ctx.fillEllipse(in: CGRect(x: x - p.size * 0.5, y: y - p.size * 0.5, width: p.size, height: p.size * 1.25))
                ctx.setFillColor(CGColor(gray: 1, alpha: 0.85 * (1 - k) * alpha))
                ctx.fillEllipse(in: CGRect(x: x - p.size * 0.28, y: y + p.size * 0.05, width: p.size * 0.3, height: p.size * 0.3))
            case .bubble:
                let r = p.size * 0.5 * (0.7 + 0.3 * k)
                ctx.setStrokeColor(CGColor(red: wr, green: wg, blue: wb, alpha: 0.65 * (1 - k) * alpha))
                ctx.setLineWidth(1.6)
                ctx.strokeEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            case .coin:
                if let coin {
                    let spin = cos(p.age * 9 + p.hue * 6)
                    let s = p.size
                    ctx.saveGState()
                    ctx.translateBy(x: x, y: y)
                    ctx.scaleBy(x: CGFloat(max(0.12, abs(spin))), y: 1)
                    ctx.setAlpha(CGFloat(alpha * min(1, (1 - k) * 4)))
                    ctx.draw(coin, in: CGRect(x: -s, y: -s, width: s * 2, height: s * 2))
                    ctx.restoreGState()
                }
            case .note:
                let tone = fx.notes.isEmpty ? 0xFFFFFF : fx.notes[Int(p.hue * Double(fx.notes.count)) % fx.notes.count]
                if let note = VistaSprites.note(tone) {
                    let s = p.size * (0.7 + 0.3 * min(1, k * 4))
                    ctx.saveGState()
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: CGFloat(sin(p.age * 3 + p.hue * 9) * 0.3))
                    ctx.setAlpha(CGFloat(alpha * min(1, (1 - k) * 3)))
                    ctx.draw(note, in: CGRect(x: -s * 0.375, y: -s * 0.5, width: s * 0.75, height: s))
                    ctx.restoreGState()
                }
            case .heart:
                if let heart {
                    let s = p.size * (0.6 + 0.4 * min(1, k * 5))
                    ctx.setAlpha(CGFloat(alpha * min(1, (1 - k) * 3)))
                    ctx.draw(heart, in: CGRect(x: x - s / 2, y: y - s * 0.46, width: s, height: s * 0.92))
                    ctx.setAlpha(1)
                }
            }
        }
        ctx.setAlpha(1)
    }

    // MARK: Speech

    /// Speech bubbles pop in over the creatures' heads, keep off the person's face and inside a safe margin.
    private func drawBubbles(in ctx: CGContext) {
        let size = world.size
        let marginX = size.width * 0.05, marginY = size.height * 0.05
        var placed: [CGRect] = []
        for c in world.creatures where c.phase != .away && stage.isReady(species: c.species) {
            guard let bubble = c.bubble, let image = VistaBubbleArt.image(bubble.text, accent: stage.accent) else { continue }
            let sp = world.cast.species[c.species]
            let reach = c.phase == .acting ? sp.actReach : 1
            // Pops in with a little overshoot, and shrinks away at the end.
            let k = min(1, bubble.age / 0.28)
            let back = 1.70158
            let pop = 1 + (back + 1) * pow(k - 1, 3) + back * pow(k - 1, 2)
            let out = min(1, max(0, (bubble.life - bubble.age) / 0.22))
            let scale = (0.62 + 0.3 * world.layout.scale(c.depth)) * max(0.05, pop) * (0.7 + 0.3 * out)
            let w = Double(image.width) * scale, h = Double(image.height) * scale
            let body = world.bounds(of: c)
            let top = Double(body.minY) + Double(body.height) * reach
            var x = c.pos.x + c.dir * world.width(c) * 0.12
            var y = top + 2
            x = min(max(x, marginX + w / 2), size.width - marginX - w / 2)
            if y > size.height - marginY - h {
                // No room above its head: the bubble goes beside it.
                y = size.height - marginY - h
                if CGRect(x: x - w / 2, y: y, width: w, height: h).intersects(body) {
                    let right = Double(body.maxX) + w / 2 + 8, left = Double(body.minX) - w / 2 - 8
                    x = right + w / 2 < size.width - marginX ? right : left
                }
            }
            if let person = world.person {
                let zone = person.faceZone.insetBy(dx: -8, dy: -8)
                var rect = CGRect(x: x - w / 2, y: y, width: w, height: h)
                if rect.intersects(zone) {
                    // Slide out sideways, to whichever side is nearer.
                    x = abs(x - zone.minX) < abs(x - zone.maxX) ? zone.minX - w / 2 : zone.maxX + w / 2
                    x = min(max(x, marginX + w / 2), size.width - marginX - w / 2)
                    rect = CGRect(x: x - w / 2, y: y, width: w, height: h)
                    if rect.intersects(zone) { y = zone.maxY + 4 }
                }
            }
            // Two talking at once: the second bubble goes above the first.
            while let hit = placed.first(where: { $0.intersects(CGRect(x: x - w / 2, y: y, width: w, height: h)) }), y < size.height - marginY - h {
                y = min(size.height - marginY - h, Double(hit.maxY) + 4)
            }
            placed.append(CGRect(x: x - w / 2, y: y, width: w, height: h))
            let wobble = bubble.text.hasPrefix("!") ? sin(bubble.age * 30) * 0.05 * max(0, 1 - bubble.age) : sin(bubble.age * 5) * 0.015
            ctx.saveGState()
            ctx.translateBy(x: x, y: y)
            ctx.rotate(by: CGFloat(wobble))
            ctx.setAlpha(CGFloat(out))
            ctx.draw(image, in: CGRect(x: -w / 2, y: 0, width: w, height: h))
            ctx.restoreGState()
        }
        ctx.setAlpha(1)
    }
}
