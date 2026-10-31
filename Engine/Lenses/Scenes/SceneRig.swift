import CoreGraphics
import Foundation
import simd

// The motion side of the hand-drawn creatures: what a creature is doing this frame, worked out from the behaviour model, and the
// small tools that turn it into a pose (a walk cycle, a two-bone leg, springs for things that lag and settle).

/// A creature drawn by hand: given what it is doing, it paints itself as vector shapes. The context is in the creature's units
/// (1 is its full height), facing right, origin at its feet (walkers) or its middle (everything else).
protocol ScenePuppet: AnyObject {
    func draw(_ ctx: CGContext, _ a: SceneActor, _ ink: SceneInk)
    /// Drawn facing you (a ghost, a pumpkin, a jellyfish): it does not squeeze thin to turn round.
    var facesViewer: Bool { get }
}

extension ScenePuppet {
    var facesViewer: Bool { false }
}

/// Everything a puppet needs to strike its pose for one frame.
struct SceneActor {
    var id = 0
    var time = 0.0
    var phase = SceneCreature.Phase.wandering
    var phaseTime = 0.0
    /// The walk cycle, in radians: one full turn is one cycle of all four feet.
    var stride = 0.0
    var pose = ScenePose()
    var quirk = 0.0
    var act = SceneSpecies.Act.hop
    var actSeconds = 2.4
    /// Off the ground, in units (a jump, a climb).
    var lift = 0.0
    /// Velocity in units a second, in the creature's own frame: +x is the way it faces.
    var velocity = SIMD2<Double>.zero
    /// 0 standing, 1 walking at its usual pace: eased, so feet settle rather than snap.
    var walk = 0.0
    /// 0 walking, 1 running flat out: eased.
    var run = 0.0
    /// Walking backwards: facing one way, going the other.
    var backwards = false
    /// The angle from its head up to the person's face, sprung (radians; 0 level, positive up).
    var look = 0.0
    /// 0 calm, 1 alert: head up, ears pricked, tail still. Eased.
    var alert = 0.0
    /// A lagging swing for the tail, -1...1.
    var tail = 0.0
    /// Has landed: on a hand, on a shoulder, on a head.
    var landed = false
    /// For a school: which fish of it this is.
    var member = 0

    /// Whether the act is under way and how far into it, 0...1, with an ease in and out of `rise` seconds.
    func acting(rise: Double = 0.3, fall: Double = 0.5) -> Double {
        guard phase == .acting else { return 0 }
        let t = phaseTime
        if t < actSeconds - fall { return SceneRig.ease(t / rise) }
        return 1 - SceneRig.ease((t - (actSeconds - fall)) / fall)
    }

    /// The eyes shut now and then, for about a tenth of a second.
    var blink: Double {
        let period = 3.1 + quirk * 2.3
        let t = (time + quirk * 11).truncatingRemainder(dividingBy: period)
        let k = t / 0.16
        return k < 1 ? sin(k * .pi) : 0
    }

    /// Slow breathing, -1...1.
    var breath: Double { sin(time * (1.7 + quirk * 0.5) + quirk * 9) }

    /// An ear twitches now and then: 0 at rest, 1 at the top of the twitch.
    func twitch(_ which: Double = 0) -> Double {
        let period = 4.3 + quirk * 3 + which * 1.7
        let t = (time + quirk * 23 + which * 2.1).truncatingRemainder(dividingBy: period)
        return t < 0.35 ? sin(t / 0.35 * .pi) : 0
    }

    /// Slow wandering noise, -1...1, for idle glances and sways.
    func drift(_ rate: Double, _ seed: Double) -> Double { ScenePaint.noise(time * rate + quirk * 37, seed) * 2 - 1 }

    var isScared: Bool { phase == .fleeing || phase == .backingOff }
}

/// What a creature remembers from one frame to the next, so that its motion eases, lags and settles.
struct SceneRigMemory {
    var time = -1.0
    var x = 0.0
    var y = 0.0
    var speedX = 0.0
    var speedY = 0.0
    var walk = 0.0
    var run = 0.0
    var look = 0.0
    var lookVelocity = 0.0
    var tail = 0.0
    var tailVelocity = 0.0
    var alert = 0.0
}

enum SceneRig {
    static func ease(_ k: Double) -> Double { let x = min(1, max(0, k)); return x * x * (3 - 2 * x) }

    /// A damped spring toward `target`: overshoots a little and settles, for heads, tails and anything that should lag.
    static func spring(_ x: inout Double, _ v: inout Double, to target: Double, frequency: Double, damping: Double, dt: Double) {
        guard dt > 0 else { return }
        let steps = max(1, Int(ceil(dt / 0.02)))
        let h = dt / Double(steps)
        let w = 2 * .pi * frequency
        for _ in 0..<steps {
            let a = -w * w * (x - target) - 2 * damping * w * v
            v += a * h
            x += v * h
        }
    }

