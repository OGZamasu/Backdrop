import CoreGraphics
import CoreImage

/// Dragon Ball: hold both fists up to power up through the Super Saiyan forms, then fire moves from the show with your hands.
///
/// The lens only joins the pieces. `SaiyanTransformation` reads both fists and decides the form; `SaiyanFace` paints the hair, brows and
/// eyes of that form; `SaiyanAura` lights the room behind you and the light over you; `SaiyanMoveSet` runs ten moves, one at a time, whose
/// size and colour follow the form. `SaiyanCompose` says how they are laid together.
final class SaiyanLens: Lens {
    /// How long the hair and aura take to fade away once the face is lost, and to come back after a blip.
    static let fadeOut = 0.3, fadeIn = 0.15

    let needs: LensNeeds = [.face, .matte, .hands]
    var wantsMatteGrid: Bool { true }
    var status: LensStatus? { statusBox.value }

    private let rig = HeadwearRig()
    private let faceArt = SaiyanFace()
    private let aura = SaiyanAura()
    private let transformation = SaiyanTransformation()
    private let moves = SaiyanMoveSet()
    private var recognizer = HandGestureRecognizer()
    private var hint = HandFXHint()
    private var person = WorldPresence()
    private let statusBox = StatusBox()
    private var clock = 0.0
    private var lastFrame: HeadwearFrame?
    private var facePresence = 0.0
    /// The last time the person's skin colour was read from the camera, on the lens clock.
    private var lastSkinRead = -9.0
    /// Layers for the hair, the aura, the moves and the hint: more than the four every lens is given.
    private var services: LensServices?

    // MARK: For tests and the interface

    var form: SaiyanForm { transformation.form }
    var body: SaiyanBodyState { transformation.state }
    /// The name of the move being posed, charged or fired, if one is.
    var engagedMove: String? { moves.engaged?.name }
    var moveSet: SaiyanMoveSet { moves }
    var costume: SaiyanFace { faceArt }

    func restart() {
        rig.reset()
        faceArt.reset()
        aura.reset()
        transformation.reset()
        moves.reset()
        recognizer.reset()
        hint.reset()
        person = WorldPresence()
        lastFrame = nil
        facePresence = 0
        lastSkinRead = -9
    }

    // MARK: Frame

    func render(_ raw: LensInput) -> CIImage {
        let input = withOwnLayers(raw)
        let dt = min(0.1, max(0, raw.dt))
        clock += dt
        person.update(grid: input.matteGrid, dt: dt)

        // The hands: what they just did, then the form, then the moves.
        let events = recognizer.update(input.hands, dt: dt)
        transformation.update(hands: input.hands, gestures: recognizer, face: input.face, dt: dt, time: clock)
        let state = transformation.state
        let centre = input.face?.eyeCenter ?? (person.level > 0.3 ? CGPoint(x: person.centre.x, y: person.centre.y) : nil)
        moves.update(SaiyanMoveContext(hands: input.hands, gestures: recognizer, events: events, face: input.face, personCenter: centre,
                                       form: state.form, power: state.level, dt: dt, time: clock, rect: input.rect),
                     blocked: transformation.isClaiming)

        // The face: hair, brows and eyes, with the last good frame kept for a moment so they fade rather than vanish.
        let frame = faceFrame(input, dt: dt)
        faceArt.apply(state)
        if let frame { faceArt.advance(frame) }
        readSkin(input)

        let effect = SaiyanScreenEffect.merged([moves.screenEffect, aura.screenEffect(state)])
        let dressed = state.form != .base || state.previousForm != .base || state.charge > 0.001 || state.flash > 0.004
        var picture: CIImage
        if dressed || state.presence > 0.02 && !effect.isNone {
            picture = dress(input, state: state, frame: frame, effect: effect)
        } else {
            // Nothing is on: the picture as the camera and the backdrop made it, untouched.
            picture = effect.isNone ? input.composed : SaiyanCompose.person(input, over: input.scenery, effect: effect)
        }
        picture = SaiyanCompose.moves(moves, over: picture, input: input)
        picture = SaiyanCompose.screen(effect, over: picture, rect: input.rect, time: clock)

        hint.update(handsInView: !input.hands.isEmpty, dt: dt)
        picture = hint.compose(over: picture, services: input.services, rect: input.rect, accent: SIMD3(1.0, 0.82, 0.3))
        statusBox.value = currentStatus(input, state: state)
        return picture.cropped(to: input.rect)
    }

