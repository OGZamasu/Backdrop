import CoreGraphics
import Foundation
import simd

// The behaviour model of a scene: what the creatures can sense, what kinds of creature there are, and what one creature remembers.
// Nothing here draws. `SceneWorld` (SceneWorld.swift) steps it; `SceneLens` and the scene painters give it a look.

// MARK: - The person, as the animals see them

/// Where the person is: enough to walk up to them, stop short of their face and climb on their shoulder.
struct ScenePerson: Equatable {
    /// The bounds of the silhouette, in output pixels (origin lower left).
    var box: CGRect
    /// The middle of the head.
    var head: CGPoint
    /// Half the width of the head.
    var headRadius: Double

    var top: Double { box.maxY }
    /// Where the chin is, roughly: the head is taller than it is wide.
    var chin: Double { head.y - headRadius * 1.3 }

    /// The part of the picture no animal in front of you may cover: the head, a little generously.
    var faceZone: CGRect {
        let halfWidth = headRadius * 1.12 + 10
        return CGRect(x: head.x - halfWidth, y: chin - 8, width: halfWidth * 2, height: top - chin + 8)
    }

    /// How high the silhouette is at a column, without looking at the matte: the head, or the shoulders beside it.
    func estimatedTop(at x: Double) -> Double {
        abs(x - head.x) <= headRadius * 0.9 ? top : max(box.minY, chin - headRadius * 0.9)
    }

    /// Finds the person in a matte by looking at it on a coarse lattice. Nil when nobody (or only a speck) is there.
    static func find(in matte: MatteQuery, size: CGSize) -> ScenePerson? {
        let step = 32.0
        let cols = max(1, Int(size.width / step)), rows = max(1, Int(size.height / step))
        var solid = [Bool](repeating: false, count: cols * rows)
        var count = 0, minC = cols, maxC = -1, minR = rows, maxR = -1
        for r in 0..<rows {
            let y = (Double(r) + 0.5) * step
            for c in 0..<cols where matte.coverage(x: (Double(c) + 0.5) * step, y: y) > 0.5 {
                solid[r * cols + c] = true
                count += 1
                minC = min(minC, c); maxC = max(maxC, c); minR = min(minR, r); maxR = max(maxR, r)
            }
        }
        guard count >= 14 else { return nil }

        // The crown: the middle of the highest cells.
        var crown: [Double] = []
        for r in stride(from: maxR, through: max(minR, maxR - 1), by: -1) {
            for c in 0..<cols where solid[r * cols + c] { crown.append((Double(c) + 0.5) * step) }
        }
        crown.sort()
        let headX = crown.isEmpty ? Double(minC + maxC + 1) / 2 * step : crown[crown.count / 2]

        // The exact top of the head, from a finer look at that column.
        var top = (Double(maxR) + 0.5) * step
        var scan = (Double(maxR) + 2) * step
        while scan > top {
            if matte.coverage(x: headX, y: scan) > 0.5 { top = scan; break }
            scan -= 2
        }
        top = min(top, size.height)

        let box = CGRect(x: Double(minC) * step, y: Double(minR) * step, width: Double(maxC - minC + 1) * step, height: max(1, top - Double(minR) * step))

        // How wide the head is, a little way below the crown, before the shoulders begin.
        let down = min(70, 0.12 * box.height)
        let y = top - down
        var left = headX, right = headX
        while left > headX - 170, matte.coverage(x: left - 8, y: y) > 0.5 { left -= 8 }
        while right < headX + 170, matte.coverage(x: right + 8, y: y) > 0.5 { right += 8 }
        let radius = min(150, max(40, (right - left) / 2 * 1.08))
        return ScenePerson(box: box, head: CGPoint(x: headX, y: top - radius * 1.3), headRadius: radius)
    }
}

/// What the creatures can sense, for one step.
struct SceneContext {
    var size: CGSize
    /// The silhouette. Optional: with nobody there, the animals just live their lives.
    var matte: MatteQuery?
    /// Where the silhouette changed since the last frame: arms thrown about light up.
    var motion: MatteQuery?
    var hands: [HandState]
    /// Where the person is. Worked out from the matte unless the caller already knows.
    var person: ScenePerson?

    init(size: CGSize, matte: MatteQuery? = nil, motion: MatteQuery? = nil, hands: [HandState] = [], person: ScenePerson? = nil) {
        self.size = size
        self.matte = matte
        self.motion = motion
        self.hands = hands
        self.person = person ?? matte.flatMap { ScenePerson.find(in: $0, size: size) }
    }
}

// MARK: - Places and kinds of creature

/// The ground and the sky of a scene: where feet land, how big things look at each distance, where fliers and swimmers roam.
struct SceneLayout {
    var size = CGSize(width: 1280, height: 720)
    /// Where the feet land at the far lane (depth 0) and the near lane (depth 1).
    var farGround = 270.0
    var nearGround = 88.0
    /// How big a creature looks far away, compared with close up.
    var farScale = 0.42
    /// The band fliers and swimmers roam in.
    var roamLow = 330.0
    var roamHigh = 650.0
    /// The depth where animals stand when they come to you.
    var nearDepth = 0.92
    /// Depth at which a creature is drawn in front of the person rather than behind.
    var frontDepth = 0.5

    func ground(_ depth: Double) -> Double { farGround + (nearGround - farGround) * depth }
    func scale(_ depth: Double) -> Double { farScale + (1 - farScale) * depth }
}

