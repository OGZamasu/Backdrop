import CoreImage
import CoreImage.CIFilterBuiltins

/// Builds the picture for the Floating Panel and Presenter arrangements.
///
/// The floating panel is meant to look like a real screen in a room, not a rectangle pasted on, so it is built in layers, back
/// to front: the surround (the screen's own light in a dim room, your room blurred, or a backdrop), a glow of the screen's colours
/// spilling onto it, a two-part shadow (a tight contact shadow and a wide soft one), the panel itself with continuous corners and a
/// fine highlight along its rim, turned slightly in space, and a faint soft shadow of you falling on it. That stage then goes to
/// `Compositor.composite` as your background, so the light wrap on your edges and the colour match pick up the panel's light.
///
/// Everything that only depends on the panel's size and look (its mask, rim highlight and shadow, the label, the status cards) is
/// drawn once and kept until the size or look changes. Per frame only cheap GPU work remains: scaling the live screen into the
/// panel, one perspective warp, and blurs done on small copies.
final class StageComposer {
    let rect: CGRect
    private let context: CIContext

    /// Everything one frame needs.
    struct Inputs {
        var content: CIImage?
        var status: StageContentStatus = .live
        /// What kind of thing is being shown, so a card says "unplugged" for a camera and "closed" for a window.
        var kind: StageContentKind = .window
        var title: String?
        var layout: StageLayout
        var live = StageLive()
        /// The camera, fitted to the output.
        var camera: CIImage
        /// Your refined cutout on the output's pixels, or nil if there is none yet.
        var matte: CIImage?
        /// The library backdrop around the panel, already fitted, when the surround is a backdrop.
        var surround: CIImage?
        /// Your head's offset from the middle, -1...1 each way, y up.
        var head: CGPoint = .zero
        /// The middle of your cutout in output pixels, when known.
        var anchor: CGPoint?
        var dt: Double = 1.0 / 30
    }

    init(rect: CGRect = CGRect(origin: .zero, size: StageGeometry.picture), context: CIContext) {
        self.rect = rect
        self.context = context
    }

    // MARK: The content's shape

    /// The width over height the panel is drawn at. It eases toward the content's real shape, so a window being resized makes
    /// the panel change shape smoothly instead of jumping.
    private(set) var aspect = 16.0 / 10
    private var aspectKnown = false
    /// How many times the shape eased this session; for tests.
    private(set) var aspectChanges = 0

    func updateAspect(from content: CIImage?, dt: Double) {
        guard let content, content.extent.width > 2, content.extent.height > 2, content.extent.width.isFinite else { return }
        let real = StageGeometry.saneAspect(Double(content.extent.width / content.extent.height))
        if !aspectKnown {
            aspect = real
            aspectKnown = true
            return
        }
        guard abs(real - aspect) > 1e-4 else { aspect = real; return }
        aspectChanges += 1
        // About a fifth of a second to change shape: quick enough to follow a window being dragged, slow enough not to jump.
        aspect += (real - aspect) * (1 - exp(-max(0, dt) / 0.09))
    }

    // MARK: The whole picture

    /// What goes behind you: the stage with the floating panel, or the screen filling the picture for Presenter.
    func backdrop(_ f: Inputs) -> CIImage {
        updateAspect(from: f.content, dt: f.dt)
        rememberFrame(f)
        switch f.layout.arrangement {
        case .floatingPanel: return stage(f)
        case .presenter, .backdrop: return filled(f)
        }
    }

    /// You as Present put you in the picture.
    struct Placed {
        var composed: CIImage
        /// The camera and your cutout as they now sit, so a lens on top lines up with you.
        var camera: CIImage
        var matte: CIImage?
        /// What takes a point on the camera picture to where it now sits, or nil when you have not been moved. Your face and hands are
        /// read on the camera picture, so a lens is given them through this, or it would dress the place you used to be.
        var transform: CGAffineTransform?
        /// The picture behind you when that is more than the backdrop: a bubble's own room and ring. Nil when it is the backdrop.
        var backdrop: CIImage?
    }

