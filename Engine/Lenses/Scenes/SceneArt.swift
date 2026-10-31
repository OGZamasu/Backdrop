import AppKit
import CoreGraphics
import Foundation
import simd

/// How a scene's light falls on its animals, so that emoji sit in the picture instead of on top of it.
struct SceneLook {
    /// The colour of the air between you and things far away, and how much of it far animals take on.
    var haze: UInt32 = 0xE8B07A
    var hazeAmount = 0.16
    /// How far animals are shaded, and in what colour.
    var dusk: UInt32 = 0x5A3050
    var duskAmount = 0.28
    /// The colour of the light on animals close up.
    var warm: UInt32 = 0xFFB05A
    var warmAmount = 0.16
    /// How much darker the feet are than the head, 0...1.
    var shade = 0.28
    /// The colour of dust kicked up.
    var dust: UInt32 = 0xE8C58A
    /// How dark ground shadows are.
    var shadow = 0.42
    /// Which way shadows fall along the ground: -1 left, +1 right, as a fraction of the animal's width.
    var shadowLean = -0.18
    /// The colour of droplets and bubbles.
    var water: UInt32 = 0xDDF2FF
}

/// The emoji of a scene, cut out, scaled to the size they will be drawn at, and lit for the far and the near lane. Drawn once.
final class SceneSprites {
    /// One animal, lit for each lane and made both ways round, so that facing either way is a plain copy.
    struct Baked {
        var near: CGImage
        var far: CGImage
        var nearFlipped: CGImage
        var farFlipped: CGImage

        func image(near wantsNear: Bool, flipped: Bool) -> CGImage {
            wantsNear ? (flipped ? nearFlipped : near) : (flipped ? farFlipped : far)
        }
    }

    private(set) var baked: [Baked?] = []
    /// A soft glow for each animal that gives off light, at four strengths so that it can pulse by switching between them.
    private(set) var glows: [[CGImage]?] = []
    let look: SceneLook

    init(cast: SceneCast, look: SceneLook) {
        self.look = look
        // Each animal is made at the size it stands at in the far lane and in the near lane, so that most of the time it is copied, not scaled.
        let layout = cast.layout
        baked = cast.species.map { sp in
            guard !sp.painted, !sp.glyph.isEmpty,
                  let far = Self.cutOut(sp.glyph, height: sp.height * layout.scale(sp.home)),
                  let near = Self.cutOut(sp.glyph, height: sp.height * layout.scale(max(sp.home, layout.nearDepth))) else { return nil }
            let nearLit = Self.lit(near, look: look, tint: sp.tint, far: false, opacity: sp.opacity), farLit = Self.lit(far, look: look, tint: sp.tint, far: true, opacity: sp.opacity)
            return Baked(near: nearLit, far: farLit, nearFlipped: Self.mirrored(nearLit), farFlipped: Self.mirrored(farLit))
        }
        glows = cast.species.map { sp in
            guard let glow = sp.glow else { return nil }
            let radius = max(30, sp.height * layout.scale(sp.home))
            let side = Int(radius * 2)
            let levels = (0..<4).compactMap { i in
                ScenePaint.picture(width: side, height: side) { ctx in
                    ScenePaint.blob(ctx, CGPoint(x: radius, y: radius), rx: radius, ry: radius, ScenePaint.color(glow, 0.3 + 0.1 * Double(i)), inner: 0.1)
                }
            }
            return levels.count == 4 ? levels : nil
        }
    }

    /// An emoji with its empty margins trimmed away, drawn `height` pixels tall.
    static func cutOut(_ glyph: String, height: Double) -> CGImage? {
        guard let raw = Sprites.emoji(glyph, size: CGFloat(min(220, max(48, height * 1.1)))), let box = opaqueBounds(raw),
              let trimmed = raw.cropping(to: box) else { return nil }
        let scale = height / Double(trimmed.height)
        return ScenePaint.picture(width: Int((Double(trimmed.width) * scale).rounded(.up)), height: Int(height.rounded(.up))) { ctx in
            ctx.draw(trimmed, in: CGRect(x: 0, y: 0, width: CGFloat(trimmed.width) * CGFloat(scale), height: CGFloat(height.rounded(.up))))
        }
    }

    static func mirrored(_ image: CGImage) -> CGImage {
        ScenePaint.picture(width: image.width, height: image.height) { ctx in
            ctx.translateBy(x: CGFloat(image.width), y: 0)
            ctx.scaleBy(x: -1, y: 1)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        } ?? image
    }