    /// The scenery with the aura, the person over it with their light, and the hair and face over that.
    private func dress(_ input: LensInput, state: SaiyanBodyState, frame: HeadwearFrame?, effect: SaiyanScreenEffect) -> CIImage {
        let alpha = HeadwearEase.smoothstep(facePresence)
        var back = aura.backLayer(input, state)
        // Super Saiyan 3's long hair falls behind the shoulders. Only then is there anything to lay behind the person (and with no cutout
        // the costume leaves it out, since it would cover them).
        if let frame, input.matte != nil, faceArt.drawsBehind,
           var hair = input.services.overlay({ ctx in faceArt.drawBack(HeadwearPen(ctx: ctx), frame, behindPerson: true) }) {
            hair = faceArt.washBack(hair)   // the colour wash of a charge or a flash, on the graphics chip
            back = (alpha < 0.999 ? hair.fading(alpha) : hair).composited(over: back)
        }
        var picture = SaiyanCompose.person(input, over: back, effect: effect)
        if let light = aura.frontLight(input, state) { picture = WorldKit.adding(light, to: picture) }
        guard let frame, alpha > 0.004, faceArt.isDrawing,
              var layer = input.services.overlay({ ctx in faceArt.draw(HeadwearPen(ctx: ctx), frame) }) else { return picture }
        // The hair is the heaviest part of the face to paint, so the costume hands it over as a picture for the graphics chip to lay.
        if let hair = faceArt.hairImage(frame) { layer = hair.composited(over: layer) }
        return (alpha < 0.999 ? layer.fading(alpha) : layer).composited(over: picture).cropped(to: input.rect)
    }

    /// This frame's face for the costume, or the last good one while it fades out.
    private func faceFrame(_ input: LensInput, dt: Double) -> HeadwearFrame? {
        if let now = rig.update(input.face, dt: dt, bounds: input.rect) {
            facePresence = now.seen <= dt + 1e-9 ? 1 : min(1, facePresence + dt / Self.fadeIn)
            lastFrame = now
            return now
        }
        facePresence = max(0, facePresence - dt / Self.fadeOut)
        if rig.hasForgotten { faceArt.reset() }
        guard let held = lastFrame, facePresence > 0.01 else { lastFrame = nil; facePresence = 0; return nil }
        return held
    }

    /// The person's skin colour, from a patch of cheek below the left eye, read now and then: the hair of Super Saiyan 3 bares the brows with it.
    private func readSkin(_ input: LensInput) {
        guard let face = input.face, clock - lastSkinRead > 0.7, faceArt.body.form == .superSaiyan3 || faceArt.body.previousForm == .superSaiyan3
                || faceArt.body.charge > 0 else { return }
        lastSkinRead = clock
        let io = max(face.interocular, 1)
        let up = face.up, across = face.across
        let c = CGPoint(x: face.leftEye.x - up.dx * io * 0.5 - across.dx * io * 0.05, y: face.leftEye.y - up.dy * io * 0.5 - across.dy * io * 0.05)
        let patch = CGRect(x: c.x - io * 0.12, y: c.y - io * 0.1, width: io * 0.24, height: io * 0.2).intersection(input.rect)
        guard patch.width >= 2, patch.height >= 2 else { return }
        let mean = input.camera.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: patch)])
        var px = [Float](repeating: 0, count: 4)
        input.services.context.render(mean, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf,
                                      colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        guard px[3] > 0.5 else { return }
        faceArt.skin = SIMD3(Double(px[0]), Double(px[1]), Double(px[2]))
    }

    /// The same frame handed to the pieces with a set of layers big enough for all of them.
    private func withOwnLayers(_ raw: LensInput) -> LensInput {
        if services == nil || services?.size != raw.services.size {
            services = LensServices(context: raw.services.context, size: raw.services.size, overlays: 8)
        }
        guard let services else { return raw }
        return LensInput(time: raw.time, dt: raw.dt, rect: raw.rect, camera: raw.camera, matte: raw.matte, background: raw.background,
                         composed: raw.composed, matteGrid: raw.matteGrid, face: raw.face, services: services, hands: raw.hands)
    }

    // MARK: Words

    private func currentStatus(_ input: LensInput, state: SaiyanBodyState) -> LensStatus {
        if input.face == nil, state.form == .base { return LensStatus("Looking for your face…", detail: "Face the camera in good light") }
        if let move = moves.status { return move }
        if let power = transformation.status { return power }
        let moveList = moves.moves
        let tip = moveList.isEmpty ? nil : moveList[Int(clock / 5) % moveList.count]
        let detail = tip.map { "\($0.name): \($0.hint)" }
        if state.form == .base { return LensStatus("Hold both fists up to power up", detail: detail) }
        return LensStatus(state.form.title, detail: detail)
    }
}