    /// Where a foot is in its step, given its own phase (in cycles): forward as -0.5...0.5 of the stride, and up as 0...1 of the
    /// lift. It is planted for `duty` of the cycle, sliding back under the body, then swings forward through the air.
    static func foot(_ phase: Double, duty: Double) -> (forward: Double, up: Double) {
        let q = phase - floor(phase)
        if q < duty { return (0.5 - q / duty, 0) }
        let k = (q - duty) / (1 - duty)
        return (-0.5 + k * k * (3 - 2 * k), sin(k * .pi) * (1 - 0.3 * k))
    }

    /// A two-bone limb from `root` reaching for `target`: where the middle joint goes. `bend` +1 swings the joint
    /// counter-clockwise from the line to the target (ahead, for a leg pointing down), -1 the other way. A target out of reach
    /// gets a straight limb pointing at it.
    static func knee(_ root: CGPoint, _ target: CGPoint, upper: Double, lower: Double, bend: Double) -> CGPoint {
        let dx = Double(target.x - root.x), dy = Double(target.y - root.y)
        let d = min(upper + lower - 1e-4, max(abs(upper - lower) + 1e-4, hypot(dx, dy)))
        let a = atan2(dy, dx)
        let cosA = max(-1, min(1, (upper * upper + d * d - lower * lower) / (2 * upper * d)))
        let angle = a + acos(cosA) * (bend >= 0 ? 1 : -1)
        return CGPoint(x: Double(root.x) + cos(angle) * upper, y: Double(root.y) + sin(angle) * upper)
    }

    /// The far end of a two-bone limb, once the middle joint is known: the target, pulled in if it is out of reach.
    static func reach(_ knee: CGPoint, _ target: CGPoint, lower: Double) -> CGPoint {
        let dx = Double(target.x - knee.x), dy = Double(target.y - knee.y)
        let d = max(1e-9, hypot(dx, dy))
        return CGPoint(x: Double(knee.x) + dx / d * lower, y: Double(knee.y) + dy / d * lower)
    }
}

/// The renderer's per-creature memory, kept between frames.
final class SceneRigMemoryBox {
    var slots: [Int: SceneRigMemory] = [:]
    var held: [Int: SceneHeldFrame] = [:]
    /// Counts drawn frames, to decide whose pose is due to be drawn again.
    var frame = 0
    var lastTime = -1.0
}

/// A creature's last drawing, kept in its own small picture and copied onto the scene at whole pixels until its pose is due again.
/// Animals are drawn on twos (fifteen poses a second) and far ones on threes, like hand-drawn animation; they still move across the
/// picture every frame.
final class SceneHeldFrame {
    private var context: CGContext?
    private(set) var image: CGImage?
    /// Where the anchor sits inside the picture, in pixels from its lower left.
    private(set) var origin = CGPoint.zero
    private(set) var drawnAt = -100
    private(set) var unit = 0.0
    private(set) var facing = 0.0
    private(set) var phase = SceneCreature.Phase.away
    private(set) var key = 0

    /// Whether the picture can stand in for a fresh drawing this frame.
    func fresh(frame: Int, every: Int, unit: Double, facing: Double, phase: SceneCreature.Phase, key: Int) -> Bool {
        guard image != nil, frame - drawnAt < every, abs(unit - self.unit) < max(0.5, unit * 0.01), abs(facing - self.facing) < 0.02,
              phase == self.phase, key == self.key else { return false }
        return true
    }

    /// Draws afresh: `paint` is called with the context set up so that the anchor is at the origin, `extent` (pixels about the anchor)
    /// is what it may cover, and the anchor's fraction of a pixel is kept.
    func redraw(extent: CGRect, anchor: CGPoint, frame: Int, unit: Double, facing: Double, phase: SceneCreature.Phase, key: Int, _ paint: (CGContext) -> Void) {
        let width = Int(ceil(extent.width)) + 2, height = Int(ceil(extent.height)) + 2
        let fits = context.map { $0.width >= width && $0.height >= height && $0.width <= width * 2 + 64 && $0.height <= height * 2 + 64 } ?? false
        if !fits {
            let w = (width + 31) / 32 * 32, h = (height + 31) / 32 * 32
            context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: ScenePaint.space, bitmapInfo: Sprites.bitmapInfo)
            context?.setAllowsAntialiasing(true)
        }
        guard let ctx = context else { image = nil; return }
        ctx.clear(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        let fx = Double(anchor.x) - floor(Double(anchor.x)), fy = Double(anchor.y) - floor(Double(anchor.y))
        origin = CGPoint(x: (-extent.minX).rounded(.up) + 1, y: (-extent.minY).rounded(.up) + 1)
        ctx.saveGState()
        ctx.translateBy(x: origin.x + CGFloat(fx), y: origin.y + CGFloat(fy))
        paint(ctx)
        ctx.restoreGState()
        image = ctx.makeImage()
        drawnAt = frame
        self.unit = unit
        self.facing = facing
        self.phase = phase
        self.key = key
    }