    /// The smallest rectangle (in the image's own top-down rows) holding everything that is not clear.
    static func opaqueBounds(_ image: CGImage) -> CGRect? {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let w = image.width, h = image.height, rowBytes = image.bytesPerRow
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w where bytes[y * rowBytes + x * 4 + 3] > 20 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// A copy lit for the scene: hazy and pale far away; warm, with darker feet, close up.
    static func lit(_ art: CGImage, look: SceneLook, tint: SIMD4<Double>?, far: Bool, opacity: Double = 1) -> CGImage {
        ScenePaint.picture(width: art.width, height: art.height) { ctx in
            let rect = CGRect(x: 0, y: 0, width: art.width, height: art.height)
            ctx.setAlpha(CGFloat((far ? 0.94 : 1) * opacity))           // far animals are a little see-through, and that is baked in
            ctx.draw(art, in: rect)
            ctx.setAlpha(1)
            ctx.setBlendMode(.sourceAtop)
            if let tint {
                ctx.setFillColor(CGColor(colorSpace: ScenePaint.space, components: [tint.x, tint.y, tint.z, tint.w])!)
                ctx.fill(rect)
            }
            if far {
                // Far off the animals are backlit and in shade: darker and a little hazy, not paler.
                ctx.setFillColor(ScenePaint.color(look.dusk, look.duskAmount))
                ctx.fill(rect)
                ctx.setFillColor(ScenePaint.color(look.haze, look.hazeAmount))
                ctx.fill(rect)
            } else {
                ctx.setFillColor(ScenePaint.color(look.warm, look.warmAmount))
                ctx.fill(rect)
                let g = ScenePaint.gradient([(0, ScenePaint.color(0x20100A, look.shade)), (0.5, ScenePaint.color(0x20100A, 0))])
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(art.height)), options: [])
            }
        } ?? art
    }
}

/// The speech bubbles: a white balloon with a word or an emoji in it, drawn once for each thing that is ever said.
enum SceneBubbleArt {
    private static let lock = NSLock()
    private static var cache: [String: CGImage] = [:]

    /// The bubble, with its pointer at the bottom middle.
    static func image(_ text: String) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[text] { return hit }
        let excited = text.hasSuffix("!") && text.count <= 2
        // The house style for words on the picture: bold rounded type, warm ink, a soft shadow under a cream balloon.
        let base = NSFont.systemFont(ofSize: excited ? 44 : 31, weight: .heavy)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: base.pointSize) } ?? base
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: excited ? NSColor(red: 0.89, green: 0.28, blue: 0.17, alpha: 1) : NSColor(red: 0.17, green: 0.14, blue: 0.12, alpha: 1),
            .kern: excited ? 0 : 0.6,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let box = string.size()
        let pad: CGFloat = excited ? 14 : 17, tail: CGFloat = 15, edge: CGFloat = 8
        let body = CGSize(width: max(box.width + pad * 2, 54), height: box.height + pad * 0.8)
        let width = Int(ceil(body.width + edge * 2)), height = Int(ceil(body.height + tail + edge * 2))
        let image = ScenePaint.picture(width: width, height: height) { ctx in
            let rect = CGRect(x: edge, y: tail + edge, width: body.width, height: body.height)
            let radius = min(rect.height / 2, 26)
            let path = CGMutablePath()
            path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
            path.move(to: CGPoint(x: rect.midX - 10, y: rect.minY + 1))
            path.addQuadCurve(to: CGPoint(x: rect.midX - 2, y: edge + 1), control: CGPoint(x: rect.midX - 4, y: rect.minY - 4))
            path.addQuadCurve(to: CGPoint(x: rect.midX + 11, y: rect.minY + 1), control: CGPoint(x: rect.midX + 2, y: rect.minY - 2))
            path.closeSubpath()
            ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 7, color: CGColor(gray: 0, alpha: 0.38))
            ctx.setFillColor(ScenePaint.color(0xFFFBF2))
            ctx.addPath(path)
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            // A soft shade along the bottom of the balloon, for a little roundness.
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ScenePaint.fillDown(ctx, CGRect(x: rect.minX, y: edge, width: rect.width, height: rect.height + tail),
                                [(0, ScenePaint.color(0xFFFFFF, 0)), (0.65, ScenePaint.color(0xFFFFFF, 0)), (1, ScenePaint.color(0xE8D8C0, 0.6))])
            ctx.restoreGState()
            ctx.setStrokeColor(ScenePaint.color(0x2A2420, 0.85))
            ctx.setLineWidth(2.4)
            ctx.setLineJoin(.round)
            ctx.addPath(path)
            ctx.strokePath()
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            string.draw(at: NSPoint(x: rect.midX - box.width / 2, y: rect.midY - box.height / 2 + 1))
            NSGraphicsContext.restoreGraphicsState()
        }
        if let image { cache[text] = image }
        return image
    }
}

