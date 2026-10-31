import CoreGraphics
import CoreImage

/// A place: who lives there, how it is painted and lit, and the animals that are painted by hand rather than taken from the emoji set.
protocol SceneStyle: AnyObject {
    var cast: SceneCast { get }
    var look: SceneLook { get }
    /// The line shown in the interface: what to do here.
    var hint: String { get }
    /// Everything behind the animals: sky, hills, trees, ground, and the slow things that move in them.
    func paintBackdrop(_ ctx: CGContext, frame: SceneFrame)
    /// Things in front of everybody, the person included: foliage at the edges, motes in the light.
    func paintForeground(_ ctx: CGContext, frame: SceneFrame)
    /// Draws an animal that is painted by hand, facing right, with the origin at its feet (or its middle, if it flies or swims).
    /// `size` is its full size; `mix` runs from 0 in the far lane to 1 in the near one.
    func paintCreature(_ ctx: CGContext, creature: SceneCreature, species: SceneSpecies, pose: ScenePose, size: CGSize, mix: Double, frame: SceneFrame)
    /// The hand-drawn rig for the kind of creature at `index` in the cast, if the scene has one. It takes the place of the emoji
    /// and of `paintCreature`.
    func puppet(for index: Int) -> ScenePuppet?
    /// Paints what the scene needs before its first frame, a step at a time, until `deadline` (a `CFAbsoluteTimeGetCurrent` time).
    /// Returns true once everything is ready. Called on the video queue, so making a scene stays instant.
    func prepare(until deadline: Double) -> Bool
}

extension SceneStyle {
    func paintCreature(_ ctx: CGContext, creature: SceneCreature, species: SceneSpecies, pose: ScenePose, size: CGSize, mix: Double, frame: SceneFrame) {}
    func puppet(for index: Int) -> ScenePuppet? { nil }
    func prepare(until deadline: Double) -> Bool { true }
}

/// A living backdrop. The person stands in front of a painted world and the animals in it notice them, come over, do something
/// and run off when they are scared. Painted in layers: the world, the animals far away, the person, the animals close up, the
/// foliage in front of everything.
final class SceneLens: Lens {
    let needs: LensNeeds
    var wantsMatteGrid: Bool { true }
    var status: LensStatus? { published.value }

    private(set) var world: SceneWorld
    private let style: SceneStyle
    private let renderer: SceneRenderer
    private var previousGrid: MatteGrid?
    private var shift = CGPoint.zero
    private let published = StatusBox()
    /// Whether the scene's pictures are painted, and when it began to fade in (world time). A scene that needed painting first
    /// fades in over the room, so nothing pops.
    private var ready = false
    private var shownAt: Double?
    private var neededPainting = false
    private var firstFrame = true
    static let fadeSeconds = 0.5

    init(style: SceneStyle, hands: Bool = false, seed: UInt64 = .random(in: .min ... .max)) {
        self.style = style
        needs = hands ? [.matte, .hands] : [.matte]
        world = SceneWorld(cast: style.cast, seed: seed)
        let sprites = SceneSprites(cast: style.cast, look: style.look)
        renderer = SceneRenderer(sprites: sprites, puppets: style.cast.species.indices.map { style.puppet(for: $0) }) { [unowned style] ctx, creature, species, pose, size, mix, frame in
            style.paintCreature(ctx, creature: creature, species: species, pose: pose, size: size, mix: mix, frame: frame)
        }
        published.value = LensStatus(style.hint)
    }

    /// For tests and previews: sends the first animal of a kind over to the person.
    func attract(_ name: String) {
        if let id = world.creatures.first(where: { world.cast.species[$0.species].name == name })?.id { world.attract(id) }
    }

    /// For tests: puts creature `id` at rest at a place, and returns the lens's world for inspection.
    func stage(_ id: Int, x: Double, depth: Double? = nil) { world.stage(id, x: x, depth: depth) }

    func restart() {
        world = SceneWorld(cast: style.cast, seed: .random(in: .min ... .max))
        previousGrid = nil
        renderer.forget()
        // The pictures are kept; a scene that is already showing does not fade in again.
        if ready { shownAt = -.infinity }
    }

    /// For tests and previews: paints everything now, so the next frame shows the whole scene.
    func paintNow() {
        while !style.prepare(until: CFAbsoluteTimeGetCurrent() + 1) {}
        ready = true
        shownAt = -.infinity
    }

    func render(_ input: LensInput) -> CIImage {
        let grid = input.matteGrid
        let motion = grid.flatMap { current in previousGrid.map { current.motion(since: $0) } }
        world.step(input.dt, context: SceneContext(size: input.rect.size, matte: grid, motion: motion, hands: input.hands))
        previousGrid = grid?.snapshot()

        // The world slides a little the other way as the person moves across the picture.
        let wanted = world.person.map { (Double($0.box.midX) / Double(input.rect.width) - 0.5) * 2 } ?? 0
        let k = 1 - exp(-input.dt * 2.5)
        shift.x += (CGFloat(wanted) - shift.x) * CGFloat(k)
        let frame = SceneFrame(time: world.time, size: input.rect.size, shift: shift)

        published.value = LensStatus(world.person == nil ? "Step into view and the animals will find you" : style.hint)

        // The scene paints itself a few milliseconds at a time on the first frames; the room stays until it is ready.
        if !ready {
            ready = style.prepare(until: CFAbsoluteTimeGetCurrent() + (firstFrame ? 0.024 : 0.012))
            firstFrame = false
            if !ready { neededPainting = true; return input.composed }
            shownAt = neededPainting ? world.time : -.infinity
        }

        guard let behind = input.services.overlay({ ctx in
            style.paintBackdrop(ctx, frame: frame)
            renderer.drawShadows(world, in: ctx)
            renderer.drawCreatures(world, front: false, in: ctx, frame: frame)
            renderer.drawEffects(world, front: false, in: ctx)
        }) else { return input.composed }
        let withPerson = input.matte == nil ? behind : input.placingPerson(over: behind)

        let front = input.services.overlay { ctx in
            renderer.drawCreatures(world, front: true, in: ctx, frame: frame)
            renderer.drawEffects(world, front: true, in: ctx)
            style.paintForeground(ctx, frame: frame)
            renderer.drawBubbles(world, in: ctx)
        }
        var out = front.map { $0.composited(over: withPerson) } ?? withPerson

        if world.shake > 0.3 {
            let t = world.time
            let move = CGAffineTransform(translationX: CGFloat(sin(t * 61) * world.shake), y: CGFloat(cos(t * 53) * world.shake * 0.8))
            out = out.clampedToExtent().transformed(by: move)
        }
        out = out.cropped(to: input.rect)
        if let shownAt, world.time >= shownAt, world.time - shownAt < Self.fadeSeconds {
            let k = max(0, (world.time - shownAt) / Self.fadeSeconds)
            out = out.fading(k * k * (3 - 2 * k)).composited(over: input.composed).cropped(to: input.rect)
        }
        return out
    }
}
