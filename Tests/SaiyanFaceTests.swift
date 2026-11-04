import CoreImage
import simd
import XCTest

/// Runs `SaiyanFace` the way the Dragon Ball lens does (like `DressUpLens.render`): a rig turns the face into frames, the body state is
/// applied, the springs move, the long hair goes in a layer behind the person, the rest in a layer over them, and the hair picture is
/// laid by the graphics chip when `gpu` is on (`hairImage`), or painted into the layer otherwise.
private final class SaiyanFaceBench {
    let face = SaiyanFace()
    let rig = HeadwearRig()
    var gpu: Bool
    private var last: HeadwearFrame?
    private(set) var presence = 0.0
    private(set) var frame = 0

    init(gpu: Bool = true) { self.gpu = gpu }

    func render(_ input: LensInput, _ state: SaiyanBodyState) -> CIImage {
        defer { frame += 1 }
        let dt = min(0.1, max(0, input.dt))
        let now: HeadwearFrame
        if let f = rig.update(input.face, dt: input.dt, bounds: input.rect) {
            presence = f.seen <= dt + 1e-9 ? 1 : min(1, presence + dt / 0.15)
            now = f
            last = f
        } else {
            presence = max(0, presence - dt / 0.3)
            if rig.hasForgotten { face.reset() }
            guard let held = last, presence > 0.01 else { last = nil; presence = 0; face.apply(state); return input.composed }
            now = held
        }
        face.apply(state)
        if input.face != nil { face.advance(now) }
        let alpha = HeadwearEase.smoothstep(presence)
        var picture = input.composed
        var backInFront = false
        if input.matte != nil {
            // Only when something is behind: re-laying the person over the scenery for nothing would cost a layer and shift their edge.
            if face.drawsBehind, let painted = input.services.overlay({ ctx in face.drawBack(HeadwearPen(ctx: ctx), now, behindPerson: true) }) {
                let back = gpu ? face.washBack(painted) : painted
                picture = input.placingPerson(over: (alpha < 0.999 ? back.fading(alpha) : back).composited(over: input.scenery))
            }
        } else {
            backInFront = true
        }
        guard var layer = input.services.overlay({ ctx in
            let pen = HeadwearPen(ctx: ctx)
            if backInFront { face.drawBack(pen, now, behindPerson: false) }
            face.draw(pen, now)
        }) else { return picture }
        if gpu, let hair = face.hairImage(now) { layer = hair.composited(over: layer) }
        return (alpha < 0.999 ? layer.fading(alpha) : layer).composited(over: picture).cropped(to: input.rect)
    }

    /// The long hair alone, as the latest frame put it behind the person, over plain grey.
    func back(_ input: LensInput) -> CIImage? {
        guard let f = last, let painted = input.services.overlay({ ctx in face.drawBack(HeadwearPen(ctx: ctx), f, behindPerson: true) }) else { return nil }
        let layer = gpu ? face.washBack(painted) : painted
        return layer.composited(over: CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: input.rect))
    }
}

final class SaiyanFaceTests: XCTestCase {
    private let h = LensHarness()
    private let still = SyntheticScene(center: CGPoint(x: 640, y: 330))
    private lazy var base = h.input(still)
    private lazy var plain = h.bitmap(base.composed)

    // MARK: Helpers

    /// A picture read out now, for keeping: lens pictures are lazy and share drawing buffers with later frames.
    private func kept(_ image: CIImage) -> CIImage {
        guard let made = h.ciContext.createCGImage(image, from: base.rect, format: .RGBA8, colorSpace: TestSupport.srgb) else { return image }
        return CIImage(cgImage: made)
    }

    private static func settled(_ form: SaiyanForm) -> SaiyanBodyState {
        var s = SaiyanBodyState()
        s.form = form; s.previousForm = form; s.level = form.power
        return s
    }

    private func frame(_ b: LensInput, face: FaceState?, time: Double, dt: Double = 1.0 / 30, matte: Bool = true) -> LensInput {
        LensInput(time: time, dt: dt, rect: b.rect, camera: b.camera, matte: matte ? b.matte : nil, background: matte ? b.background : nil,
                  composed: matte ? b.composed : b.camera, matteGrid: nil, face: face, services: b.services)
    }

    /// Plays `state` (or a state made for each frame) for `frames` frames and returns the last picture.
    @discardableResult
    private func play(_ bench: SaiyanFaceBench, _ b: LensInput, face: FaceState?, frames: Int, matte: Bool = true,
                      state: (Int) -> SaiyanBodyState) -> CIImage {
        var out = b.composed
        for i in 0..<frames {
            let t = Double(bench.frame) / 30
            var s = state(i)
            s.time = t
            out = bench.render(frame(b, face: face, time: t, matte: matte), s)
        }
        return out
    }

