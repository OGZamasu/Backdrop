import CoreGraphics
import CoreImage
import Foundation
import simd

/// The body half of the Dragon Ball lens, as light: the aura behind the person and the light over them.
///
/// Behind: the flame, worked out the way `AuraLens` does it (the cutout shrunk to a quarter, grown, softened, pushed about by climbing
/// noise and smeared upward into tongues) and coloured at full size through the form's ramp, so its bands have clean edges; the room
/// dimmed under the flame's body so its colour still reads on a bright wall; light rays and a refracting ring when the form changes; embers rising off the
/// head and shoulders; and while powering up, light rushing upward, ripples along the floor and debris lifting off it. Over the person:
/// light wrapping their edges, lightning crawling along and jumping off the outline, the shockwave rings and the burst of a change.
///
/// Every form's look comes from `SaiyanForm` (style, size, lightning, palette) and blends into the next over `transition`; while a
/// power-up charges, the next form leans in. Base draws nothing and costs nothing. With no cutout there is nothing to glow round, so
/// nothing is drawn. Two overlay layers: one behind (embers), one over (lightning and rings).
final class SaiyanAura {
    private let embers = SaiyanEmbers()
    private let lightning = SaiyanLightning()
    private var person = WorldPresence()
    private var outline = SaiyanOutline()
    private var unit = 1.0
    private var lastTime: Double?
    private var frame = 0
    /// The blend worked out by `backLayer`, used again by `frontLight` in the same frame.
    private var mix = SaiyanAuraMix()
    private var mixTime = -1.0
    /// The change the burst was last fired for, so it fires once per change.
    private var burstFor = -1.0
    private var rays: [(angle: Double, length: Double, width: Double)] = []
    /// The embers' colours, kept from the last frame that had an aura, so the ones still in the air when it has gone keep theirs.
    private var emberColours = SaiyanEmbers.Colours(core: SIMD3(1, 1, 1), mid: SIMD3(1, 1, 1), rim: SIMD3(1, 1, 1), charge: SIMD3(1, 1, 1))
    /// Leftover embers fade out over a third of a second once the aura has gone, rather than drifting on alone.
    private var emberFade = HandFXLevel(rise: 0.1, fall: 0.12, value: 1)

    init() {}

    func reset() {
        embers.reset()
        lightning.reset()
        person.reset()
        outline = SaiyanOutline()
        lastTime = nil
        burstFor = -1
        rays = []
    }

    // MARK: For tests

    var emberCount: Int { embers.count }
    var boltCount: Int { lightning.bolts.count }
    var rockCount: Int { embers.rocks.count }
    var lastOutline: SaiyanOutline { outline }
    /// The embers' average velocity, in pixels a second: they should be rising.
    var emberDrift: SIMD2<Double> {
        let all = embers.sparks.particles
        return all.isEmpty ? .zero : all.reduce(SIMD2<Double>(0, 0)) { $0 + $1.velocity } / Double(all.count)
    }

    // MARK: Frame

    /// Whether there is anything at all to draw or move: base, settled, nothing left in the air.
    private func isIdle(_ state: SaiyanBodyState) -> Bool {
        let quiet = state.form.isBase && (state.previousForm.isBase || state.transition >= 1) && state.charge <= 0.001 && state.flash <= 0.004
        return quiet && embers.isIdle && lightning.isIdle
    }