/// What the painter of a scene is told about the moment it is drawing.
struct SceneFrame {
    var time: Double
    var size: CGSize
    /// Where the person stands, -1 at the left edge to 1 at the right: shifts the layers a little as they move.
    var shift: CGPoint
}

/// Draws the animals, their shadows, dust and speech bubbles for a world. The scene supplies the animals it paints by hand.
struct SceneRenderer {
    let sprites: SceneSprites
    let painter: (CGContext, SceneCreature, SceneSpecies, ScenePose, CGSize, Double, SceneFrame) -> Void
    /// The hand-drawn rigs, one for each kind of creature that has one.
    let puppets: [ScenePuppet?]
    /// The paint box the rigs use, with this scene's light.
    let ink: SceneInk
    private let memory = SceneRigMemoryBox()

    init(sprites: SceneSprites, puppets: [ScenePuppet?] = [], painter: @escaping (CGContext, SceneCreature, SceneSpecies, ScenePose, CGSize, Double, SceneFrame) -> Void) {
        self.sprites = sprites
        self.painter = painter
        self.puppets = puppets
        ink = SceneInk(look: sprites.look, lights: SceneLightBox(look: sprites.look))
    }

    // MARK: Shadows

    /// Soft shadows on the ground. They are painted with the backdrop, so the person (who is in front of the ground) covers them.
    func drawShadows(_ world: SceneWorld, in ctx: CGContext) {
        let look = sprites.look
        for c in world.creatures where c.phase != .away {
            let sp = world.cast.species[c.species]
            guard sp.body != .swimmer, sp.body != .floater || sp.act == .boo else { continue }
            let w = world.width(c), h = world.height(c)
            let ground = world.layout.ground(c.depth)
            let altitude = sp.isGroundBound ? max(0, c.lift) : max(0, c.pos.y - ground)
            let fade = 1 / (1 + altitude / (h * 0.5 + 30))
            let width = w * (sp.isGroundBound ? 0.95 : 0.6) * (0.8 + 0.2 * fade), height = max(7, w * 0.15) * (sp.isGroundBound ? 1 : 0.8)
            let alpha = look.shadow * fade * (0.55 + 0.45 * world.layout.scale(c.depth))
            let x = c.pos.x + w * look.shadowLean * (sp.isGroundBound ? 1 : 2)
            // Two ellipses, one inside the other, stand in for a soft edge.
            ctx.setFillColor(CGColor(gray: 0, alpha: CGFloat(alpha * 0.5)))
            ctx.fillEllipse(in: CGRect(x: x - width * 0.55, y: ground - height * 0.55, width: width * 1.1, height: height * 1.1))
            ctx.setFillColor(CGColor(gray: 0, alpha: CGFloat(alpha * 0.7)))
            ctx.fillEllipse(in: CGRect(x: x - width * 0.38, y: ground - height * 0.34, width: width * 0.76, height: height * 0.68))
        }
    }

    // MARK: Creatures

    func drawCreatures(_ world: SceneWorld, front: Bool, in ctx: CGContext, frame: SceneFrame) {
        if world.time != memory.lastTime {
            memory.lastTime = world.time
            memory.frame += 1
        }
        var order = world.creatures.filter { $0.phase != .away && ($0.depth >= world.layout.frontDepth) == front }
        order.sort { $0.depth != $1.depth ? $0.depth < $1.depth : $0.pos.y > $1.pos.y }
        ctx.interpolationQuality = .medium
        for c in order { draw(c, in: world, ctx: ctx, frame: frame) }
        ctx.interpolationQuality = .high
    }