/// A kind of animal and everything that sets it apart: how big, how it moves, what it does when it comes for you.
struct SceneSpecies {
    enum Body {
        /// Walks, hops or slithers along the ground.
        case walker
        /// Flaps about the air at any height.
        case flier
        /// Swims through the water.
        case swimmer
        /// Circles slowly up in the sky.
        case soarer
        /// Drifts: jellyfish, ghosts.
        case floater
    }
    enum Gait { case walk, hop, slither }
    /// How it takes a scare. Prey bolt; brutes back off a step and come again; the curious just skip aside.
    enum Temper { case prey, brute, curious }
    /// What it does once it has come to you.
    enum Act {
        case roar, trumpet, stomp, chestBeat, snap, rear, lean, hop
        /// Climbs onto your head or shoulder and sits there, bouncing.
        case climb
        /// Circles, then lands on your shoulder, or on an open hand held up.
        case perch
        /// Circles you in a wide ring, then goes on its way.
        case orbit
        /// Circles, then comes straight at you and veers off.
        case lunge
        /// Floats up beside you and says boo.
        case boo
        /// Drops down on a thread beside your head.
        case drop
    }

    var name: String
    /// The emoji it is drawn from. Empty for creatures that are painted by hand.
    var glyph: String
    /// Which way the emoji naturally faces, so it can be flipped to face the way it moves.
    var facesRight: Bool
    /// How tall it stands close up, in pixels.
    var height: Double
    /// Width over height of its art.
    var aspect: Double
    /// Walking pace close up, in pixels a second.
    var speed: Double
    var body = Body.walker
    var gait = Gait.walk
    var temper = Temper.curious
    var act = Act.hop
    /// The depth it lives at: low is far, high is near.
    var home = 0.2
    /// Too tall to come to the front: it leans in from behind you instead.
    var farOnly = false
    /// How much faster it moves when it is after you.
    var charge = 1.4
    /// Creeps up slowly, then bursts.
    var stalks = false
    /// Lands on a raised open hand.
    var perchesOnHand = false
    /// How readily it takes an interest in you; 1 is average.
    var interest = 1.0
    /// How many it draws: a school of fish is one creature drawn many times.
    var group = 1
    /// How long its act lasts, in seconds.
    var actSeconds = 2.4
    /// Whether the scene paints it itself rather than using an emoji.
    var painted = false
    /// 1 for solid; less for a ghost, which you can see the room through.
    var opacity = 1.0
    /// The colour of a light that it gives off, like a lit pumpkin.
    var glow: UInt32?
    /// Hangs from a thread out of the top of the picture, like a spider.
    var hangs = false
    /// The heights (pixels from the bottom) it roams between, when that is not the whole sky or sea.
    var band: ClosedRange<Double>?
    /// What it says when it does its act, if not the usual cry for that act.
    var shout: String?
    /// A colour wash over the emoji, as red, green, blue and strength: makes a dark bird of prey out of an eagle.
    var tint: SIMD4<Double>?

    var isGroundBound: Bool { body == .walker }
}

/// Who lives in a scene, and the shape of its world.
struct SceneCast {
    var species: [SceneSpecies]
    /// One entry per creature: an index into `species`. The population is exactly this, so the cap is built in.
    var roster: [Int]
    var layout = SceneLayout()
    /// How many creatures can be on screen at once.
    var cap = 12
    /// How many are already in view when the scene starts.
    var visibleAtStart = 7
    /// Under water: dust becomes bubbles.
    var underwater = false
}

// MARK: - One creature

/// A speech bubble over a creature's head.
struct SceneBubble: Equatable {
    var text: String
    var age = 0.0
    var life: Double
}

struct SceneCreature: Identifiable {
    enum Phase: Equatable {
        /// Off screen, waiting to walk in.
        case away
        /// Walking in from the edge.
        case entering
        /// Going about its business.
        case wandering
        /// Has just seen you: stops, looks, "!".
        case noticing
        /// Coming after you.
        case approaching
        /// Doing its thing: roaring, trumpeting, sitting on your head.
        case acting
        /// Going back to where it came from, after an act.
        case retreating
        /// Bolting, scared by a sudden movement.
        case fleeing
        /// Taking a few steps back, facing you.
        case backingOff
    }

    let id: Int
    let species: Int
    var phase = Phase.away
    var phaseTime = 0.0
    /// Walkers: where the feet are. Everything else: the middle of the body.
    var pos = SIMD2<Double>.zero
    var vel = SIMD2<Double>.zero
    /// 0 far, 1 near. Decides the size, the height on the ground and whether it is drawn behind you or in front.
    var depth = 0.2
    /// Which way it faces: +1 right, -1 left. `turn` follows it smoothly, so a turn looks like a turn.
    var dir = 1.0
    var turn = 1.0
    /// The walk cycle, in radians.
    var stride = 0.0
    var target = SIMD2<Double>.zero
    /// A timer for whatever it is waiting for: rest between walks, the wait to come back.
    var wait = 0.0
    /// Time before it may take an interest in you again.
    var cooldown = 0.0
    /// A smoothed measure of how much waving is going on near it.
    var fear = 0.0
    /// Lift off the ground, in pixels: a hop, a jump onto your shoulder.
    var lift = 0.0
    var bubble: SceneBubble?
    /// A number of its own that keeps two of a kind from moving in step.
    var quirk = 0.0
    /// Which flank it is heading for, or sitting at: -1 left of you, +1 right.
    var side = 1.0
    /// For perching: how long to stay, and whether it is on a hand rather than a shoulder.
    var stay = 4.0
    var onHand = false
    var landedAt: Double?
    /// Heading for the edge of the picture to leave.
    var leaving = false
    /// Where it started an act from, for acts that travel.
    var origin = SIMD2<Double>.zero
    /// Counts how often it has done its act (for a variation), and used to pace repeated beats.
    var beats = 0
}