    private func scene(roll: Double = 0, open: Double = 0, blink: Double = 0, brows: Double = 0, scale: Double = 1,
                       center: CGPoint = CGPoint(x: 640, y: 330)) -> SyntheticScene {
        var s = SyntheticScene(center: center)
        s.roll = roll; s.mouthOpen = open; s.blink = blink; s.browRaise = brows; s.scale = scale
        return s
    }

    /// A box in face units, in output pixels.
    private func box(_ face: FaceState, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> CGRect {
        let c = cos(face.roll), s = sin(face.roll), io = face.interocular
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: face.eyeCenter.x + (x * c - y * s) * io, y: face.eyeCenter.y + (x * s + y * c) * io) }
        let corners = [p(x0, y0), p(x1, y0), p(x0, y1), p(x1, y1)]
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    private func point(_ face: FaceState, _ x: Double, _ y: Double) -> (Int, Int) {
        let c = cos(face.roll), s = sin(face.roll), io = face.interocular
        return (Int(face.eyeCenter.x + (x * c - y * s) * io), Int(face.eyeCenter.y + (x * s + y * c) * io))
    }

    private func changed(_ bits: Bitmap, from other: Bitmap, in rect: CGRect, threshold: Int = 40) -> Int {
        var n = 0
        for x in Int(max(0, rect.minX))..<Int(min(1280, rect.maxX)) {
            for y in Int(max(0, rect.minY))..<Int(min(720, rect.maxY)) {
                let a = bits.pixel(x, y), b = other.pixel(x, y)
                if abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) > threshold { n += 1 }
            }
        }
        return n
    }

    /// The mean colour, 0...1, of the pixels in `rect` that the face changed.
    private func meanChanged(_ bits: Bitmap, from other: Bitmap, in rect: CGRect) -> SIMD3<Double>? {
        var sum = SIMD3<Double>(0, 0, 0), n = 0.0
        for x in Int(max(0, rect.minX))..<Int(min(1280, rect.maxX)) {
            for y in Int(max(0, rect.minY))..<Int(min(720, rect.maxY)) {
                let a = bits.pixel(x, y), b = other.pixel(x, y)
                guard abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) > 60 else { continue }
                sum += SIMD3(Double(a.r), Double(a.g), Double(a.b)) / 255
                n += 1
            }
        }
        return n > 0 ? sum / n : nil
    }

    /// How far a colour is from the nearest point between the palette's shade and highlight (through its base).
    private func distance(_ c: SIMD3<Double>, to p: SaiyanPalette) -> Double {
        func segment(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
            let d = b - a, t = max(0, min(1, simd_dot(c - a, d) / max(1e-9, simd_dot(d, d))))
            return simd_length(c - (a + d * t))
        }
        return min(segment(p.hairShade, p.hairBase), segment(p.hairBase, p.hairHighlight))
    }

    /// The highest row in a column of `rect` that differs from the plain picture.
    private func top(_ bits: Bitmap, _ rect: CGRect) -> Int? {
        for y in stride(from: min(719, Int(rect.maxY)), to: max(0, Int(rect.minY)), by: -1)
        where changed(bits, from: plain, in: CGRect(x: rect.minX, y: Double(y), width: rect.width, height: 1)) > 2 { return y }
        return nil
    }

    // MARK: Base

    func testBaseDrawsNothingAtAll() {
        let bench = SaiyanFaceBench()
        let out = play(bench, base, face: still.face(), frames: 40) { _ in Self.settled(.base) }
        XCTAssertEqual(h.bitmap(out).change(from: plain, in: base.rect), 0, "base leaves the picture exactly as it was")
        XCTAssertFalse(bench.face.isDrawing)
        XCTAssertFalse(bench.face.drawsBehind)
        XCTAssertFalse(bench.face.hair.isShowing)
        // Without a cutout too.
        let noMatte = SaiyanFaceBench()
        let bare = play(noMatte, base, face: still.face(), frames: 10, matte: false) { _ in Self.settled(.base) }
        XCTAssertEqual(h.bitmap(bare).change(from: h.bitmap(base.camera), in: base.rect), 0)
    }

    // MARK: Every form

    func testEveryFormCoversTheHeadInItsOwnColours() throws {
        let face = still.face()
        let above = box(face, -0.8, 1.7, 0.8, 2.4), crown = box(face, -1.0, 1.1, 1.0, 1.7)
        var pictures: [CIImage] = []
        for form in SaiyanForm.allCases {
            let bench = SaiyanFaceBench()
            let out = play(bench, base, face: face, frames: 40) { _ in Self.settled(form) }
            pictures.append(kept(out))
            Output.save(out, as: "saiyan-face-\(form).png")
            guard !form.isBase else { continue }
            let bits = h.bitmap(out)
            XCTAssertGreaterThan(changed(bits, from: plain, in: above), 2500, "\(form): hair stands above the head")
            XCTAssertGreaterThan(changed(bits, from: plain, in: crown), 6000, "\(form): and covers the crown (the person's own hair)")
            let mean = try XCTUnwrap(meanChanged(bits, from: plain, in: above.union(crown)))
            let miss = distance(mean, to: form.palette)
            XCTAssertLessThan(miss, 0.2, "\(form): the hair is the palette's colour, got \(mean) (off by \(miss))")
            XCTAssertTrue(bench.face.hair.isShowing)
            XCTAssertEqual(bench.face.drawsBehind, form == .superSaiyan3, "\(form): only Super Saiyan 3 has hair behind")
        }
        Output.save(SaiyanBench.sheet(pictures, columns: 5, scale: 0.4), as: "saiyan-face-sheet-cartoon.png")
    }

    func testEveryFormOnARealHeadAtThreeSizes() {
        var pictures: [CIImage] = []
        for (io, center) in [(52.0, CGPoint(x: 640, y: 330)), (72, CGPoint(x: 640, y: 300)), (104, CGPoint(x: 640, y: 250))] {
            var person = HeadwearRealHead(center: center, io: io)
            if io > 100 { person.hair = CGColor(srgbRed: 0.85, green: 0.7, blue: 0.45, alpha: 1) }
            let input = person.input(services: h.services)
            let plainReal = h.bitmap(input.composed)
            for form in SaiyanForm.allCases where io == 72 || [.superSaiyan, .superSaiyan3, .superSaiyanBlue, .ultraInstinct].contains(form) {
                let bench = SaiyanFaceBench()
                bench.face.skin = SIMD3(0.87, 0.68, 0.56)
                let out = play(bench, input, face: person.face(), frames: 40) { _ in Self.settled(form) }
                pictures.append(kept(out))
                guard !form.isBase else { continue }
                // The person's own hair, up to the top of their skull, is under the drawn hair.
                let skull = box(person.face(), -0.9, 1.3, 0.9, 1.95)
                XCTAssertGreaterThan(Double(changed(h.bitmap(out), from: plainReal, in: skull)) / Double(skull.width * skull.height), 0.6,
                                     "\(form) at \(io): the drawn hair hides the real hair")
            }
        }
        Output.save(SaiyanBench.sheet(pictures, columns: 6, scale: 0.34), as: "saiyan-face-sheet-real.png")
    }

    func testPosesRolledMouthOpenBlinkingNearAndFar() {
        var pictures: [CIImage] = []
        for form in [SaiyanForm.superSaiyan, .superSaiyan3, .superSaiyanGod, .ultraInstinct] {
            for s in [scene(roll: 0.5), scene(roll: -0.5, center: CGPoint(x: 560, y: 320)), scene(open: 1), scene(blink: 1), scene(brows: 1),
                      scene(scale: 0.5, center: CGPoint(x: 900, y: 300)), scene(scale: 1.6, center: CGPoint(x: 640, y: 560))] {
                let input = h.input(s)
                let bench = SaiyanFaceBench()
                bench.face.skin = SIMD3(0.93, 0.74, 0.62)
                pictures.append(kept(play(bench, input, face: s.face(), frames: 36) { _ in Self.settled(form) }))
            }
        }
        Output.save(SaiyanBench.sheet(pictures, columns: 7, scale: 0.3), as: "saiyan-face-sheet-poses.png")
    }

    // MARK: Behind the person

    func testSuperSaiyan3HasLongHairBehindOnlyWithACutout() {
        let face = still.face()
        let besideNeck = box(face, 1.35, -1.9, 2.4, -0.9), otherSide = box(face, -2.4, -1.9, -1.35, -0.9)
        let bench = SaiyanFaceBench()
        let out = h.bitmap(play(bench, base, face: face, frames: 40) { _ in Self.settled(.superSaiyan3) })
        XCTAssertGreaterThan(changed(out, from: plain, in: besideNeck), 1500, "long hair falls beside the neck")
        XCTAssertGreaterThan(changed(out, from: plain, in: otherSide), 1500, "on both sides")
        // The face itself is in front of it.
        let cheek = point(face, 0.7, -0.6)
        XCTAssertEqual(out.pixel(cheek.0, cheek.1).r, plain.pixel(cheek.0, cheek.1).r, accuracy: 6, "the person stays in front of the long hair")
        // With no cutout there is nothing to put it behind, so it is left out.
        let camera = h.bitmap(base.camera)
        let bare = h.bitmap(play(SaiyanFaceBench(), base, face: face, frames: 40, matte: false) { _ in Self.settled(.superSaiyan3) })
        XCTAssertEqual(changed(bare, from: camera, in: besideNeck), 0, "no long hair without a cutout")
        XCTAssertGreaterThan(changed(bare, from: camera, in: box(face, -0.8, 1.7, 0.8, 2.4)), 2500, "the mane still shows")
        // Another form puts nothing there.
        let ssj = h.bitmap(play(SaiyanFaceBench(), base, face: face, frames: 40) { _ in Self.settled(.superSaiyan2) })
        XCTAssertEqual(changed(ssj, from: plain, in: besideNeck), 0)
    }

    func testTheLongHairTakesTheManesWashAllTheWayDown() throws {
        let face = still.face()
        let mane = box(face, -0.9, 1.4, 0.9, 2.6)
        // Measured from where the long hair hangs, on its own: high beside the head, and low, near the tips, below the shoulders.
        let pivot = Double(face.eyeCenter.y) + face.interocular
        let high = CGRect(x: 640 + 1.3 * 84, y: pivot - 2 * 84, width: 1.9 * 84, height: 84)
        let low = CGRect(x: 640 + 1.3 * 84, y: pivot - 4.6 * 84, width: 1.9 * 84, height: 0.9 * 84)
        func hair(_ bits: Bitmap, _ rect: CGRect) throws -> SIMD3<Double> {
            var sum = SIMD3<Double>(0, 0, 0), n = 0.0
            for x in Int(rect.minX)..<Int(rect.maxX) { for y in Int(max(0, rect.minY))..<Int(rect.maxY) {
                let p = bits.pixel(x, y)
                guard abs(p.r - 128) + abs(p.g - 128) + abs(p.b - 128) > 30 else { continue }
                sum += SIMD3(Double(p.r), Double(p.g), Double(p.b)) / 255; n += 1
            } }
            XCTAssertGreaterThan(n, 200, "long hair in \(rect)")
            return n > 0 ? sum / n : SIMD3(0, 0, 0)
        }
        func red(_ c: SIMD3<Double>) -> Double { c.x - c.y }
        for gpu in [true, false] {
            let bench = SaiyanFaceBench(gpu: gpu)
            let calmFront = h.bitmap(play(bench, base, face: face, frames: 30) { _ in Self.settled(.superSaiyan3) })
            let calmBack = h.bitmap(try XCTUnwrap(bench.back(base)))
            // Powering up toward God, then the flash: each time the mane and every part of the long hair move the same way.
            var charging = Self.settled(.superSaiyan3)
            charging.charge = 0.9
            let chargedFront = h.bitmap(play(bench, base, face: face, frames: 20) { _ in charging })
            let chargedBack = h.bitmap(try XCTUnwrap(bench.back(base)))
            let lift = [red(try hair(chargedBack, high)) - red(try hair(calmBack, high)), red(try hair(chargedBack, low)) - red(try hair(calmBack, low))]
            let maneLift = red(try XCTUnwrap(meanChanged(chargedFront, from: plain, in: mane))) - red(try XCTUnwrap(meanChanged(calmFront, from: plain, in: mane)))
            XCTAssertGreaterThan(lift[0], 0.05, "gpu \(gpu): the long hair glows toward God's crimson too")
            XCTAssertEqual(lift[0], lift[1], accuracy: 0.045, "gpu \(gpu): as much near the tips as beside the head: \(lift)")
            XCTAssertEqual(lift[0], maneLift, accuracy: 0.06, "gpu \(gpu): and as much as the mane (\(maneLift))")
            var flash = Self.settled(.superSaiyan3)
            flash.flash = 1
            play(bench, base, face: face, frames: 1) { _ in flash }
            let blazed = h.bitmap(try XCTUnwrap(bench.back(base)))
            // How far each part went toward the flash's white: the same share everywhere, whatever it started from.
            let core = simd_reduce_add(SaiyanForm.superSaiyan3.palette.auraCore)
            let share = try [high, low].map { rect -> Double in
                let before = simd_reduce_add(try hair(calmBack, rect)), after = simd_reduce_add(try hair(blazed, rect))
                return (after - before) / (core - before)
            }
            XCTAssertGreaterThan(share[0], 0.3, "gpu \(gpu): the flash blazes the long hair")
            XCTAssertEqual(share[0], share[1], accuracy: 0.06, "gpu \(gpu): all the way down: \(share)")
            if gpu { Output.save(play(bench, base, face: face, frames: 1) { _ in charging }, as: "saiyan-face-ssj3-charging-long-hair.png") }
        }
    }

    // MARK: Changing form

    func testANewFormSpringsUpWithAnOvershootWhileItsColourCrossesOver() throws {
        let face = still.face()
        let column = box(face, -0.15, 1.0, 0.15, 3.6)
        let bench = SaiyanFaceBench()
        play(bench, base, face: face, frames: 20) { _ in Self.settled(.base) }
        var growths: [Double] = [], pictures: [CIImage] = [], tops: [Double: Int] = [:]
        // The body's change runs over 0.7 s (21 frames) with the flash falling over 0.6 s.
        for i in 0...36 {
            var s = Self.settled(.superSaiyan)
            s.previousForm = .base
            s.transition = min(1, Double(i) / 21)
            s.flash = max(0, 1 - Double(i) / 18)
            let out = play(bench, base, face: face, frames: 1) { _ in s }
            growths.append(bench.face.hair.growth)
            if let stop = [0: 0.0, 4: 0.2, 10: 0.5, 36: 1.0][i] {
                pictures.append(kept(out))
                tops[stop] = top(h.bitmap(out), column) ?? 0
            }
        }
        Output.save(SaiyanBench.sheet(pictures, columns: 4, scale: 0.4), as: "saiyan-face-change-base-ssj.png")
        XCTAssertLessThan(growths[0], 0.35, "it starts small")
        XCTAssertGreaterThan(growths.max() ?? 0, 1.06, "it shoots past full size")
        XCTAssertEqual(growths.last ?? 0, 1, accuracy: 0.005, "and settles")
        for (a, b) in zip(growths, growths.dropFirst()) { XCTAssertLessThan(abs(b - a), 0.35, "no jumps") }
        XCTAssertLessThan(tops[0.2] ?? 0, tops[0.5] ?? 0, "the hair is still rising at 0.2 of the change")

        // Super Saiyan 3 to God: gold to crimson, the long hair drawing back.
        var transition: [CIImage] = []
        let god = SaiyanFaceBench()
        play(god, base, face: face, frames: 20) { _ in Self.settled(.superSaiyan3) }
        let hairBox = box(face, -0.9, 1.4, 0.9, 2.4)
        var redness: [Double] = []
        for i in 0...24 {
            var s = Self.settled(.superSaiyanGod)
            s.previousForm = .superSaiyan3
            s.transition = min(1, Double(i) / 21)
            let out = play(god, base, face: face, frames: 1) { _ in s }
            if [0, 4, 10, 24].contains(i) {
                transition.append(kept(out))
                let m = try XCTUnwrap(meanChanged(h.bitmap(out), from: plain, in: hairBox))
                redness.append(m.x - m.y)
            }
        }
        Output.save(SaiyanBench.sheet(transition, columns: 4, scale: 0.4), as: "saiyan-face-change-ssj3-god.png")
        XCTAssertGreaterThan(redness.last ?? 0, (redness.first ?? 0) + 0.25, "the hair crosses from gold to crimson: \(redness)")
        XCTAssertFalse(god.face.drawsBehind, "and the long hair is gone")
    }

    func testPoweringDownCollapsesTheHairAndLeavesNothing() {
        let face = still.face()
        let bench = SaiyanFaceBench()
        play(bench, base, face: face, frames: 20) { _ in Self.settled(.superSaiyanBlue) }
        var pictures: [CIImage] = []
        for i in 0...30 {
            var s = Self.settled(.base)
            s.previousForm = .superSaiyanBlue
            s.transition = min(1, Double(i) / 21)
            let out = play(bench, base, face: face, frames: 1) { _ in s }
            if [0, 7, 14, 30].contains(i) { pictures.append(kept(out)) }
            if i == 30 { XCTAssertEqual(h.bitmap(out).change(from: plain, in: base.rect), 0, "back to your own hair") }
        }
        Output.save(SaiyanBench.sheet(pictures, columns: 4, scale: 0.4), as: "saiyan-face-power-down.png")
    }

    // MARK: Powering up

    func testPoweringUpTremblesLiftsAndGlowsTowardTheNextForm() throws {
        let face = still.face()
        let hairBox = box(face, -0.9, 1.4, 0.9, 2.6)
        let bench = SaiyanFaceBench()
        let calm = h.bitmap(play(bench, base, face: face, frames: 30) { _ in Self.settled(.superSaiyan3) })
        var pictures: [CIImage] = [], last: Bitmap?
        var moving = 0
        for i in 0..<36 {
            var s = Self.settled(.superSaiyan3)
            s.charge = min(0.9, Double(i) / 36)
            let out = play(bench, base, face: face, frames: 1) { _ in s }
            if i % 12 == 11 { pictures.append(kept(out)) }
            if i >= 30 {
                let bits = h.bitmap(out)
                if let last { moving = max(moving, changed(bits, from: last, in: hairBox, threshold: 30)) }
                last = bits
            }
        }
        Output.save(SaiyanBench.sheet(pictures, columns: 3, scale: 0.4), as: "saiyan-face-charge-ssj3.png")
        XCTAssertGreaterThan(bench.face.hair.trembling, 0.5)
        XCTAssertGreaterThan(moving, 150, "the hair trembles from frame to frame")
        let charged = try XCTUnwrap(last)
        let a = try XCTUnwrap(meanChanged(calm, from: plain, in: hairBox)), b = try XCTUnwrap(meanChanged(charged, from: plain, in: hairBox))
        XCTAssertGreaterThan(b.x - b.y, a.x - a.y + 0.08, "Super Saiyan 3 glows toward God's crimson: \(a) to \(b)")
        let column = box(face, -0.15, 1.0, 0.15, 4.4)
        XCTAssertGreaterThan(top(charged, column) ?? 0, top(calm, column) ?? 0, "and the hair stands taller")

        // In base the Super Saiyan hair flickers in before the first change.
        let first = SaiyanFaceBench()
        var flickered = 0
        for i in 0..<40 {
            var s = Self.settled(.base)
            s.charge = min(1, Double(i) / 30)
            let out = play(first, base, face: face, frames: 1) { _ in s }
            if i % 4 == 0 { flickered = max(flickered, changed(h.bitmap(out), from: plain, in: hairBox)) }
        }
        XCTAssertGreaterThan(flickered, 3000, "the hair flickers gold while the first charge fills")
    }

    func testTheFlashBlazes() throws {
        let face = still.face()
        let hairBox = box(face, -0.9, 1.4, 0.9, 2.4)
        let bench = SaiyanFaceBench()
        let calm = h.bitmap(play(bench, base, face: face, frames: 30) { _ in Self.settled(.superSaiyan) })
        var s = Self.settled(.superSaiyan)
        s.flash = 1
        let blaze = h.bitmap(play(bench, base, face: face, frames: 1) { _ in s })
        let a = try XCTUnwrap(meanChanged(calm, from: plain, in: hairBox)), b = try XCTUnwrap(meanChanged(blaze, from: plain, in: hairBox))
        XCTAssertGreaterThan(b.x + b.y + b.z, a.x + a.y + a.z + 0.25, "the flash lights the hair white-hot")
    }

    // MARK: Eyes and brows

    func testIrisesAreRecolouredUnderTheRealLids() {
        let bench = SaiyanFaceBench()
        let face = still.face()
        let (ex, ey) = point(face, 0.5, 0)
        let teal = h.bitmap(play(bench, base, face: face, frames: 30) { _ in Self.settled(.superSaiyan) }).pixel(ex + 4, ey - 4)
        XCTAssertGreaterThan(teal.g, teal.r + 40, "Super Saiyan's irises are teal, got \(teal)")
        XCTAssertGreaterThan(teal.b, teal.r + 40)
        // Shut eyes: the lid closes over the iris.
        let shut = scene(blink: 1).face()
        let closed = h.bitmap(play(bench, h.input(scene(blink: 1)), face: shut, frames: 4) { _ in Self.settled(.superSaiyan) })
        let plainShut = h.bitmap(h.input(scene(blink: 1)).composed)
        XCTAssertLessThan(changed(closed, from: plainShut, in: box(shut, 0.35, -0.04, 0.65, 0.04), threshold: 60), 6, "no iris over a shut eye")
        // God's are red, Ultra Instinct's silver.
        let red = h.bitmap(play(SaiyanFaceBench(), base, face: face, frames: 30) { _ in Self.settled(.superSaiyanGod) }).pixel(ex + 4, ey - 4)
        XCTAssertGreaterThan(red.r, red.g + 60, "God's irises are red, got \(red)")
        let silver = h.bitmap(play(SaiyanFaceBench(), base, face: face, frames: 30) { _ in Self.settled(.ultraInstinct) }).pixel(ex + 4, ey - 4)
        XCTAssertGreaterThan(silver.r + silver.g + silver.b, 480, "Ultra Instinct's irises are silver, got \(silver)")
    }

    func testBrowsFollowTheRealOnesAndSuperSaiyan3BaresThem() {
        func isGold(_ p: RGB) -> Bool { p.r > 200 && p.g > 140 && p.b < 110 }
        func gold(_ bits: Bitmap, _ rect: CGRect) -> Int {
            var n = 0
            for x in Int(rect.minX)..<Int(rect.maxX) { for y in Int(rect.minY)..<Int(rect.maxY) where isGold(bits.pixel(x, y)) { n += 1 } }
            return n
        }
        let rest = scene()
        let restBits = h.bitmap(play(SaiyanFaceBench(), base, face: rest.face(), frames: 30) { _ in Self.settled(.superSaiyan) })
        let (bx, by) = point(rest.face(), 0.72, 0.42)
        XCTAssertTrue(isGold(restBits.pixel(bx, by)), "a golden brow over the real one, got \(restBits.pixel(bx, by))")
        // Raised, on a head with a real forehead (the cartoon's hairline sits on its brows), the brow moves up out of where it rests.
        var person = HeadwearRealHead()
        let calm = h.bitmap(play(SaiyanFaceBench(), person.input(services: h.services), face: person.face(), frames: 30) { _ in Self.settled(.superSaiyan) })
        person.browRaise = 0.6
        let lifted = h.bitmap(play(SaiyanFaceBench(), person.input(services: h.services), face: person.face(), frames: 30) { _ in Self.settled(.superSaiyan) })
        let resting = box(HeadwearRealHead().face(), 0.45, 0.4, 0.75, 0.5), above = box(HeadwearRealHead().face(), 0.45, 0.58, 0.75, 0.72)
        XCTAssertGreaterThan(gold(lifted, above), gold(calm, above) + 60, "the brows lift with the real ones")
        XCTAssertLessThan(gold(lifted, resting), gold(calm, resting) - 60)
        // Super Saiyan 3: no gold brow there, the real brow covered with skin.
        let bench = SaiyanFaceBench()
        bench.face.skin = SIMD3(0.93, 0.74, 0.62)
        let bare = h.bitmap(play(bench, base, face: rest.face(), frames: 30) { _ in Self.settled(.superSaiyan3) })
        let (sx, sy) = point(rest.face(), 0.72, 0.4)
        let skin = bare.pixel(sx, sy)
        XCTAssertFalse(isGold(skin), "Super Saiyan 3 has no brows, got \(skin)")
        XCTAssertGreaterThan(skin.r, 170, "the real brow is under skin, got \(skin)")
        XCTAssertGreaterThan(skin.r, skin.b + 40)
        let (rx, ry) = point(rest.face(), 0.5, 0.4)
        XCTAssertGreaterThan(bare.pixel(rx, ry).r, plain.pixel(rx, ry).r + 60, "where the real brow was dark, it is skin now")
    }

    // MARK: Robustness

    func testFollowsATiltedHeadAndAFaceAtTheTop() {
        for roll in [0.5, -0.5] {
            let s = scene(roll: roll)
            let out = h.bitmap(play(SaiyanFaceBench(), h.input(s), face: s.face(), frames: 30) { _ in Self.settled(.superSaiyan) })
            let plainTilt = h.bitmap(h.input(s).composed)
            XCTAssertGreaterThan(changed(out, from: plainTilt, in: box(s.face(), -0.3, 1.8, 0.3, 2.4)), 1200, "roll \(roll): the hair follows up the tilted face")
        }
        let high = scene(center: CGPoint(x: 640, y: 640))
        let input = h.input(high)
        let out = h.bitmap(play(SaiyanFaceBench(), input, face: high.face(), frames: 30) { _ in Self.settled(.superSaiyan3) })
        let plainHigh = h.bitmap(input.composed)
        XCTAssertGreaterThan(changed(out, from: plainHigh, in: CGRect(x: 440, y: 700, width: 400, height: 20)), 2000, "spikes run off the top")
        XCTAssertEqual(changed(out, from: plainHigh, in: CGRect(x: 0, y: 0, width: 1280, height: 120)), 0, "and nothing strays below")
    }

    func testWildHeadsNeverRunAway() {
        let bench = SaiyanFaceBench()
        var generator = SystemRandomNumberGenerator()
        for i in 0..<240 {
            let lost = i % 50 > 44
            let s = scene(roll: Double.random(in: -0.6...0.6, using: &generator), open: Double(i % 3) / 2,
                          blink: i % 7 == 0 ? 1 : 0, scale: Double.random(in: 0.4...1.6, using: &generator),
                          center: CGPoint(x: Double.random(in: 200...1080, using: &generator), y: Double.random(in: 150...650, using: &generator)))
            let forms = SaiyanForm.allCases
            var state = Self.settled(forms[(i / 20) % forms.count])
            state.previousForm = forms[max(0, (i / 20) % forms.count - 1)]
            state.transition = Double(i % 20) / 14
            state.charge = Double(i % 11) / 10
            state.flash = i % 20 == 0 ? 1 : 0
            let dt = [0, 1.0 / 30, 0.1, 0.4][i % 4]
            let input = frame(base, face: lost ? nil : s.face(), time: Double(i) / 30, dt: dt)
            _ = bench.render(input, state)
            for x in bench.face.hair.springs { XCTAssertTrue(x.isFinite && abs(x) <= 0.61, "a spring ran away: \(x)") }
            XCTAssertTrue(bench.face.hair.growth.isFinite)
        }
        let out = play(bench, base, face: still.face(), frames: 30) { _ in Self.settled(.ultraInstinct) }
        let mean = h.average(out, base.rect)
        XCTAssertTrue(mean.r.isFinite && mean.g.isFinite && mean.b.isFinite)
    }

    func testALostFaceFadesTheHairAndABriefBlipKeepsIt() {
        let face = still.face()
        let bench = SaiyanFaceBench()
        play(bench, base, face: face, frames: 30) { _ in Self.settled(.superSaiyan2) }
        let hairBox = box(face, -0.8, 1.6, 0.8, 2.4)
        let gone1 = h.bitmap(play(bench, base, face: nil, frames: 3) { _ in Self.settled(.superSaiyan2) })
        XCTAssertGreaterThan(changed(gone1, from: plain, in: hairBox), 1500, "a blip keeps the hair, fading")
        let gone = h.bitmap(play(bench, base, face: nil, frames: 12) { _ in Self.settled(.superSaiyan2) })
        XCTAssertEqual(gone.change(from: plain, in: base.rect), 0, "gone after a moment")
        // When the face comes back the hair springs back up rather than popping in.
        play(bench, base, face: nil, frames: 30) { _ in Self.settled(.superSaiyan2) }
        play(bench, base, face: face, frames: 2) { _ in Self.settled(.superSaiyan2) }
        XCTAssertLessThan(bench.face.hair.growth, 0.7, "arriving, it starts small")
        play(bench, base, face: face, frames: 30) { _ in Self.settled(.superSaiyan2) }
        XCTAssertEqual(bench.face.hair.growth, 1, accuracy: 0.01)
    }

    func testTheGraphicsChipAndThePainterLayTheSameHair() {
        let face = still.face()
        let a = h.bitmap(play(SaiyanFaceBench(gpu: true), base, face: face, frames: 30) { _ in Self.settled(.superSaiyanBlue) })
        let b = h.bitmap(play(SaiyanFaceBench(gpu: false), base, face: face, frames: 30) { _ in Self.settled(.superSaiyanBlue) })
        let area = box(face, -2, -0.6, 2, 3.4)
        let differ = changed(a, from: b, in: area, threshold: 90)
        XCTAssertLessThan(Double(differ) / Double(area.width * area.height), 0.01, "the two ways of laying the hair agree (\(differ) pixels differ)")
    }

    // MARK: Cost

    func testCostUnderBudget() {
        let face = still.face()
        func measure(_ form: SaiyanForm, gpu: Bool, charge: Bool) -> Double {
            let bench = SaiyanFaceBench(gpu: gpu)
            play(bench, base, face: face, frames: 45) { _ in Self.settled(form) }
            var times: [Double] = []
            for i in 0..<90 {
                var s = scene(roll: 0.08 * sin(Double(i) * 0.2), center: CGPoint(x: 640 + 30 * sin(Double(i) * 0.3), y: 330))
                s.scale = 1
                var state = Self.settled(form)
                if charge { state.charge = 0.2 + 0.7 * Double(i) / 90 }
                let started = CFAbsoluteTimeGetCurrent()
                let input = frame(base, face: s.face(), time: Double(bench.frame) / 30)
                // Only the face's own work: the rig, the springs, both layers and the hair picture. Core Image composes later, on the chip.
                _ = bench.render(input, state)
                times.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
            }
            return times.reduce(0, +) / Double(times.count)
        }
        var report: [String] = []
        for form in [SaiyanForm.superSaiyan, .superSaiyan3, .ultraInstinct] {
            let steady = measure(form, gpu: true, charge: false), charging = measure(form, gpu: true, charge: true)
            let painted = measure(form, gpu: false, charge: false)
            report.append(String(format: "%@: %.2f ms steady, %.2f ms charging (hair painted on the processor: %.2f ms)", "\(form)", steady, charging, painted))
            // Generous: the machine is shared. The budget is 1.5 ms.
            XCTAssertLessThan(steady, 3, "\(form) steady")
            XCTAssertLessThan(charging, 4, "\(form) charging")
            XCTAssertLessThan(painted, 8, "\(form) painted")
        }
        let idle = SaiyanFaceBench()
        play(idle, base, face: face, frames: 10) { _ in Self.settled(.base) }
        let started = CFAbsoluteTimeGetCurrent()
        play(idle, base, face: face, frames: 60) { _ in Self.settled(.base) }
        let baseCost = (CFAbsoluteTimeGetCurrent() - started) * 1000 / 60
        report.append(String(format: "base: %.2f ms", baseCost))
        print("SAIYAN FACE COST " + report.joined(separator: " | "))
    }
}