    /// The scenery with the aura's glow, embers and anything else that sits behind the person added. Does not include the person: the
    /// lens lays them over this with `input.placingPerson(over:)`.
    func backLayer(_ input: LensInput, _ state: SaiyanBodyState) -> CIImage {
        guard let matte = input.matte, !isIdle(state) else { return input.scenery }
        advance(input, state)
        let rect = input.rect
        let m = mix
        let presence = min(1, max(0, state.presence))
        let shown = m.amount * presence

        var room = input.scenery
        // A change bends the room behind you as its first ring passes, like a lens.
        if m.rising, state.sinceChange < 0.7, presence > 0.05 {
            let k = state.sinceChange / 0.7
            room = room.clampedToExtent().applyingFilter("CITorusLensDistortion", parameters: [
                kCIInputCenterKey: CIVector(cgPoint: burstCentre(input)),
                kCIInputRadiusKey: ringRadius(k, rect: rect),
                kCIInputWidthKey: (60 + 90 * k) * unit,
                "inputRefraction": 1.5 * pow(1 - k, 1.4) * presence,
            ]).cropped(to: rect)
        }

        var picture = room
        if shown > 0.003, let ramp = SaiyanAuraRamp.ramp(m.weights) {
            let l = m.look
            let t = state.time
            // A slow flicker, and for the electric forms a hard random strobe a dozen times a second.
            let strobeBucket = Int(t * 12)
            let strobe = l.strobe * (WorldKit.hash(strobeBucket) - 0.5) * 2
            let flick = 1 + l.flicker * (0.6 * sin(t * l.flickerRate * 2 * .pi / 3) + 0.4 * sin(t * l.flickerRate * 1.53 + 1)) + strobe
            let field = SaiyanAuraField.strength(matte: matte, rect: rect, look: l, unit: unit, swell: m.swell, time: t)
            var full = SaiyanAuraField.enlarge(field, rect: rect)
            // Fading, the flame shrinks into its body and rim colours (the white core goes first) rather than dimming its pale core to grey,
            // and it breathes with the flicker.
            full = SaiyanAuraKit.scaled(full, pow(shown, 1.6) * flick * (1 + 0.2 * state.charge))
            var light = full.applyingFilter("CIColorMap", parameters: ["inputGradientImage": ramp])
            let boost = m.rising ? 0.5 * state.flash * state.flash : 0
            light = SaiyanAuraKit.gained(light, shown.squareRoot() * (0.9 + 0.15 * state.level) * (1 + boost)).cropped(to: rect)
            if l.veil > 0.01 {
                picture = WorldKit.multiply(SaiyanAuraKit.veil(full, l.veil * shown, reach: 1.8).cropped(to: rect), picture).cropped(to: rect)
            }
            picture = WorldKit.adding(light, to: picture)
            if l.pulse > 0.01 {
                // Blue Kaioken's beat: a red swell on the rim of the glow.
                let beat = SaiyanAuraKit.heartbeat(t) * l.pulse * shown
                if beat > 0.01 {
                    let halo = SaiyanAuraField.enlarge(WorldKit.halo(matte: matte, rect: rect, sigma: 46 * unit, grow: 20 * unit * m.swell), rect: rect)
                    picture = WorldKit.adding(WorldKit.tint(halo, m.rim, strength: 0.55 * beat).cropped(to: rect), to: picture)
                }
            }
        }

        picture = embers.compositeRocks(over: picture, presence: presence, rect: rect)
        let colours = emberColours
        let raysOn = m.rising && state.sinceChange < 0.9 && !rays.isEmpty
        if !embers.isIdle || raysOn,
           let layer = input.services.overlay({ ctx in
               if raysOn { drawRays(in: ctx, input: input, state: state, colour: m.mid, core: m.core) }
               embers.drawLight(in: ctx, outline: outline, colours: colours, charge: state.charge, presence: presence * emberFade.value, rect: rect)
           }) {
            picture = HandFXLight.add(layer, to: picture, rect: rect, bloom: 0.6)
        }
        return picture.cropped(to: rect)
    }

    /// A layer of light to add over the person: wrap light on their edges, lightning across the body, the flash and shockwave of a power-up.
    /// Nil when there is nothing to add.
    func frontLight(_ input: LensInput, _ state: SaiyanBodyState) -> CIImage? {
        guard let matte = input.matte, !isIdle(state) else { return nil }
        if mixTime != state.time { _ = advance(input, state) }
        let rect = input.rect
        let m = mix
        let presence = min(1, max(0, state.presence))
        let shown = m.amount * presence
        var parts: [CIImage] = []

        // Light wrapping round your edges; for Blue Kaioken it turns red on the beat.
        if shown > 0.01 {
            var colour = m.mid, strength = m.look.wrap * shown * (1 + 0.4 * state.charge)
            if m.look.pulse > 0.01 {
                let beat = SaiyanAuraKit.heartbeat(state.time) * m.look.pulse
                colour = SaiyanAuraKit.mix(m.mid, m.rim, 0.35 + 0.5 * beat)
                strength *= 1 + 0.6 * beat
            }
            if let edge = WorldKit.edgeGlow(matte: matte, rect: rect, width: 30 * unit, colour: colour, strength: strength) { parts.append(edge) }
        }

        // The burst of a change: a soft white-gold bloom from the chest, under the rings.
        if m.rising, state.flash > 0.01 {
            let c = burstCentre(input)
            let f = state.flash * state.flash * presence
            let tint = SaiyanAuraKit.mix(m.core, m.mid, 0.3)
            parts.append(WorldKit.wash(center: c, radius: Double(outline.width) * 0.55, red: tint.x, green: tint.y, blue: tint.z, alpha: 0.75 * f, in: rect))
        }

        let rings = (m.rising && state.sinceChange < 1.0) || (m.collapsing && state.sinceChange < 0.6)
        if (rings || !lightning.isIdle) && presence > 0.01,
           let layer = input.services.overlay({ ctx in
               if rings { drawRings(in: ctx, input: input, state: state) }
               lightning.draw(in: ctx, outline: outline, colour: m.lightningColour, strength: presence * min(1, 1.5 * max(m.amount, state.charge)), avoid: input.face?.rect)
           }) {
            parts.append(layer)
            parts.append(HandFXLight.bloom(of: layer, rect: rect, gain: 0.85))
        }
        guard !parts.isEmpty else { return nil }
        return WorldKit.sum(parts, rect: rect)
    }