    /// Copies the last drawing onto the scene with its anchor at `anchor`, at whole pixels.
    func stamp(_ ctx: CGContext, at anchor: CGPoint) {
        guard let image else { return }
        ctx.draw(image, in: CGRect(x: floor(anchor.x) - origin.x, y: floor(anchor.y) - origin.y, width: CGFloat(image.width), height: CGFloat(image.height)))
    }
}

extension SceneWorld {
    /// What a hand-drawn creature is doing this frame, with the eased and sprung parts brought up to date in `memory`.
    func actor(of c: SceneCreature, memory: inout SceneRigMemory) -> SceneActor {
        let sp = cast.species[c.species]
        let unit = max(1, spriteHeight(c))
        var a = SceneActor()
        a.id = c.id
        a.time = time
        a.phase = c.phase
        a.phaseTime = c.phaseTime
        a.stride = c.stride
        a.pose = pose(of: c)
        a.quirk = c.quirk
        a.act = sp.act
        a.actSeconds = sp.actSeconds
        a.lift = c.lift / unit
        a.landed = c.landedAt != nil

        // How fast it is really going, from where it was last frame (some moves set the position directly).
        let dt = memory.time < 0 ? 0 : min(0.25, max(0, time - memory.time))
        if dt > 0 {
            let vx = (c.pos.x - memory.x) / dt, vy = (c.pos.y - memory.y) / dt
            let k = 1 - exp(-dt / 0.08)
            memory.speedX += (vx - memory.speedX) * k
            memory.speedY += (vy - memory.speedY) * k
        } else if memory.time < 0 {
            memory.speedX = c.vel.x
            memory.speedY = c.vel.y
        }
        memory.time = time
        memory.x = c.pos.x
        memory.y = c.pos.y
        let facing = c.dir >= 0 ? 1.0 : -1.0
        a.velocity = SIMD2(memory.speedX * facing / unit, memory.speedY / unit)
        let usual = max(1, sp.speed * layout.scale(c.depth))
        let pace = abs(memory.speedX) / usual
        a.backwards = memory.speedX * facing < -usual * 0.2

        let ease = dt > 0 ? 1 - exp(-dt / 0.12) : (memory.walk == 0 && pace > 0.3 ? 1 : 0)
        memory.walk += ((pace > 0.15 ? 1 : 0) - memory.walk) * ease
        memory.run += ((pace > 1.75 ? 1 : 0) - memory.run) * ease
        if memory.time >= 0, dt == 0, pace > 0.3 { memory.walk = max(memory.walk, 1) }
        a.walk = memory.walk
        a.run = memory.run

        // Alert when it has seen you, is coming, is doing its thing, or is scared.
        let alert: Double
        switch c.phase {
        case .noticing, .approaching, .acting: alert = 1
        case .fleeing, .backingOff: alert = 0.7
        default: alert = 0
        }
        memory.alert += (alert - memory.alert) * (dt > 0 ? 1 - exp(-dt / 0.18) : 0)
        a.alert = memory.alert

        // The head turns up or down toward the person's face when it is interested in them.
        var target = 0.0
        if let person, alert > 0.5, !(c.phase == .fleeing) {
            let headY = sp.isGroundBound ? c.pos.y + c.lift + unit * 0.75 : c.pos.y
            let dy = Double(person.head.y) - headY
            let dx = max(unit * 0.6, abs(Double(person.head.x) - c.pos.x))
            target = max(-0.55, min(0.6, atan2(dy, dx)))
        }
        SceneRig.spring(&memory.look, &memory.lookVelocity, to: target, frequency: 1.6, damping: 0.55, dt: dt)
        a.look = memory.look

        // The tail swings behind the body: it lags the walk and throws out when the creature turns or stops.
        let swing = sin(time * 1.3 + c.quirk * 7) * 0.5 * (1 - memory.alert * 0.6) + sin(c.stride) * 0.35 * memory.walk + memory.run * 0.6
        SceneRig.spring(&memory.tail, &memory.tailVelocity, to: swing, frequency: 1.1, damping: 0.35, dt: dt)
        a.tail = max(-1.5, min(1.5, memory.tail))
        return a
    }
}