    /// You over `backdrop`: your cutout, moved and scaled when the layout says so, or a camera bubble.
    func person(_ f: Inputs, over backdrop: CIImage, compositor: Compositor, params: CompositeParameters) -> Placed {
        let layout = f.layout
        if layout.showsBubble { return bubble(f, over: backdrop) }
        guard let matte = f.matte else { return Placed(composed: backdrop, camera: f.camera, matte: nil) }
        let frame = layout.presenter
        if StageGeometry.isIdentity(frame) {
            var base = backdrop
            if layout.arrangement == .presenter { base = dropShadow(of: matte, onto: base) }
            return Placed(composed: compositor.compositeSubject(f.camera, matte: matte, background: base, params: params), camera: f.camera, matte: matte)
        }
        let t = StageGeometry.presenterTransform(frame, in: rect.size)
        let movedCamera = f.camera.transformed(by: t)
        let movedMatte = feathered(matte).transformed(by: t).cropped(to: rect)
        var base = backdrop
        if layout.arrangement == .presenter { base = dropShadow(of: movedMatte, onto: base) }
        let composed = compositor.compositeSubject(movedCamera, matte: movedMatte, background: base, params: params)
        return Placed(composed: composed, camera: movedCamera.cropped(to: rect), matte: movedMatte, transform: t)
    }

    /// A full-picture card for the Backdrop arrangement when the screen is paused, gone or not allowed; nil while it is live or
    /// starting (starting keeps the usual dark placeholder).
    func fullCard(_ f: Inputs) -> CIImage? {
        rememberFrame(f)
        guard f.status == .paused || f.status == .lost || f.status == .denied else { return nil }
        return card(f.status, kind: f.kind, size: rect.size, title: f.title)
    }

    // MARK: Floating panel