    /// What the body does to the whole picture: the shake of a power-up, the white flash of a change. The lens merges it with the moves'.
    func screenEffect(_ state: SaiyanBodyState) -> SaiyanScreenEffect {
        var e = SaiyanScreenEffect()
        let p = min(1, max(0, state.presence))
        guard p > 0.01 else { return e }
        let f = min(1, max(0, state.flash))
        if f > 0.002 {
            if state.form > state.previousForm {
                // White-gold, leaning toward the new form's colour.
                e.flash = 0.6 * pow(f, 1.6) * p
                e.flashTint = SaiyanAuraKit.mix(SIMD3(1, 0.94, 0.76), state.form.palette.auraMid, 0.4)
                e.shake = 0.32 * pow(f, 1.2) * p
            } else {
                e.flash = 0.35 * pow(f, 1.4) * p
                e.flashTint = state.previousForm.palette.auraCore
            }
        }
        // Trembling while a power-up charges, growing as it fills.
        let c = min(1, max(0, state.charge))
        if c > 0.01 { e.shake = max(e.shake, (0.025 + 0.11 * pow(c, 1.6)) * p) }
        return e
    }

    // MARK: Moving things on

    /// Moves everything on to `state.time` once a frame and works out this frame's blend and outline. Returns the step.
    @discardableResult
    private func advance(_ input: LensInput, _ state: SaiyanBodyState) -> Double {
        let dt = lastTime.map { min(1.0 / 15, max(0, state.time - $0)) } ?? WorldKit.clamped(input.dt)
        lastTime = state.time
        mixTime = state.time
        frame += 1
        mix = SaiyanAuraMix.of(state)
        if !mix.weights.isEmpty {
            emberColours = SaiyanEmbers.Colours(core: mix.core, mid: mix.mid, rim: mix.rim, charge: (state.form.next ?? state.form).palette.auraMid)
        }
        emberFade.approach(mix.amount > 0.05 ? 1 : 0, dt: dt)
        person.update(grid: input.matteGrid, dt: dt)
        // The aura's size follows the face (eyes 84 px apart is 1), or the silhouette's width when there is no face; eased, so a face
        // dropping out does not make it jump.
        let wanted = input.face.map { $0.interocular / 84 } ?? Double(person.width) / 560
        unit += (min(1.6, max(0.35, wanted)) - unit) * (1 - exp(-dt / 0.3))
        if let grid = input.matteGrid {
            // Every other frame is plenty: a person does not move far in a fifteenth of a second, and the lightning re-forks at that rate.
            if frame % 2 == 1 || outline.isEmpty {
                outline = SaiyanOutline.read(grid, presence: person, unit: unit, rect: input.rect)
            } else {
                outline.unit = unit
            }
        } else {
            outline = SaiyanOutline()
            outline.unit = unit
            if let face = input.face { outline.centre = face.eyeCenter; outline.width = face.interocular * 5 }
        }
        let presence = min(1, max(0, state.presence))
        let rate = mix.embers * mix.amount * presence
        embers.step(dt: dt, outline: outline, rate: rate, look: mix.look, charge: state.charge * presence, rect: input.rect)
        lightning.step(dt: dt, amount: mix.lightning * max(mix.amount, state.charge) * presence, heavy: max(0, mix.lightning - 0.7) / 0.3,
                       outline: outline)
        // Once per change upward: a burst of embers and a fresh set of light rays.
        if mix.rising, state.sinceChange < 0.2, abs(burstFor - (state.time - state.sinceChange)) > 0.05 {
            burstFor = state.time - state.sinceChange
            embers.burst(outline: outline, count: Int(50 + 50 * state.form.power))
            var r = SplitMix64(seed: UInt64(truncatingIfNeeded: Int(burstFor * 1000)) &+ 0xBEEF)
            rays = (0..<11).map { i in
                (angle: Double(i) / 11 * 2 * .pi + Double.random(in: -0.2...0.2, using: &r), length: Double.random(in: 0.9...1.6, using: &r),
                 width: Double.random(in: 0.6...1.2, using: &r))
            }
        }
        return dt
    }

    // MARK: Drawing

    /// Where a change bursts from: the chest, between the face and the middle of the silhouette.
    private func burstCentre(_ input: LensInput) -> CGPoint {
        if let face = input.face {
            return CGPoint(x: (face.mouth.x + outline.centre.x) / 2, y: (face.mouth.y + outline.centre.y) / 2)
        }
        return outline.centre
    }

