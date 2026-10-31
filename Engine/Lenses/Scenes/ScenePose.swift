import CoreGraphics
import Foundation

/// How a creature's body is bent out of shape at this moment: the walk bob, rearing up to roar, a squash on landing.
/// Worked out from the behaviour model alone, so the drawing code only has to apply it.
struct ScenePose {
    /// Pixels off the ground.
    var lift = 0.0
    /// Vertical and horizontal scale.
    var stretch = 1.0
    var squash = 1.0
    /// Radians, positive tips the nose up (about the back feet for walkers, the middle for the rest).
    var tilt = 0.0
    /// Pixels forward along the way it faces.
    var shift = 0.0
    /// 0...1: how far a painted creature has reared up or opened its mouth.
    var open = 0.0
}

extension SceneWorld {
    private static func ease(_ k: Double) -> Double { let x = min(1, max(0, k)); return x * x * (3 - 2 * x) }

    /// A shape that rises to 1 by `rise`, stays there until `fall`, and is gone again by `end`.
    private static func envelope(_ t: Double, rise: Double, fall: Double, end: Double) -> Double {
        t < fall ? ease(t / rise) : 1 - ease((t - fall) / (end - fall))
    }

    func pose(of c: SceneCreature) -> ScenePose {
        let sp = cast.species[c.species]
        let h = height(c)
        let t = c.phaseTime
        let moving = abs(c.vel.x) > 8
        var p = ScenePose()
        p.stretch = 1 + 0.014 * sin(time * 2.1 + c.quirk * 6)
        p.squash = 1 - 0.008 * sin(time * 2.1 + c.quirk * 6)

        switch sp.body {
        case .walker:
            switch sp.gait {
            case .walk:
                if moving {
                    // A bob with each step. Small animals squash and stretch too; the big ones are kept to a bob, which is much cheaper to draw.
                    p.lift = abs(sin(c.stride)) * h * 0.03
                    if h < 120 {
                        p.tilt = sin(c.stride) * 0.04
                        p.stretch += 0.04 * cos(2 * c.stride)
                        p.squash -= 0.03 * cos(2 * c.stride)
                    }
                }
            case .hop:
                let air = max(0, sin(c.stride))
                if moving {
                    p.lift = air * h * 0.55
                    p.stretch += 0.12 * air
                    p.squash -= 0.08 * air
                    p.tilt = (air - 0.5) * 0.3
                }
            case .slither:
                break
            }
        case .flier:
            p.lift = sin(time * 2.2 + c.quirk * 8) * h * 0.05
            p.stretch += 0.16 * sin(c.stride)
            p.squash -= 0.1 * sin(c.stride)
            p.tilt = max(-0.4, min(0.4, c.vel.y * 0.0015)) * c.dir
        case .swimmer:
            p.lift = sin(time * 1.4 + c.quirk * 8) * h * 0.03
            p.tilt = max(-0.35, min(0.35, c.vel.y * 0.0012)) * c.dir + sin(c.stride * 0.6) * 0.04
            p.squash -= 0.04 * sin(c.stride * 0.6)
        case .soarer:
            p.tilt = -0.18 * c.dir * cos(c.stride)
            p.stretch += 0.12 * sin(time * 3.2 + c.quirk * 9)
        case .floater:
            p.lift = sin(time * 1.6 + c.quirk * 8) * h * 0.07
            // Small ones pulse as they drift; big ones only bob, which is much cheaper to draw.
            if h < 130 {
                p.stretch += 0.08 * sin(time * 2.4 + c.quirk * 5)
                p.squash -= 0.06 * sin(time * 2.4 + c.quirk * 5)
            }
        }

        switch c.phase {
        case .noticing:
            // A start: straightens up, then settles.
            let k = max(0, 1 - t / 0.3)
            p.stretch += 0.08 * k
            p.squash -= 0.05 * k
        case .approaching:
            if sp.stalks, sp.body == .walker { p.stretch -= 0.1; p.squash += 0.05 }
        case .fleeing:
            p.stretch -= 0.04
            p.squash += 0.05
        case .backingOff:
            p.stretch += 0.05
        case .acting:
            applyAct(sp, t, &p)
        default:
            break
        }
        return p
    }

    private func applyAct(_ sp: SceneSpecies, _ t: Double, _ p: inout ScenePose) {
        let rise = Self.envelope(t, rise: 0.3, fall: sp.actSeconds - 0.5, end: sp.actSeconds)
        switch sp.act {
        case .roar:
            p.tilt = 0.2 * rise + 0.012 * sin(t * 55) * rise
            p.stretch += 0.07 * rise
            p.open = rise
        case .trumpet:
            let up = Self.envelope(t, rise: 0.35, fall: sp.actSeconds - 0.6, end: sp.actSeconds)
            p.tilt = 0.12 * up
            p.stretch += 0.06 * up
            p.open = up
        case .stomp:
            if t > 0.2, t < 1.7 { p.lift += 12 * max(0, sin((t - 0.2) * 2 * .pi / 0.5)) }
            if t > 1.7, t < 2.2 { p.shift = 38 * sin((t - 1.7) / 0.5 * .pi); p.tilt = -0.08 }
        case .chestBeat:
            let up = Self.envelope(t, rise: 0.4, fall: sp.actSeconds - 0.6, end: sp.actSeconds)
            p.tilt = 0.14 * up
            p.stretch += 0.1 * up
            if t > 0.5, t < 2.1 { p.squash += 0.05 * max(0, sin(t * 2 * .pi / 0.26)) }
            p.open = up
        case .snap:
            let wave = max(0, sin(t * 2 * .pi / 0.55))
            p.tilt = 0.13 * wave
            p.squash += 0.05 * wave
            p.open = wave
        case .rear:
            p.open = Self.envelope(t, rise: 0.5, fall: sp.actSeconds - 0.6, end: sp.actSeconds)
        case .lean:
            p.tilt = -0.06 * rise
            p.stretch -= 0.04 * rise
            p.shift = 14 * rise
            p.open = rise
        case .boo:
            p.stretch += 0.1 * rise
            p.tilt = 0.05 * sin(t * 28) * rise
            p.open = rise
        case .hop, .climb, .perch, .orbit, .lunge, .drop:
            break
        }
    }
}
