import CoreGraphics
import Foundation
import simd

// The behaviour model of the Vista scenes (Arctic, Outer Space, Dragon Castle, Enchanted Forest, Pirate Cove): what the creatures can
// sense, what kinds of creature there are, and what one creature remembers. Nothing here draws. `VistaWorld` steps it; `VistaLens`
// and the scene painters give it a look. It follows the same rules as the first five scenes (notice, come over, do something, run off
// when you wave, never cover the face) and adds the things these places need: creatures that rise out of the water, props that stay
// put, birds that sit on a raised hand, and acts timed out as beats.

/// The Vista scenes' source of chance: seeded, so a scene plays out the same way given the same seed and the same view.
struct VistaRandom: RandomNumberGenerator {
    private var base: SplitMix64

    init(seed: UInt64) { base = SplitMix64(seed: seed) }

    mutating func next() -> UInt64 { base.next() }
    /// 0 up to, but not including, 1.
    mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
    mutating func range(_ low: Double, _ high: Double) -> Double { low + (high - low) * unit() }
    mutating func chance(_ p: Double) -> Bool { unit() < p }
    /// -1 or 1.
    mutating func sign() -> Double { chance(0.5) ? 1 : -1 }
}

// MARK: - The person, as the creatures see them

/// Where the person is: enough to walk up to them, stop short of their face and land on their shoulder.
struct VistaPerson: Equatable {
    /// The bounds of the silhouette, in output pixels (origin lower left).
    var box: CGRect
    /// The middle of the head.
    var head: CGPoint
    /// Half the width of the head.
    var headRadius: Double

    var top: Double { box.maxY }
    /// Where the chin is, roughly: the head is taller than it is wide.
    var chin: Double { head.y - headRadius * 1.3 }

    /// The part of the picture no creature in front of you may cover: the head, a little generously.
    var faceZone: CGRect {
        let halfWidth = headRadius * 1.12 + 10
        return CGRect(x: head.x - halfWidth, y: chin - 8, width: halfWidth * 2, height: top - chin + 8)
    }

    /// How high the silhouette is at a column, without looking at the matte: the head, or the shoulders beside it.
    func estimatedTop(at x: Double) -> Double {
        abs(x - head.x) <= headRadius * 0.9 ? top : max(box.minY, chin - headRadius * 0.9)
    }

    /// Finds the person in a matte by looking at it on a coarse lattice. Nil when nobody (or only a speck) is there.
    static func find(in matte: MatteQuery, size: CGSize) -> VistaPerson? {
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
        return VistaPerson(box: box, head: CGPoint(x: headX, y: top - radius * 1.3), headRadius: radius)
    }
}

/// What the creatures can sense, for one step.
struct VistaContext {
    var size: CGSize
    /// The silhouette. Optional: with nobody there, the creatures just live their lives.
    var matte: MatteQuery?
    /// Where the silhouette changed since the last frame: arms thrown about light up.
    var motion: MatteQuery?
    var hands: [HandState]
    /// Where the person is. Worked out from the matte unless the caller already knows.
    var person: VistaPerson?

    init(size: CGSize, matte: MatteQuery? = nil, motion: MatteQuery? = nil, hands: [HandState] = [], person: VistaPerson? = nil) {
        self.size = size
        self.matte = matte
        self.motion = motion
        self.hands = hands
        self.person = person ?? matte.flatMap { VistaPerson.find(in: $0, size: size) }
    }
}

// MARK: - Places and kinds of creature

/// The ground and the sky of a scene: where feet land, how big things look at each distance, where fliers roam.
struct VistaLayout {
    var size = CGSize(width: 1280, height: 720)
    /// Where the feet land at the far lane (depth 0) and the near lane (depth 1).
    var farGround = 270.0
    var nearGround = 88.0
    /// How big a creature looks far away, compared with close up.
    var farScale = 0.42
    /// The band fliers roam in.
    var roamLow = 330.0
    var roamHigh = 650.0
    /// The depth where creatures stand when they come to you.
    var nearDepth = 0.92
    /// Depth at which a creature is drawn in front of the person rather than behind.
    var frontDepth = 0.5

    func ground(_ depth: Double) -> Double { farGround + (nearGround - farGround) * depth }
    func scale(_ depth: Double) -> Double { farScale + (1 - farScale) * depth }
}

/// The little things the world throws about: puffs, sparks, coins, notes. The scene decides their colours.
enum VistaFX: Int, CaseIterable {
    /// A soft puff of whatever the ground is made of.
    case dust
    /// Powder snow, thrown up and drifting down.
    case snow
    /// A four-pointed twinkle.
    case sparkle
    /// A glowing spark that rises and fades.
    case ember
    case smoke
    /// A drop of water, thrown up and falling.
    case splash
    case bubble
    /// A spinning gold coin, thrown up and falling.
    case coin
    /// A music note, rising and swaying.
    case note
    case heart
}

/// Something that happens at a moment in an act.
struct VistaBeat {
    enum Event {
        /// Says something in a bubble, for this many seconds.
        case say(String, Double)
        /// Shakes the picture, in pixels. Kept small: other people are watching the call.
        case shake(Double)
        /// Throws out this many particles of a kind, at a strength.
        case burst(VistaFX, Int, Double)
        /// Jumps, at this speed upward (pixels a second).
        case jump(Double)
    }

    var at: Double
    var event: Event
}

/// A steady stream of particles during part of an act.
struct VistaEmitter {
    var kind: VistaFX
    var from: Double
    var to: Double
    /// Particles a second.
    var rate: Double
    /// Where they come from, in units of the creature's height: x forward along the way it faces, y up from its feet (or its middle).
    var at = SIMD2<Double>(0, 0.5)
    /// Their speed, pixels a second, x forward.
    var velocity = SIMD2<Double>(0, 60)
    var spread = 40.0
    /// Rises from the ground all round the person instead (a beam of light from above).
    var aroundPerson = false
    var front = false
}