    /// The shockwave's radius as it runs out, `k` from 0 to 1: fast at first, slowing, reaching past the corners.
    private func ringRadius(_ k: Double, rect: CGRect) -> Double {
        let start = Double(outline.width) * 0.25, end = Double(hypot(rect.width, rect.height)) * 0.75
        return start + (end - start) * HandFXKit.easeOutCubic(k)
    }

    /// The shockwave rings of a change, or the one ring drawing in on the way down.
    private func drawRings(in ctx: CGContext, input: LensInput, state: SaiyanBodyState) {
        let m = mix
        let centre = burstCentre(input)
        let p = min(1, max(0, state.presence))
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        let white = HandFXPalette.white
        func ring(radius r: Double, alpha a: Double, thickness: Double, colour: SIMD3<Double>) {
            guard a > 0.004, r > 2 else { return }
            let box = CGRect(x: Double(centre.x) - r, y: Double(centre.y) - r * 0.9, width: r * 2, height: r * 1.8)
            for (w, c, k) in [(thickness * 3.2, colour, 0.14), (thickness * 1.3, SaiyanAuraKit.mix(colour, white, 0.45), 0.42), (max(1.5, thickness * 0.4), white, 0.85)] {
                ctx.setLineWidth(max(1, w))
                ctx.setStrokeColor(HandFXKit.cgColor(c, a * k))
                ctx.strokeEllipse(in: box)
            }
        }
        if m.rising {
            // Three rings, each a beat behind the last, thinning and fading as they run out.
            for (i, delay) in [0.0, 0.1, 0.22].enumerated() {
                let s = state.sinceChange - delay
                guard s > 0, s < 0.8 else { continue }
                let k = s / 0.8
                let alpha = pow(1 - k, 1.4) * WorldKit.smoothstep(0, 0.05, s) * (i == 0 ? 1 : 0.65) * p
                ring(radius: ringRadius(k, rect: input.rect), alpha: alpha, thickness: (8 - 4 * k) * unit, colour: i == 1 ? m.core : m.mid)
            }
        } else if m.collapsing {
            // Calming down: one soft ring drawing in to the body.
            let k = min(1, state.sinceChange / 0.6)
            let r = Double(outline.width) * (1.1 - 0.75 * HandFXKit.easeOutCubic(k))
            ring(radius: r, alpha: sin(k * .pi) * 0.6 * p, thickness: 5 * unit, colour: m.mid)
        }
        ctx.restoreGState()
    }

    /// Light rays fanning out from behind the person as they change: soft shafts that widen and fade as they go, longest at the start,
    /// fading as the flash does.
    private func drawRays(in ctx: CGContext, input: LensInput, state: SaiyanBodyState, colour: SIMD3<Double>, core: SIMD3<Double>) {
        let s = state.sinceChange
        let alpha = WorldKit.smoothstep(0, 0.06, s) * (1 - WorldKit.smoothstep(0.15, 0.85, s)) * min(1, max(0, state.presence))
        let tint = SaiyanAuraKit.mix(colour, core, 0.35)
        guard alpha > 0.01, let shaft = Self.shaft(tint) else { return }
        let c = burstCentre(input)
        let reach = Double(hypot(input.rect.width, input.rect.height)) * 0.42
        let grow = HandFXKit.easeOutCubic(min(1, s / 0.3))
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.interpolationQuality = .low
        for ray in rays {
            let length = reach * ray.length * (0.35 + 0.65 * grow)
            let width = length * 0.26 * ray.width
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y)
            ctx.rotate(by: CGFloat(ray.angle + s * 0.12))
            ctx.setAlpha(CGFloat(alpha * 0.8))
            ctx.draw(shaft, in: CGRect(x: 0, y: -width / 2, width: length, height: width))
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    /// A shaft of light, from its root on the left to its end on the right: a white-hot thread down the middle of a coloured wedge that
    /// widens and fades as it goes, with soft edges all round. Made once per colour.
    private static func shaft(_ c: SIMD3<Double>) -> CGImage? {
        let q = { (v: Double) in Int((min(1, max(0, v)) * 12).rounded()) }
        return HandFXSprites.named("saiyan-shaft-\(q(c.x))-\(q(c.y))-\(q(c.z))") {
            HandFXKit.sprite(width: 128, height: 48) { u, v in
                let half = 0.2 + 0.8 * u
                let across = abs(v - 0.5) * 2 / half
                let along = WorldKit.smoothstep(0, 0.15, u) * pow(1 - u, 1.2)
                let body = exp(-3.2 * across * across) * along, thread = exp(-60 * across * across) * along * (1 - u)
                let sum = c * body * 0.8 + SIMD3(1, 1, 1) * thread
                let a = min(1, max(sum.x, max(sum.y, sum.z)))
                return a < 1e-4 ? (0, 0, 0, 0) : (sum.x / a, sum.y / a, sum.z / a, a)
            }
        }
    }
}