    private func stage(_ f: Inputs) -> CIImage {
        let layout = f.layout
        let flat = StageGeometry.panelRect(layout.panel, aspect: aspect, in: rect.size)
        let quad = StageGeometry.panelQuad(layout, aspect: aspect, head: f.head, lift: f.live.panelLift, in: rect.size)
        let w = max(8, Int(flat.width.rounded())), h = max(8, Int(flat.height.rounded()))
        let radius = StageGeometry.cornerRadius(roundness: layout.roundness, height: Double(h))
        let art = panelArt(width: w, height: h, radius: radius, shadow: layout.shadow)
        let small = smallBlur(of: shownContent(f))

        // 1. The surround.
        var picture = surround(f, small: small)

        // 2. The screen's light spilling onto it.
        if let small {
            let bounds = StageGeometry.bounds(of: quad)
            // The screen's light falls on the wall around it: its colours, spread a little wider than the panel and softened, fading
            // with distance. A white slide lights the wall up; a dark editor barely does.
            let spill = small.transformed(by: Compositor.fillTransform(small.extent, into: bounds.insetBy(dx: -bounds.width * 0.18, dy: -bounds.height * 0.22)))
                .clampedToExtent()
            let falloff = ellipse(center: CGPoint(x: bounds.midX, y: bounds.midY - bounds.height * 0.04),
                                  radii: CGSize(width: bounds.width * 0.95, height: bounds.height * 1.1))
            let strength = layout.surround == .ambient ? 0.42 : 0.2
            let glow = spill.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear), kCIInputMaskImageKey: falloff])
                .applyingFilter("CIColorMatrix", parameters: Self.gain(strength))
                .cropped(to: rect)
            picture = glow.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: picture]).cropped(to: rect)
        }

        // 3. The shadow, deeper and further while held.
        let lift = f.live.panelLift
        let flatExtent = CGRect(x: 0, y: 0, width: w, height: h)
        let shadow = art.shadow
            .transformed(by: CGAffineTransform(translationX: 0, y: -CGFloat(lift) * Double(h) * 0.025))
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(1 + 0.4 * lift))])
        picture = warp(shadow, from: flatExtent, to: quad).composited(over: picture)

        // 4. The panel: content fitted onto the bezel, cut to shape, rimmed, then turned.
        let body = panelBody(f, art: art, width: w, height: h)
        let panel = warp(body, from: flatExtent, to: quad)
        picture = panel.composited(over: picture)

        // 5. Your soft shadow falling on the panel.
        if let matte = f.matte {
            let you = StageGeometry.isIdentity(layout.presenter) ? matte
                : feathered(matte).transformed(by: StageGeometry.presenterTransform(layout.presenter, in: rect.size)).cropped(to: rect)
            let onPanel = softShadow(of: you, offset: CGVector(dx: 18, dy: -10), sigma: 5)
                .applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear),
                                                                   kCIInputMaskImageKey: warp(art.mask, from: flatExtent, to: quad)])
            picture = darken(picture, by: onPanel, strength: 0.22 + 0.14 * layout.shadow)
        }

        // 6. The label.
        if layout.showsLabel, let title = f.title, !title.isEmpty, let label = labelImage(title) {
            let bottom = CGPoint(x: (quad[0].x + quad[1].x) / 2, y: min(quad[0].y, quad[1].y))
            let y = max(label.extent.height / 2 + 8, bottom.y - 30)
            picture = label.transformed(by: CGAffineTransform(translationX: bottom.x - label.extent.width / 2, y: y - label.extent.height / 2))
                .composited(over: picture)
        }
        return picture.cropped(to: rect)
    }

    /// The live screen, or the card standing in for it.
    private func shownContent(_ f: Inputs) -> CIImage? {
        f.status == .live ? f.content : nil
    }

    private func panelBody(_ f: Inputs, art: PanelArt, width w: Int, height h: Int) -> CIImage {
        let box = CGRect(x: 0, y: 0, width: w, height: h)
        let bezel = CIImage(color: CIColor(red: StageArt.bezel.x, green: StageArt.bezel.y, blue: StageArt.bezel.z)).cropped(to: box)
        var inside: CIImage
        if f.status == .live, let content = f.content {
            inside = scaled(content, into: box).composited(over: bezel)
        } else {
            inside = card(f.status == .live ? .starting : f.status, kind: f.kind, size: box.size, title: f.title).composited(over: bezel)
        }
        inside = inside.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: art.mask])
        return art.rim.composited(over: inside).cropped(to: box)
    }

    /// `image` fitted inside `box` without cropping. Big shrinks (a 2560-pixel window into a 700-pixel panel) use Lanczos, which
    /// keeps small text from shimmering the way plain resampling does.
    private func scaled(_ image: CIImage, into box: CGRect) -> CIImage {
        let e = image.extent
        guard e.width > 0, e.height > 0 else { return CIImage.empty() }
        let s = min(box.width / e.width, box.height / e.height)
        let w = e.width * s, h = e.height * s
        let origin = CGPoint(x: box.minX + (box.width - w) / 2, y: box.minY + (box.height - h) / 2)
        let moved = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
        var out: CIImage
        if s < 0.7 {
            let lanczos = CIFilter.lanczosScaleTransform()
            lanczos.inputImage = moved
            lanczos.scale = Float(s)
            lanczos.aspectRatio = 1
            out = lanczos.outputImage ?? moved.transformed(by: CGAffineTransform(scaleX: s, y: s))
        } else {
            out = moved.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        out = out.transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
        return out.cropped(to: CGRect(origin: origin, size: CGSize(width: w, height: h)))
    }

    /// Maps `image`'s `extent` onto the four corners (lower left, lower right, upper right, upper left).
    private func warp(_ image: CIImage, from extent: CGRect, to quad: [CGPoint]) -> CIImage {
        let f = CIFilter.perspectiveTransformWithExtent()
        f.inputImage = image
        f.extent = extent
        f.bottomLeft = quad[0]
        f.bottomRight = quad[1]
        f.topRight = quad[2]
        f.topLeft = quad[3]
        return f.outputImage ?? image
    }

    // MARK: Surround

    private func surround(_ f: Inputs, small: CIImage?) -> CIImage {
        switch f.layout.surround {
        case .ambient:
            // A dim room lit only by the screen: dark slate, faintly tinted with the screen's overall colour. The light itself, brightest
            // round the panel, is the glow laid on next.
            guard let small else { return slate().applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: vignette]).cropped(to: rect) }
            let average = small.clampedToExtent().applyingGaussianBlur(sigma: 40).cropped(to: small.extent)
            let tint = average.transformed(by: Compositor.fillTransform(small.extent, into: rect)).cropped(to: rect)
                .applyingFilter("CIColorMatrix", parameters: Self.gain(0.1))
            return WorldKit.adding(tint, to: slate())
                .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: vignette]).cropped(to: rect)
        case .room:
            let soft = BackdropLens.blurred(f.camera, sigma: 22, bokeh: 0.45) ?? f.camera
            return WorldKit.grade(soft, saturation: 0.85, tint: (0.72, 0.72, 0.74)).cropped(to: rect)
        case .backdrop:
            return (f.surround ?? slate()).cropped(to: rect)
        }
    }

    private func slate() -> CIImage {
        if let slateImage { return slateImage }
        let g = CIFilter.linearGradient()
        g.point0 = CGPoint(x: rect.width * 0.3, y: rect.height)
        g.point1 = CGPoint(x: rect.width * 0.6, y: 0)
        g.color0 = CIColor(red: 0.13, green: 0.14, blue: 0.17)
        g.color1 = CIColor(red: 0.05, green: 0.055, blue: 0.07)
        let made = (g.outputImage ?? CIImage(color: .black)).cropped(to: rect)
        slateImage = made
        return made
    }

    private var slateImage: CIImage?

    /// Darkens the corners a little, like light falling off in a room.
    private lazy var vignette: CIImage = {
        let g = CIFilter.radialGradient()
        g.center = CGPoint(x: rect.midX, y: rect.midY * 1.08)
        g.radius0 = Float(rect.height * 0.3)
        g.radius1 = Float(hypot(rect.width, rect.height) * 0.58)
        g.color0 = CIColor(red: 1, green: 1, blue: 1)
        g.color1 = CIColor(red: 0.5, green: 0.5, blue: 0.52)
        return (g.outputImage ?? CIImage(color: .white)).cropped(to: rect)
    }()

    /// The content on a tiny canvas, blurred: the source of the ambient surround and the glow. Working at this size makes a very
    /// wide blur cost next to nothing.
    private func smallBlur(of content: CIImage?) -> CIImage? {
        guard let content, content.extent.width > 2, content.extent.height > 2 else {
            return frozenSmall.map { CIImage(cgImage: $0) }
        }
        let box = CGRect(x: 0, y: 0, width: 96, height: max(24, (96 * content.extent.height / content.extent.width).rounded()))
        return content.transformed(by: Compositor.fillTransform(content.extent, into: box)).clampedToExtent()
            .applyingGaussianBlur(sigma: 3.2).cropped(to: box)
    }

    private func ellipse(center: CGPoint, radii: CGSize) -> CIImage {
        let g = CIFilter.gaussianGradient()
        g.center = .zero
        g.radius = 1
        g.color0 = CIColor(red: 1, green: 1, blue: 1)
        g.color1 = CIColor(red: 0, green: 0, blue: 0)
        return (g.outputImage ?? CIImage(color: .white))
            .transformed(by: CGAffineTransform(scaleX: radii.width, y: radii.height).concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
            .cropped(to: rect)
    }

    private static func gain(_ k: Double) -> [String: Any] {
        ["inputRVector": CIVector(x: CGFloat(k), y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: CGFloat(k), z: 0, w: 0),
         "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(k), w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(k))]
    }

    // MARK: Shadows of you

    /// A soft copy of a cutout, shifted: worked out at a quarter of the size, where a wide blur is cheap.
    private func softShadow(of matte: CIImage, offset: CGVector, sigma: Double) -> CIImage {
        let small = WorldKit.shrink(matte, rect: rect, by: 0.25).clampedToExtent().applyingGaussianBlur(sigma: sigma)
            .cropped(to: CGRect(x: 0, y: 0, width: rect.width / 4, height: rect.height / 4))
        return WorldKit.enlarge(small, rect: rect, from: 0.25).transformed(by: CGAffineTransform(translationX: offset.dx, y: offset.dy)).cropped(to: rect)
    }

    /// `image` darkened where `mask` is light, by up to `strength`.
    private func darken(_ image: CIImage, by mask: CIImage, strength: Double) -> CIImage {
        let k = CGFloat(strength)
        let factor = mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: -k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: -k, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: -k, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 1),
        ]).cropped(to: mask.extent.intersection(rect))
        return image.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: factor]).cropped(to: rect)
    }

    private func dropShadow(of matte: CIImage, onto image: CIImage) -> CIImage {
        darken(image, by: softShadow(of: matte, offset: CGVector(dx: 10, dy: -12), sigma: 4), strength: 0.3)
    }

    /// The cutout with its edges against the camera's frame softened, so moving you does not show a hard line where the camera's
    /// picture ends.
    private func feathered(_ matte: CIImage) -> CIImage {
        matte.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: edgeFeather]).cropped(to: rect)
    }

    private lazy var edgeFeather: CIImage = {
        let w = Int(rect.width), h = Int(rect.height)
        guard let ctx = StageArt.bitmap(width: w, height: h) else { return CIImage(color: .white).cropped(to: rect) }
        ctx.setFillColor(StageArt.white(1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setBlendMode(.destinationOut)
        func fade(_ start: CGPoint, _ end: CGPoint, _ r: CGRect) {
            ctx.saveGState()
            ctx.clip(to: r)
            let colors = [StageArt.black(1), StageArt.black(0)] as CFArray
            if let g = CGGradient(colorsSpace: StageArt.space, colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: start, end: end, options: [])
            }
            ctx.restoreGState()
        }
        let side: CGFloat = 26, bottom: CGFloat = 46
        fade(CGPoint(x: 0, y: 0), CGPoint(x: side, y: 0), CGRect(x: 0, y: 0, width: side, height: CGFloat(h)))
        fade(CGPoint(x: CGFloat(w), y: 0), CGPoint(x: CGFloat(w) - side, y: 0), CGRect(x: CGFloat(w) - side, y: 0, width: side, height: CGFloat(h)))
        fade(CGPoint(x: 0, y: CGFloat(h)), CGPoint(x: 0, y: CGFloat(h) - side), CGRect(x: 0, y: CGFloat(h) - side, width: CGFloat(w), height: side))
        fade(CGPoint(x: 0, y: 0), CGPoint(x: 0, y: bottom), CGRect(x: 0, y: 0, width: CGFloat(w), height: bottom))
        guard let image = ctx.makeImage() else { return CIImage(color: .white).cropped(to: rect) }
        // White where the camera's picture is solid, fading at the edges; opaque, so it multiplies the matte cleanly.
        return CIImage(cgImage: image).composited(over: CIImage(color: .black).cropped(to: rect))
    }()

    // MARK: Presenter

    /// The screen filling the picture, letterboxed over a blurred copy of itself as a backdrop always has been, or its card.
    private func filled(_ f: Inputs) -> CIImage {
        if f.status != .live || f.content == nil {
            let c = card(f.status == .live ? .starting : f.status, kind: f.kind, size: rect.size, title: f.title)
            return c.cropped(to: rect)
        }
        guard let content = f.content else { return slate() }
        let back = content.transformed(by: Compositor.fillTransform(content.extent, into: CGRect(x: 0, y: 0, width: 160, height: 90)))
            .clampedToExtent().applyingGaussianBlur(sigma: 4.5).cropped(to: CGRect(x: 0, y: 0, width: 160, height: 90))
        let backdrop = WorldKit.enlarge(back, rect: rect, from: 0.125)
        let fitted = scaled(content, into: rect)
        return fitted.composited(over: backdrop).cropped(to: rect)
    }

    private var framing: CGPoint?

    /// You in a bubble. The camera, cutout, face and hands a lens is given are moved into the bubble too and stop at its edge, and the
    /// picture behind you holds the bubble's room and ring with nobody in it, so a lens that lays you back over it keeps the bubble.
    private func bubble(_ f: Inputs, over backdrop: CIImage) -> Placed {
        let layout = f.layout
        let square = StageGeometry.bubbleRect(layout.presenter, in: rect.size)
        let grow = CGFloat(0.02 * f.live.presenterLift)
        let shown = square.insetBy(dx: -square.width * grow / 2, dy: -square.height * grow / 2)
        let side = max(16, Int(square.width.rounded()))
        let art = bubbleArt(side: side, style: layout.presenterStyle, shadow: layout.shadow)

        // Frame your head and shoulders: a little above the middle of your cutout, steadied so the framing glides, not twitches.
        let wanted = f.anchor.map { CGPoint(x: $0.x, y: $0.y + rect.height * 0.16) } ?? CGPoint(x: rect.midX, y: rect.height * 0.58)
        let k = 1 - exp(-max(0, f.dt) / 0.45)
        let current = framing.map { CGPoint(x: $0.x + (wanted.x - $0.x) * k, y: $0.y + (wanted.y - $0.y) * k) } ?? wanted
        framing = current
        let crop = rect.height * 0.7
        let cx = min(rect.maxX - crop / 2, max(rect.minX + crop / 2, current.x))
        let cy = min(rect.maxY - crop / 2, max(rect.minY + crop / 2, current.y))
        let source = CGRect(x: cx - crop / 2, y: cy - crop / 2, width: crop, height: crop)

        // Where a point on the camera picture lands in the bubble.
        let s = shown.width / source.width
        let t = CGAffineTransform(translationX: -source.minX, y: -source.minY)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: shown.minX, y: shown.minY))
        let place = CGAffineTransform(scaleX: shown.width / CGFloat(side), y: shown.height / CGFloat(side))
            .concatenating(CGAffineTransform(translationX: shown.minX, y: shown.minY))
        let mask = art.mask.transformed(by: place)
        let lift = f.live.presenterLift
        let shadow = art.shadow.transformed(by: place)
            .transformed(by: CGAffineTransform(translationX: 0, y: -CGFloat(lift) * shown.height * 0.03))
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(1 + 0.4 * lift))])
        let ring = art.ring.transformed(by: place)

        /// The bubble holding `picture`, over the stage.
        func framed(_ picture: CIImage) -> CIImage {
            let inside = picture.cropped(to: source).transformed(by: t).applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: mask])
            return ring.composited(over: inside.composited(over: shadow.composited(over: backdrop))).cropped(to: rect)
        }

        // You over your room softly out of focus, like a portrait lens.
        guard let matte = f.matte, let room = BackdropLens.blurred(f.camera, sigma: 9, bokeh: 0.35) else {
            return Placed(composed: framed(f.camera), camera: f.camera, matte: f.matte, transform: t)
        }
        let you = WorldKit.place(person: f.camera, over: room, matte: matte, rect: rect)
        // What a lens is given stops at the bubble's edge: nothing outside it is shown, so none of it is you.
        func inBubble(_ image: CIImage) -> CIImage {
            image.transformed(by: t).applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: mask]).cropped(to: rect)
        }
        return Placed(composed: framed(you), camera: inBubble(f.camera), matte: inBubble(matte), transform: t, backdrop: framed(room))
    }

    // MARK: Cached art

    private struct PanelKey: Equatable { var w: Int, h: Int, radius: Int, shadow: Int }

    private struct PanelArt {
        var key: PanelKey
        /// White inside the panel's shape, at the panel's size.
        var mask: CIImage
        /// The fine highlight round the rim and a whisper of sheen at the top.
        var rim: CIImage
        /// Both shadows, placed so the panel's own box is at the origin.
        var shadow: CIImage
    }

    private var panelCache: PanelArt?
    /// How many times the panel's art was drawn; for tests that check it is kept.
    private(set) var panelArtBuilds = 0

    private func panelArt(width w: Int, height h: Int, radius: Double, shadow: Double) -> PanelArt {
        let key = PanelKey(w: w, h: h, radius: Int((radius * 4).rounded()), shadow: Int((shadow * 50).rounded()))
        if let cached = panelCache, cached.key == key { return cached }
        panelArtBuilds += 1
        let box = CGRect(x: 0, y: 0, width: w, height: h)
        let path = StageArt.continuousRect(box, radius: CGFloat(radius))

        var mask = CIImage.empty(), rim = CIImage.empty(), shadowImage = CIImage.empty()
        if let ctx = StageArt.bitmap(width: w, height: h) {
            ctx.addPath(path)
            ctx.setFillColor(StageArt.white(1))
            ctx.fillPath()
            if let image = ctx.makeImage() { mask = CIImage(cgImage: image) }
        }
        if let ctx = StageArt.bitmap(width: w, height: h) {
            // A hairline just inside the edge: bright along the top like a lit bevel, fading toward the bottom.
            ctx.saveGState()
            ctx.addPath(StageArt.continuousRect(box.insetBy(dx: 0.75, dy: 0.75), radius: CGFloat(radius) - 0.75))
            ctx.setLineWidth(1.5)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            let colors = [StageArt.white(0.42), StageArt.white(0.12), StageArt.white(0.07)] as CFArray
            if let g = CGGradient(colorsSpace: StageArt.space, colors: colors, locations: [0, 0.35, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(h)), end: CGPoint(x: 0, y: 0), options: [])
            }
            ctx.restoreGState()
            // A faint sheen over the top third, as on glass.
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let sheen = [StageArt.white(0.045), StageArt.white(0)] as CFArray
            if let g = CGGradient(colorsSpace: StageArt.space, colors: sheen, locations: [0, 1]) {
                let corner = CGPoint(x: 0, y: CGFloat(h))
                ctx.drawRadialGradient(g, startCenter: corner, startRadius: 0, endCenter: corner, endRadius: CGFloat(max(w, h)) * 0.7, options: [])
            }
            ctx.restoreGState()
            // And a dark line just outside, so the panel holds its edge on a light surround.
            ctx.addPath(path)
            ctx.setStrokeColor(StageArt.black(0.32))
            ctx.setLineWidth(1)
            ctx.strokePath()
            if let image = ctx.makeImage() { rim = CIImage(cgImage: image) }
        }
        // The shadows, drawn at half size with room around them, then laid back at full size.
        let scale: CGFloat = 0.5
        let pad = CGFloat(h) * 0.34 + 24
        let sw = Int(((CGFloat(w) + pad * 2) * scale).rounded(.up)), sh = Int(((CGFloat(h) + pad * 2) * scale).rounded(.up))
        if let ctx = StageArt.bitmap(width: sw, height: sh) {
            ctx.scaleBy(x: scale, y: scale)
            let shape = StageArt.continuousRect(box.offsetBy(dx: pad, dy: pad), radius: CGFloat(radius))
            // Shadow only: the shape is drawn far off the canvas and its shadow thrown back onto it.
            let away: CGFloat = 100_000
            func cast(blur: CGFloat, dy: CGFloat, alpha: Double) {
                ctx.saveGState()
                ctx.translateBy(x: away, y: 0)
                ctx.setShadow(offset: CGSize(width: -away * scale, height: dy * scale), blur: blur * scale, color: StageArt.black(alpha))
                ctx.addPath(shape)
                ctx.setFillColor(StageArt.black(1))
                ctx.fillPath()
                ctx.restoreGState()
            }
            let amount = max(0, min(1, shadow))
            cast(blur: CGFloat(h) * 0.16, dy: -CGFloat(h) * 0.05, alpha: 0.62 * amount)
            cast(blur: CGFloat(h) * 0.05, dy: -CGFloat(h) * 0.014, alpha: 0.38 * amount)
            cast(blur: 3, dy: -1.5, alpha: 0.35 * amount)
            if let image = ctx.makeImage() {
                shadowImage = CIImage(cgImage: image)
                    .transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale).concatenating(CGAffineTransform(translationX: -pad, y: -pad)))
            }
        }
        let art = PanelArt(key: key, mask: mask, rim: rim, shadow: shadowImage)
        panelCache = art
        return art
    }

    private struct BubbleKey: Equatable { var side: Int, style: PresenterStyle, shadow: Int }

    private struct BubbleArt {
        var key: BubbleKey
        var mask: CIImage
        var ring: CIImage
        var shadow: CIImage
    }

    private var bubbleCache: BubbleArt?
    private(set) var bubbleArtBuilds = 0

    private func bubbleArt(side: Int, style: PresenterStyle, shadow: Double) -> BubbleArt {
        let key = BubbleKey(side: side, style: style, shadow: Int((shadow * 50).rounded()))
        if let cached = bubbleCache, cached.key == key { return cached }
        bubbleArtBuilds += 1
        let box = CGRect(x: 0, y: 0, width: side, height: side)
        func shape(_ r: CGRect) -> CGPath {
            style == .circle ? CGPath(ellipseIn: r, transform: nil) : StageArt.continuousRect(r, radius: r.width * 0.2)
        }
        var mask = CIImage.empty(), ring = CIImage.empty(), shadowImage = CIImage.empty()
        if let ctx = StageArt.bitmap(width: side, height: side) {
            ctx.addPath(shape(box))
            ctx.setFillColor(StageArt.white(1))
            ctx.fillPath()
            if let image = ctx.makeImage() { mask = CIImage(cgImage: image) }
        }
        if let ctx = StageArt.bitmap(width: side, height: side) {
            // A soft white border, brighter at the top, and a hairline of shade outside it.
            let border = max(2.5, CGFloat(side) * 0.016)
            ctx.saveGState()
            ctx.addPath(shape(box.insetBy(dx: border / 2 + 0.5, dy: border / 2 + 0.5)))
            ctx.setLineWidth(border)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            let colors = [StageArt.white(0.96), StageArt.white(0.74)] as CFArray
            if let g = CGGradient(colorsSpace: StageArt.space, colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(side)), end: .zero, options: [])
            }
            ctx.restoreGState()
            ctx.addPath(shape(box.insetBy(dx: 0.5, dy: 0.5)))
            ctx.setStrokeColor(StageArt.black(0.22))
            ctx.setLineWidth(1)
            ctx.strokePath()
            if let image = ctx.makeImage() { ring = CIImage(cgImage: image) }
        }
        let scale: CGFloat = 0.5
        let pad = CGFloat(side) * 0.3 + 16
        let full = Int(((CGFloat(side) + pad * 2) * scale).rounded(.up))
        if let ctx = StageArt.bitmap(width: full, height: full) {
            ctx.scaleBy(x: scale, y: scale)
            let s = shape(box.offsetBy(dx: pad, dy: pad))
            let away: CGFloat = 100_000
            let amount = max(0, min(1, shadow))
            for (blur, dy, alpha) in [(CGFloat(side) * 0.14, -CGFloat(side) * 0.05, 0.55 * amount), (CGFloat(side) * 0.035, -CGFloat(side) * 0.012, 0.35 * amount)] {
                ctx.saveGState()
                ctx.translateBy(x: away, y: 0)
                ctx.setShadow(offset: CGSize(width: -away * scale, height: dy * scale), blur: blur * scale, color: StageArt.black(alpha))
                ctx.addPath(s)
                ctx.setFillColor(StageArt.black(1))
                ctx.fillPath()
                ctx.restoreGState()
            }
            if let image = ctx.makeImage() {
                shadowImage = CIImage(cgImage: image)
                    .transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale).concatenating(CGAffineTransform(translationX: -pad, y: -pad)))
            }
        }
        let art = BubbleArt(key: key, mask: mask, ring: ring, shadow: shadowImage)
        bubbleCache = art
        return art
    }

    private var labelCache: (text: String, image: CIImage)?

    private func labelImage(_ text: String) -> CIImage? {
        if let cached = labelCache, cached.text == text { return cached.image }
        let size: CGFloat = 15
        let l = StageArt.fitted(text, size: size, weight: .semibold, color: StageArt.white(0.95), maxWidth: 520)
        let w = Int((StageArt.width(of: l) + size * 1.3 + 24).rounded(.up)), h = Int((size * 1.85 + 24).rounded(.up))
        guard let ctx = StageArt.bitmap(width: w, height: h) else { return nil }
        StageArt.pill(text, at: CGPoint(x: CGFloat(w) / 2, y: CGFloat(h) / 2), size: size, in: ctx, fill: StageArt.black(0.5), maxWidth: 520)
        guard let image = ctx.makeImage() else { return nil }
        let made = CIImage(cgImage: image)
        labelCache = (text, made)
        return made
    }

    // MARK: Cards

    private struct CardKey: Equatable { var status: StageContentStatus, kind: StageContentKind, w: Int, h: Int, title: String?, frozen: Int }

    private var cardCache: [(key: CardKey, image: CIImage)] = []
    private(set) var cardBuilds = 0

    /// The card for a status at a size. Kept, so a paused panel costs nothing per frame.
    func card(_ status: StageContentStatus, kind: StageContentKind = .window, size: CGSize, title: String?) -> CIImage {
        let w = max(8, Int(size.width.rounded())), h = max(8, Int(size.height.rounded()))
        let key = CardKey(status: status, kind: kind, w: w, h: h, title: status == .lost ? title : nil, frozen: status == .paused ? frozenGeneration : 0)
        if let hit = cardCache.first(where: { $0.key == key }) { return hit.image }
        cardBuilds += 1
        var image = CIImage(color: CIColor(red: 0.08, green: 0.085, blue: 0.1)).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        if let ctx = StageArt.bitmap(width: w, height: h) {
            StageCards.draw(status, kind: kind, size: CGSize(width: w, height: h), title: title, frozen: status == .paused ? frozenSmall : nil, in: ctx)
            if let made = ctx.makeImage() { image = CIImage(cgImage: made) }
        }
        cardCache.append((key, image))
        if cardCache.count > 6 { cardCache.removeFirst() }
        return image
    }

    // MARK: Freezing for the paused card

    /// A small, blurred copy of the screen as it was the moment sharing was paused. Copied into memory of its own, since the
    /// capture's buffers are reused for later frames.
    private var frozenSmall: CGImage?
    private var frozenGeneration = 0
    private var lastStatus = StageContentStatus.live

    /// The capture keeps its last frame while paused, so the moment sharing pauses that frame is still the one handed in.
    private func rememberFrame(_ f: Inputs) {
        if f.status == .paused, lastStatus != .paused {
            frozenGeneration += 1
            frozenSmall = nil
            if let last = f.content, last.extent.width > 2 {
                let box = CGRect(x: 0, y: 0, width: 160, height: max(40, (160 * last.extent.height / last.extent.width).rounded()))
                let small = last.transformed(by: Compositor.fillTransform(last.extent, into: box)).clampedToExtent()
                    .applyingGaussianBlur(sigma: 6).cropped(to: box)
                frozenSmall = context.createCGImage(small, from: box, format: .RGBA8, colorSpace: StageArt.space)
            }
        }
        lastStatus = f.status
    }
}