    private func draw(_ c: SceneCreature, in world: SceneWorld, ctx: CGContext, frame: SceneFrame) {
        let sp = world.cast.species[c.species]
        if c.species < puppets.count, let puppet = puppets[c.species] {
            drawPuppet(puppet, c, sp, world: world, ctx: ctx, frame: frame)
            return
        }
        let pose = world.pose(of: c)
        let h = world.spriteHeight(c), w = world.spriteWidth(c)
        let mix = min(1, max(0, (c.depth - 0.36) / 0.3))
        let facing = c.turn
        let anchor = sp.isGroundBound ? CGPoint(x: c.pos.x, y: c.pos.y + c.lift + pose.lift) : CGPoint(x: c.pos.x, y: c.pos.y + pose.lift)
        if sp.hangs {
            // The thread it hangs by, from the top of the picture.
            ctx.setStrokeColor(CGColor(gray: 0.85, alpha: 0.65))
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: anchor.x, y: world.size.height + 4))
            ctx.addLine(to: CGPoint(x: anchor.x, y: anchor.y + CGFloat(h * 0.3)))
            ctx.strokePath()
        }
        if let glow = sprites.glows[c.species] {
            // A lantern's pulse of light round it.
            let level = min(3, max(0, Int(((0.5 + 0.5 * sin(frame.time * 3.2 + c.quirk * 7)) * 3.99))))
            let image = glow[level]
            let middle = sp.isGroundBound ? anchor.y + CGFloat(h * 0.45) : anchor.y
            ctx.draw(image, in: CGRect(x: (anchor.x - CGFloat(image.width) / 2).rounded(), y: (middle - CGFloat(image.height) / 2).rounded(), width: CGFloat(image.width), height: CGFloat(image.height)))
        }

        // The usual case, an animal walking or standing in its lane: the sprite made for that lane is copied onto the picture as it is,
        // which is many times cheaper than any scaling or turning.
        if !sp.painted, sp.group == 1, let art = sprites.baked[c.species], abs(facing) > 0.92, mix < 0.02 || mix > 0.98,
           abs(pose.stretch - 1) < 0.018, abs(pose.squash - 1) < 0.018, abs(pose.tilt) < 0.004 {
            let image = art.image(near: mix > 0.5, flipped: (facing > 0) != sp.facesRight)
            let iw = Double(image.width), ih = Double(image.height)
            if abs(w / iw - 1) < 0.06, abs(h / ih - 1) < 0.06 {
                let x = (anchor.x + CGFloat(c.dir * pose.shift) - CGFloat(iw / 2)).rounded()
                let y = (sp.isGroundBound ? anchor.y : anchor.y - CGFloat(ih / 2)).rounded()
                ctx.draw(image, in: CGRect(x: x, y: y, width: CGFloat(iw), height: CGFloat(ih)))
                return
            }
        }

        ctx.saveGState()
        ctx.translateBy(x: anchor.x + CGFloat(c.dir * pose.shift), y: anchor.y)
        // Tip about the back feet for walkers, about the middle for everything else.
        if pose.tilt != 0 {
            let pivot = sp.isGroundBound ? CGPoint(x: -facing * w * 0.3, y: 0) : .zero
            ctx.translateBy(x: pivot.x, y: pivot.y)
            ctx.rotate(by: CGFloat(pose.tilt * facing))
            ctx.translateBy(x: -pivot.x, y: -pivot.y)
        }
        if sp.painted {
            ctx.scaleBy(x: CGFloat(facing * pose.squash), y: CGFloat(pose.stretch))
            painter(ctx, c, sp, pose, CGSize(width: w, height: h), mix, frame)
        } else if let art = sprites.baked[c.species] {
            let flip = facing * (sp.facesRight ? 1 : -1)
            ctx.scaleBy(x: CGFloat(flip * pose.squash), y: CGFloat(pose.stretch))
            let rect = sp.isGroundBound ? CGRect(x: -w / 2, y: 0, width: w, height: h) : CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
            if sp.group > 1 {
                drawSchool(art, rect: rect, count: sp.group, c: c, mix: mix, world: world, ctx: ctx, facing: facing)
            } else {
                if mix < 0.98 { ctx.draw(art.far, in: rect) }
                if mix > 0.02 { ctx.setAlpha(CGFloat(mix)); ctx.draw(art.near, in: rect) }
            }
        }
        ctx.restoreGState()
    }

    /// Forgets what the creatures were doing, for a fresh world.
    func forget() {
        memory.slots.removeAll()
        memory.held.removeAll()
        memory.lastTime = -1
    }

    /// The room a hand-drawn creature's picture has about its anchor, in its units: its own box and a margin for tails, trunks and
    /// wings, and more headroom for a snake that rears.
    static func room(for sp: SceneSpecies) -> CGRect {
        let half = sp.aspect * 0.5 + 0.75
        if sp.isGroundBound { return CGRect(x: -half, y: -0.25, width: half * 2, height: sp.act == .rear ? 2.15 : 1.75) }
        return CGRect(x: -half, y: -1.05, width: half * 2, height: 2.1)
    }

    /// A hand-drawn creature: its rig is posed from what it is doing and painted as vector shapes, in its own units.
    private func drawPuppet(_ puppet: ScenePuppet, _ c: SceneCreature, _ sp: SceneSpecies, world: SceneWorld, ctx: CGContext, frame: SceneFrame) {
        var remembered = memory.slots[c.id] ?? SceneRigMemory()
        var actor = world.actor(of: c, memory: &remembered)
        memory.slots[c.id] = remembered
        let pose = actor.pose
        let unit = world.spriteHeight(c)
        let mix = min(1, max(0, (c.depth - 0.36) / 0.3))
        // Turning round squeezes it thin and out the other side, but never to a sliver; things that face you just turn.
        var facing = c.turn
        if puppet.facesViewer { facing = c.dir >= 0 ? 1 : -1 } else if abs(facing) < 0.3 { facing = facing < 0 ? -0.3 : 0.3 }
        let lift = sp.isGroundBound ? c.lift + (sp.gait == .walk ? 0 : pose.lift) : pose.lift
        let anchor = CGPoint(x: c.pos.x + c.dir * pose.shift, y: c.pos.y + lift)
        if sp.hangs {
            ctx.setStrokeColor(CGColor(gray: 0.88, alpha: 0.6))
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: anchor.x, y: world.size.height + 4))
            ctx.addLine(to: CGPoint(x: anchor.x, y: anchor.y + CGFloat(unit * 0.3)))
            ctx.strokePath()
        }
        if let glow = sprites.glows[c.species] {
            let level = min(3, max(0, Int(((0.5 + 0.5 * sin(frame.time * 3.2 + c.quirk * 7)) * 3.99))))
            let image = glow[level]
            let middle = sp.isGroundBound ? anchor.y + CGFloat(unit * 0.45) : anchor.y
            ctx.draw(image, in: CGRect(x: (anchor.x - CGFloat(image.width) / 2).rounded(), y: (middle - CGFloat(image.height) / 2).rounded(),
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        func place(_ ctx: CGContext, _ at: CGPoint, scale: Double, _ a: SceneActor) {
            ctx.saveGState()
            ctx.translateBy(x: at.x, y: at.y)
            if !(sp.isGroundBound && sp.gait == .walk), pose.tilt != 0 { ctx.rotate(by: CGFloat(pose.tilt * facing)) }
            if sp.gait == .hop { ctx.scaleBy(x: CGFloat(pose.squash), y: CGFloat(pose.stretch)) }
            ctx.scaleBy(x: CGFloat(facing * unit * scale), y: CGFloat(unit * scale))
            ink.begin(ctx, far: 1 - mix)
            puppet.draw(ctx, a, ink)
            ctx.restoreGState()
        }
        // What the drawing may cover, in pixels about the anchor.
        let room = Self.room(for: sp)
        var extent = CGRect(x: room.minX * unit, y: room.minY * unit, width: room.width * unit, height: room.height * unit)
        if sp.group > 1 {
            extent = extent.insetBy(dx: -world.width(c) * 1.4 - 12, dy: -world.height(c) * 1.4 - 12)
        }
        let held = memory.held[c.id] ?? SceneHeldFrame()
        memory.held[c.id] = held
        // Busy animals near you are drawn on twos, those walking about on threes, those standing still on fours; never all on the
        // same frame.
        let busy = c.phase == .acting || c.phase == .noticing || c.phase == .approaching || c.phase == .fleeing || c.phase == .backingOff
        let every = busy ? 2 : (actor.walk > 0.1 || !sp.isGroundBound ? 3 : 4)
        let due = (memory.frame + c.id) % every == 0
        let key = Int(c.lift > 0.5 ? 1 : 0) + (actor.landed ? 2 : 0)
        if !due, held.fresh(frame: memory.frame, every: every + 1, unit: unit, facing: facing, phase: c.phase, key: key) {
            held.stamp(ctx, at: anchor)
            return
        }
        held.redraw(extent: extent, anchor: anchor, frame: memory.frame, unit: unit, facing: facing, phase: c.phase, key: key) { cache in
            guard sp.group > 1 else {
                place(cache, .zero, scale: 1, actor)
                return
            }
            // A school: one creature drawn as a shoal that swims together, bunching and spreading, and bursting apart when scared.
            let scatter = c.phase == .fleeing ? min(2.6, 1 + c.phaseTime * 2.5) : 1
            let spreadX = world.width(c) * 0.5 * scatter, spreadY = world.height(c) * 0.5 * scatter
            let t = world.time
            for i in 0..<sp.group {
                let a = Double(i) * 2.399 + c.quirk * 6
                let ring = 0.3 + 0.7 * sqrt(Double(i) / Double(sp.group))
                let breathe = 1 + 0.12 * sin(t * 0.8 + c.quirk * 5)
                let dx = cos(a + t * 0.25) * spreadX * ring * breathe + sin(t * 1.3 + Double(i) * 1.7) * 7
                let dy = sin(a + t * 0.2) * spreadY * ring * breathe + cos(t * 1.1 + Double(i)) * 5
                let scale = 0.72 + 0.28 * Double((i * 7) % 5) / 4
                var member = actor
                member.member = i
                member.quirk = (c.quirk + Double(i) * 0.371).truncatingRemainder(dividingBy: 1)
                member.stride += Double(i) * 1.3
                place(cache, CGPoint(x: dx, y: dy), scale: scale, member)
            }
        }
        held.stamp(ctx, at: anchor)
    }

    /// A school: one creature, drawn as a shoal that swims together, bunching and spreading.
    private func drawSchool(_ art: SceneSprites.Baked, rect: CGRect, count: Int, c: SceneCreature, mix: Double, world: SceneWorld, ctx: CGContext, facing: Double) {
        // Waving at them makes the school burst apart as it bolts.
        let scatter = c.phase == .fleeing ? min(2.6, 1 + c.phaseTime * 2.5) : 1
        let spreadX = world.width(c) * 0.5 * scatter, spreadY = world.height(c) * 0.5 * scatter
        let t = world.time
        // Each fish faces where the school is heading, mirrored back since the whole school is drawn flipped.
        for i in 0..<count {
            let a = Double(i) * 2.399 + c.quirk * 6
            let ring = 0.3 + 0.7 * sqrt(Double(i) / Double(count))
            let breathe = 1 + 0.12 * sin(t * 0.8 + c.quirk * 5)
            let dx = (cos(a + t * 0.25) * spreadX * ring * breathe + sin(t * 1.3 + Double(i) * 1.7) * 7) * (facing < 0 ? -1 : 1)
            let dy = sin(a + t * 0.2) * spreadY * ring * breathe + cos(t * 1.1 + Double(i)) * 5
            let scale = 0.72 + 0.28 * Double((i * 7) % 5) / 4
            let r = CGRect(x: rect.midX + dx - rect.width * scale / 2, y: rect.midY + dy - rect.height * scale / 2, width: rect.width * scale, height: rect.height * scale)
            ctx.draw(mix > 0.5 ? art.near : art.far, in: r)
        }
    }

    // MARK: Effects and speech

    func drawEffects(_ world: SceneWorld, front: Bool, in ctx: CGContext) {
        let look = sprites.look
        let system = front ? world.effects : world.effectsBehind
        let (dr, dg, db) = Self.components(look.dust)
        let (wr, wg, wb) = Self.components(look.water)
        for p in system.particles {
            let k = p.progress
            switch p.kind {
            case SceneWorld.dropKind:
                ctx.setFillColor(CGColor(red: wr, green: wg, blue: wb, alpha: 0.92 * (1 - k * k * k)))
                ctx.fillEllipse(in: CGRect(x: p.position.x - p.size * 0.5, y: p.position.y - p.size * 0.5, width: p.size, height: p.size * 1.25))
                ctx.setFillColor(CGColor(gray: 1, alpha: 0.9 * (1 - k)))
                ctx.fillEllipse(in: CGRect(x: p.position.x - p.size * 0.28, y: p.position.y + p.size * 0.05, width: p.size * 0.3, height: p.size * 0.3))
            case SceneWorld.bubbleKind:
                let r = p.size * 0.5 * (0.7 + 0.3 * k)
                ctx.setStrokeColor(CGColor(red: wr, green: wg, blue: wb, alpha: 0.65 * (1 - k)))
                ctx.setLineWidth(1.6)
                ctx.strokeEllipse(in: CGRect(x: p.position.x - r, y: p.position.y - r, width: r * 2, height: r * 2))
                ctx.setFillColor(CGColor(gray: 1, alpha: 0.5 * (1 - k)))
                ctx.fillEllipse(in: CGRect(x: p.position.x - r * 0.55, y: p.position.y + r * 0.1, width: r * 0.4, height: r * 0.4))
            default:
                // A puff: two ellipses, the inner one denser.
                let r = p.size * (0.7 + 1.0 * k), fade = pow(1 - k, 1.4)
                ctx.setFillColor(CGColor(red: dr, green: dg, blue: db, alpha: 0.16 * fade))
                ctx.fillEllipse(in: CGRect(x: p.position.x - r, y: p.position.y - r * 0.85, width: r * 2, height: r * 1.7))
                ctx.setFillColor(CGColor(red: dr, green: dg, blue: db, alpha: 0.24 * fade))
                ctx.fillEllipse(in: CGRect(x: p.position.x - r * 0.55, y: p.position.y - r * 0.5, width: r * 1.1, height: r))
            }
        }
    }

    /// Speech bubbles pop in over the animals' heads. They keep off the person's face.
    func drawBubbles(_ world: SceneWorld, in ctx: CGContext) {
        let size = world.size
        var placed: [CGRect] = []
        for c in world.creatures where c.phase != .away {
            guard let bubble = c.bubble, let image = SceneBubbleArt.image(bubble.text) else { continue }
            let sp = world.cast.species[c.species]
            let pose = world.pose(of: c)
            let k = min(1, bubble.age / 0.18)
            let pop = 1 + 0.35 * sin(k * .pi) * (1 - k) - (1 - k) * 0.6
            let fade = min(1, (bubble.life - bubble.age) / 0.25)
            let scale = (0.7 + 0.3 * world.layout.scale(c.depth)) * max(0.05, pop)
            let w = Double(image.width) * scale, h = Double(image.height) * scale
            let top = sp.isGroundBound ? c.pos.y + c.lift + pose.lift + world.height(c) * pose.stretch : c.pos.y + world.height(c) / 2
            var x = c.pos.x + c.dir * world.width(c) * 0.12
            var y = top + 4
            x = min(max(x, w / 2 + 6), size.width - w / 2 - 6)
            if y > size.height - h - 6 {
                // No room above its head: the bubble goes beside it, at the height of its head.
                y = size.height - h - 6
                let body = world.bounds(of: c)
                if CGRect(x: x - w / 2, y: y, width: w, height: h).intersects(body) {
                    let right = Double(body.maxX) + w / 2 + 8, left = Double(body.minX) - w / 2 - 8
                    x = right + w / 2 < size.width ? right : left
                }
            }
            if let person = world.person {
                let zone = person.faceZone.insetBy(dx: -6, dy: -6)
                var rect = CGRect(x: x - w / 2, y: y, width: w, height: h)
                if rect.intersects(zone) {
                    // Slide out sideways, to whichever side is nearer.
                    x = abs(x - zone.minX) < abs(x - zone.maxX) ? zone.minX - w / 2 : zone.maxX + w / 2
                    x = min(max(x, w / 2 + 6), size.width - w / 2 - 6)
                    rect = CGRect(x: x - w / 2, y: y, width: w, height: h)
                    if rect.intersects(zone) { y = zone.maxY + 4 }
                }
            }
            // Two animals talking at once: the second bubble goes above the first.
            while let hit = placed.first(where: { $0.intersects(CGRect(x: x - w / 2, y: y, width: w, height: h)) }), y < size.height - h - 6 {
                y = min(size.height - h - 6, Double(hit.maxY) + 4)
            }
            placed.append(CGRect(x: x - w / 2, y: y, width: w, height: h))
            let wobble = bubble.text.hasSuffix("!") ? sin(bubble.age * 38) * 0.035 : 0
            ctx.saveGState()
            ctx.translateBy(x: x, y: y)
            ctx.rotate(by: CGFloat(wobble))
            ctx.setAlpha(CGFloat(max(0, fade)))
            ctx.draw(image, in: CGRect(x: -w / 2, y: 0, width: w, height: h))
            ctx.restoreGState()
        }
        ctx.setAlpha(1)
    }

    private static func components(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 255) / 255, Double((hex >> 8) & 255) / 255, Double(hex & 255) / 255)
    }
}