/// A kind of creature and everything that sets it apart: how big, how it moves, what it does when it comes to you.
struct VistaSpecies {
    enum Body {
        /// Walks, hops or scuttles along the ground.
        case walker
        /// Flaps about the air at any height.
        case flier
        /// Drifts: astronauts, space whales.
        case floater
        /// Circles slowly up in the sky.
        case soarer
        /// Lives below a line (the sea, a hill) and rises out of it: a kraken's arm, a giant cat peeping over the hill.
        case emerger
        /// Stays where it is put: a treasure chest.
        case prop
    }
    enum Gait { case walk, waddle, hop, scuttle, roll }
    /// How it takes a scare. Prey bolt; brutes back off a step and come again; the curious skip aside; the steady flinch where they are.
    enum Temper { case prey, brute, curious, steady }
    /// What it does once it has come to you.
    enum Act {
        /// Stands (or hovers, or rises) beside you and puts on a show, timed out by `beats`.
        case show
        /// Circles, then lands on your shoulder, or on an open hand held up.
        case perch
        /// Circles your head (or the whole of you), then goes on its way.
        case orbit
    }
    /// Where a flier waits to do its show: beside your head, above it, or high and out past your shoulder (to breathe fire
    /// down beside you).
    enum Spot { case beside, above, flank }

    var name: String
    /// Which drawing the scene uses for it.
    var art: Int
    /// How tall it stands close up, in pixels.
    var height: Double
    /// Width over height.
    var aspect: Double
    /// Pace close up, in pixels a second.
    var speed: Double
    var body = Body.walker
    var gait = Gait.walk
    var temper = Temper.curious
    var act = Act.show
    var spot = Spot.beside
    /// The depth it lives at: low is far, high is near.
    var home = 0.2
    /// Too big to come to the front: it comes up behind you instead.
    var farOnly = false
    /// How much faster it moves when it is after you.
    var charge = 1.4
    /// Creeps up slowly, then bursts.
    var stalks = false
    /// Slides on its belly when it hurries, like a penguin.
    var slides = false
    var perchesOnHand = false
    /// How readily it takes an interest in you; 1 is average.
    var interest = 1.0
    /// How long its show lasts, in seconds.
    var actSeconds = 2.4
    /// What it says during its show, and when.
    var cry = ""
    var cryAt = 0.35
    var beats: [VistaBeat] = []
    var emitters: [VistaEmitter] = []
    /// The heights (pixels from the bottom) it roams between, when that is not the whole sky.
    var band: ClosedRange<Double>?
    /// For a prop: where across the picture it stands, 0...1.
    var anchorX = 0.85
    /// How high its head gets during its show, as a share of its height: a bear rearing up stands half as tall again.
    var actReach = 1.0

    init(name: String, art: Int, height: Double, aspect: Double, speed: Double) {
        self.name = name
        self.art = art
        self.height = height
        self.aspect = aspect
        self.speed = speed
    }

    /// Feet on a line: the ground, the sea, the hilltop.
    var isGroundBound: Bool { body == .walker || body == .emerger || body == .prop }
    /// Moves about the air, centred on its position.
    var isAirborne: Bool { !isGroundBound }
}

/// Who lives in a scene, and the shape of its world.
struct VistaCast {
    var species: [VistaSpecies]
    /// One entry per creature: an index into `species`. The population is exactly this, so the cap is built in.
    var roster: [Int]
    var layout = VistaLayout()
    /// How many creatures can be on screen at once.
    var cap = 10
    /// How many are already in view when the scene starts (props always are).
    var visibleAtStart = 7
}

// MARK: - One creature

/// A speech bubble over a creature's head.
struct VistaBubble: Equatable {
    var text: String
    var age = 0.0
    var life: Double
}

/// An open hand held up, which birds like to land on.
struct VistaOffer: Equatable {
    var point: CGPoint
    var handID: Int
}

struct VistaCreature: Identifiable {
    enum Phase: Equatable {
        /// Off screen, waiting to come in.
        case away
        case entering
        /// Going about its business.
        case wandering
        /// Has just seen you: stops, looks, "!".
        case noticing
        /// Coming over to you.
        case approaching
        /// Doing its thing.
        case acting
        /// Going back to where it came from, after an act.
        case retreating
        /// Bolting, scared by a sudden movement.
        case fleeing
        /// Taking a step back facing you, or flinching where it is.
        case backingOff
    }

    let id: Int
    let species: Int
    var phase = Phase.away
    var phaseTime = 0.0
    /// Ground-bound: where the feet are. Everything else: the middle of the body.
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
    /// A timer for whatever it is waiting for.
    var wait = 0.0
    /// Time before it may take an interest in you again.
    var cooldown = 0.0
    /// A smoothed measure of how much waving is going on near it.
    var fear = 0.0
    /// Lift off the ground, in pixels: a hop, a jump.
    var lift = 0.0
    /// For a creature that rises out of something: 0 hidden, 1 all the way up.
    var rise = 0.0
    /// Sliding on its belly right now, and how far it has gone over onto its belly (0 standing, 1 flat), smoothed.
    var sliding = false
    var slide = 0.0
    var bubble: VistaBubble?
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
    /// What it is aiming at during its show, in output pixels: where a beam lands, where fire is breathed.
    var aim = SIMD2<Double>.zero
    /// Counts how often it has done things, for variations and paced beats.
    var beats = 0
    /// Fractional particles owed by its emitters.
    var owed = 0.0
}
