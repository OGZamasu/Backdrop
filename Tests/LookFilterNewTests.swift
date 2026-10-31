import CoreImage
import XCTest

/// The ten looks added in round two, and the rebuilt comic, pixel art, mirror and kaleidoscope: what each does to the picture,
/// in numbers, and that each copes with nobody there.
final class LookFilterNewLookTests: XCTestCase {
    private let h = LensHarness()
    private let t0 = 5000.0

    private func diff(_ a: RGB, _ b: RGB) -> Int { abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) }

    private func lens(_ id: String) -> Lens {
        guard let info = LensCatalog.info(for: id) else { fatalError("no look \(id)") }
        return info.make()
    }

    /// Runs a look for `seconds`, so anything that eases or develops has settled.
    private func run(_ id: String, _ base: LensInput, seconds: Double = 3.5, steps: Int = 12) -> CIImage {
        let l = lens(id)
        var out = base.composed
        for i in 0...steps { out = l.render(h.at(base, time: t0 + seconds * Double(i) / Double(steps))) }
        return out.cropped(to: base.rect)
    }

    static let newIds = ["film-noir", "instant-photo", "super-eight", "blockbuster", "dreamy-glow", "golden-hour", "hologram", "stained-glass",
                         "watercolour", "blueprint"]

    func testEveryNewLookRendersFullSizeWithAndWithoutSomeone() {
        for id in Self.newIds {
            for state in [LookFixture.State.backdrop, .room, .empty] {
                let out = run(id, LookFixture.input(h, state), seconds: 1, steps: 3)
                XCTAssertEqual(out.extent, LookFixture.rect, "\(id) \(state)")
                let p = h.pixel(out, 640, 360)
                XCTAssertTrue(p.r + p.g + p.b > 0 || state == .empty, "\(id) \(state) is not blank")
            }
        }
    }

    // MARK: Film noir

    func testNoirIsBlackAndWhiteWithBarsOfLightOnTheWall() {
        let base = LookFixture.input(h, .room)
        let out = run("film-noir", base, seconds: 1)
        let picture = h.bitmap(out)
        for (x, y) in [(640, 420), (200, 600), (900, 500)] {
            let p = picture.pixel(x, y)
            XCTAssertLessThan(max(abs(p.r - p.g), abs(p.g - p.b)), 12, "grey at \(x),\(y): \(p)")
        }
        // Walking along a line across the light patch on the wall, the bars make it go light, dark, light.
        var levels: [Int] = []
        for i in 0..<130 { let p = picture.pixel(770 + i, 560 + i); levels.append(p.g) }
        XCTAssertGreaterThan((levels.max() ?? 0) - (levels.min() ?? 0), 30, "bars of light and shade on the wall, got \(levels)")
        let face = h.average(out, CGRect(x: 600, y: 380, width: 80, height: 60)), corner = h.average(out, CGRect(x: 0, y: 0, width: 120, height: 120))
        XCTAssertGreaterThan(face.g, corner.g * 3, "your face is lit, the corners are dark")
    }

    // MARK: Instant photo

    func testInstantPhotoDevelopsAndSitsInAWhiteFrame() {
        XCTAssertEqual(LookInstantPlan.developed(after: 0), 0)
        XCTAssertEqual(LookInstantPlan.developed(after: LookInstantPlan.developTime + 1), 1)
        var last = -1.0
        for t in stride(from: 0.0, to: 4, by: 0.1) { let d = LookInstantPlan.developed(after: t); XCTAssertGreaterThanOrEqual(d, last); last = d }
        let window = LookInstantPlan.window(in: LookFixture.rect)
        XCTAssertTrue(LookFixture.rect.contains(window))
        XCTAssertGreaterThan(window.minY - LookFixture.rect.minY, (LookFixture.rect.maxY - window.maxY) * 2, "a deep strip at the foot")

        let base = LookFixture.input(h, .backdrop)
        let photo = LookInstantLens(startDate: Date(timeIntervalSince1970: 1_000_000_000))
        let early = h.bitmap(photo.render(h.at(base, time: t0)).cropped(to: base.rect))
        let late = h.bitmap(photo.render(h.at(base, time: t0 + 4)).cropped(to: base.rect))
        let blank = early.pixel(640, 420)
        XCTAssertLessThan(abs(blank.r - blank.b), 20, "at first the photo is a blank blue-grey, got \(blank)")
        XCTAssertGreaterThan(diff(late.pixel(640, 420), blank), 40, "and then you appear")
        let card = late.pixel(12, 360)
        XCTAssertGreaterThan(min(card.r, card.g, card.b), 225, "the border is white card, got \(card)")
        let caption = LookInstantLens.caption(for: Date(timeIntervalSince1970: 1_000_000_000))
        XCTAssertNotNil(caption.range(of: "^Sep [89] '01$", options: .regularExpression), "scribbled like a date, got \(caption)")
        photo.restart()
        let again = h.bitmap(photo.render(h.at(base, time: t0 + 10)).cropped(to: base.rect))
        XCTAssertLessThan(diff(again.pixel(640, 420), blank), 30, "picking it again develops it again")
    }

    // MARK: Super 8

    func testSuperEightWeavesFlickersAndLeaksLightNowAndThen() {
        var leaking = 0
        for t in stride(from: 0.0, to: 140, by: 0.1) {
            let frame = LookSuperEightPlan.frame(at: t)
            let shake = LookSuperEightPlan.weave(frame: frame)
            XCTAssertTrue(abs(shake.dx) <= 1 && abs(shake.dy) <= 2.2)
            XCTAssertTrue((0.95...1.02).contains(LookSuperEightPlan.exposure(frame: frame)))
            if let leak = LookSuperEightPlan.leak(at: t) {
                leaking += 1
                XCTAssertTrue((0...1).contains(leak.strength) && (0..<1).contains(leak.place))
            }
        }
        let share = Double(leaking) / 1400
        XCTAssertGreaterThan(share, 0.08, "light leaks happen")
        XCTAssertLessThan(share, 0.5, "but not all the time")
        XCTAssertEqual(LookSuperEightPlan.leak(at: 33.3), LookSuperEightPlan.leak(at: 33.3))

        let base = LookFixture.input(h, .backdrop)
        let out = run("super-eight", base, seconds: 1)
        XCTAssertLessThan(h.pixel(out, 4, 4).r, 25, "the corner of the gate is dark")
        let face = h.average(out, CGRect(x: 600, y: 380, width: 80, height: 60))
        XCTAssertGreaterThan(face.r, face.b * 1.3, "warm film, got \(face)")
    }

    // MARK: Blockbuster

    func testBlockbusterSlidesInBarsAndGradesSkinWarmAndShadowsTeal() {
        XCTAssertEqual(LookBlockbusterPlan.barHeight(for: CGSize(width: 1280, height: 720)), (720 - 1280 / 2.2) / 2, accuracy: 0.01)
        XCTAssertEqual(LookBlockbusterPlan.barsIn(after: 0), 0)
        XCTAssertEqual(LookBlockbusterPlan.barsIn(after: 5), 1)
        XCTAssertGreaterThan(LookBlockbusterPlan.barsIn(after: 0.3), 0.5, "they come in quickly and land softly")
        let skin = LookBlockbusterLens.grade(SIMD3<Float>(0.86, 0.66, 0.55)), shadow = LookBlockbusterLens.grade(SIMD3<Float>(0.2, 0.2, 0.2))
        XCTAssertGreaterThan(skin.x - skin.z, 0.86 - 0.55, "skin warms, got \(skin)")
        XCTAssertGreaterThan(shadow.z, shadow.x + 0.05, "grey shadows go teal, got \(shadow)")
        XCTAssertGreaterThan(shadow.y, shadow.x + 0.03)

        let base = LookFixture.input(h, .room)
        let out = run("blockbuster", base, seconds: 2)
        let picture = h.bitmap(out)
        XCTAssertLessThan(picture.pixel(640, 715).g, 8, "a bar at the top")
        XCTAssertLessThan(picture.pixel(640, 4).g, 8, "and one at the bottom")
        XCTAssertGreaterThan(picture.pixel(640, 400).g, 60, "the picture between them")
        let early = h.bitmap(lens("blockbuster").render(h.at(base, time: t0)).cropped(to: base.rect))
        XCTAssertGreaterThan(early.pixel(640, 715).g, 20, "no bars the moment it is picked: they slide in")
    }

    // MARK: Dreamy

    func testDreamyLiftsTheShadowsGlowsAndFloatsLightsBehindYou() {
        let lights = LookDreamyPlan.lights(at: 12.3, size: SyntheticScene.size)
        XCTAssertEqual(lights.count, LookDreamyPlan.count)
        XCTAssertEqual(lights, LookDreamyPlan.lights(at: 12.3, size: SyntheticScene.size))
        for light in lights {
            XCTAssertTrue((-80...1360).contains(light.centre.x) && (-80...800).contains(light.centre.y))
            XCTAssertTrue((0...0.45).contains(light.alpha))
        }
        let later = LookDreamyPlan.lights(at: 12.3 + 1.0 / 30, size: SyntheticScene.size)
        for (a, b) in zip(lights, later) { XCTAssertLessThan(hypot(a.centre.x - b.centre.x, a.centre.y - b.centre.y), 5, "they drift, never jump") }

        let base = LookFixture.input(h, .backdrop)
        let out = run("dreamy-glow", base, seconds: 1)
        let darkest = h.average(out, CGRect(x: 1180, y: 20, width: 80, height: 80)), before = h.average(base.composed, CGRect(x: 1180, y: 20, width: 80, height: 80))
        XCTAssertGreaterThan(darkest.r + darkest.g + darkest.b, (before.r + before.g + before.b) * 1.15, "shadows are lifted")
    }

    // MARK: Golden hour

    func testGoldenHourWarmsThePictureFromTheUpperLeft() {
        let sun = LookGoldenHourPlan.sun(at: 7, size: SyntheticScene.size)
        XCTAssertLessThan(sun.x, 100); XCTAssertGreaterThan(sun.y, 650)
        let ghosts = LookGoldenHourPlan.ghosts(sun: sun, size: SyntheticScene.size)
        XCTAssertGreaterThan(ghosts.count, 3)
        for ghost in ghosts { XCTAssertGreaterThan(ghost.centre.x, sun.x, "the flare runs from the sun across the frame") }

        let base = LookFixture.input(h, .backdrop)
        let out = run("golden-hour", base, seconds: 1)
        let a = h.average(out, CGRect(x: 0, y: 0, width: 1280, height: 720)), b = h.average(base.composed, CGRect(x: 0, y: 0, width: 1280, height: 720))
        XCTAssertGreaterThan(a.r - a.b, b.r - b.b + 0.05, "warmer, got \(a) from \(b)")
        let near = h.average(out, CGRect(x: 0, y: 560, width: 160, height: 160)), far = h.average(out, CGRect(x: 1120, y: 0, width: 160, height: 160))
        XCTAssertGreaterThan(near.r, far.r, "brighter towards the sun")
    }

    // MARK: Hologram

    func testHologramTurnsYouBlueInADarkRoomAndStuttersRarely() {
        var slipping = 0
        for t in stride(from: 0.0, to: 120, by: 1.0 / 30) {
            if let slip = LookHologramPlan.slip(at: t, height: 720) { slipping += 1; XCTAssertTrue(abs(slip.shift) <= 18 && slip.height <= 60) }
            XCTAssertTrue((0.88...1.0).contains(LookHologramPlan.shimmer(at: t)), "a shimmer, never a strobe")
        }
        let share = Double(slipping) / (120 * 30)
        XCTAssertGreaterThan(share, 0.01); XCTAssertLessThan(share, 0.1)

        let base = LookFixture.input(h, .room)
        let out = run("hologram", base, seconds: 1)
        let face = h.average(out, CGRect(x: 600, y: 380, width: 80, height: 60))
        XCTAssertGreaterThan(face.b, face.r * 1.5, "blue light, got \(face)")
        let room = h.average(out, CGRect(x: 20, y: 600, width: 200, height: 100)), before = h.average(base.composed, CGRect(x: 20, y: 600, width: 200, height: 100))
        XCTAssertLessThan(room.r + room.g + room.b, (before.r + before.g + before.b) * 0.5, "the room is dark")
    }

    // MARK: Stained glass

    func testStainedGlassIsLeadedAndRicherInColour() {
        let base = LookFixture.input(h, .room)
        let out = run("stained-glass", base, seconds: 1)
        let picture = h.bitmap(out)
        var lead = 0
        for x in stride(from: 300, to: 900, by: 1) { let p = picture.pixel(x, 620); if max(p.r, p.g, p.b) < 45 { lead += 1 } }
        XCTAssertGreaterThan(lead, 15, "dark lead between the pieces")
        func saturation(_ c: (r: Double, g: Double, b: Double)) -> Double { max(c.r, c.g, c.b) - min(c.r, c.g, c.b) }
        let wall = h.average(out, CGRect(x: 300, y: 560, width: 200, height: 120)), before = h.average(base.composed, CGRect(x: 300, y: 560, width: 200, height: 120))
        XCTAssertGreaterThan(saturation(wall), saturation(before) * 1.4, "the plain wall becomes coloured glass")
    }

    // MARK: Watercolour

    func testWatercolourIsLighterAndFadesToPaperAtTheEdges() {
        let base = LookFixture.input(h, .backdrop)
        let out = run("watercolour", base, seconds: 1)
        let a = h.average(out, CGRect(x: 0, y: 0, width: 1280, height: 720)), b = h.average(base.composed, CGRect(x: 0, y: 0, width: 1280, height: 720))
        XCTAssertGreaterThan(a.r + a.g + a.b, (b.r + b.g + b.b) * 1.3, "transparent paint is lighter than a photo")
        let corner = h.pixel(out, 4, 4)
        XCTAssertGreaterThan(min(corner.r, corner.g, corner.b), 200, "bare paper in the corner, got \(corner)")
    }

    // MARK: Blueprint

    func testBlueprintIsWhiteLinesOnBlueWithDimensionsThatFollowYou() {
        let base = LookFixture.input(h, .backdrop)
        let out = run("blueprint", base, seconds: 1)
        let paper = h.pixel(out, 200, 300)
        XCTAssertGreaterThan(paper.b, paper.r + 60, "blueprint blue, got \(paper)")
        var white = 0
        for x in 530...760 { let p = h.pixel(out, x, 470); if min(p.r, p.g, p.b) > 170 { white += 1 } }
        XCTAssertGreaterThan(white, 3, "your outline is drawn in white")

        let head = try? XCTUnwrap(base.matteGrid.flatMap { LookHead.find(in: $0) })
        if let head {
            let d = LookBlueprintPlan.dimensions(for: head)
            XCTAssertEqual(d.headRight - d.headLeft, head.width, accuracy: 0.01)
            XCTAssertGreaterThan(d.side, d.headRight)
        }
        // With nobody there the dimension lines fade away.
        let empty = LookFixture.input(h, .empty)
        let l = lens("blueprint")
        for i in 0...10 { _ = l.render(h.at(base, time: t0 + Double(i) / 30)) }
        var gone = base.composed
        for i in 0...20 { gone = l.render(h.at(empty, time: t0 + 1 + Double(i) / 30)) }
        let span = h.bitmap(gone.cropped(to: base.rect))
        var marks = 0
        for x in 560...720 { let p = span.pixel(x, 592); if min(p.r, p.g, p.b) > 200 { marks += 1 } }
        XCTAssertLessThan(marks, 5, "no dimension line over an empty room")
    }

    // MARK: Older looks, rebuilt

    func testTheHeadIsFoundFromTheTopOfTheCutout() throws {
        let near = try XCTUnwrap(LookFixture.input(h, .backdrop).matteGrid.flatMap { LookHead.find(in: $0) })
        XCTAssertEqual(near.centre.x, 640, accuracy: 20)
        XCTAssertEqual(near.width, 200, accuracy: 30, "the head, not the shoulders")
        XCTAssertEqual(near.top, 558, accuracy: 16)
        let far = try XCTUnwrap(LookFixture.input(h, .far).matteGrid.flatMap { LookHead.find(in: $0) })
        XCTAssertEqual(far.width, 100, accuracy: 24, "a small head far away, got \(far.width)")
        XCTAssertNil(LookHead.find(in: MatteGrid(outputSize: SyntheticScene.size)))
    }

    func testMirrorMakesATwinThatFacesYou() {
        let base = LookFixture.input(h, .backdrop)
        let out = MirrorLens().render(base).cropped(to: base.rect)
        // You were in the middle; now you are a quarter of the way in, and so is your twin from the other side.
        XCTAssertLessThan(diff(h.pixel(out, 320, 420), h.pixel(base.composed, 640, 420)), 40, "you, slid left")
        XCTAssertLessThan(diff(h.pixel(out, 959, 420), h.pixel(out, 320, 420)), 10, "and your twin")
        XCTAssertGreaterThan(diff(h.pixel(out, 640, 420), h.pixel(base.composed, 640, 420)), 30, "the middle is backdrop now")
    }

    func testKaleidoscopeHasSixFoldSymmetry() {
        let base = LookFixture.input(h, .backdrop)
        let out = h.bitmap(KaleidoscopeLens().render(h.at(base, time: 0)).cropped(to: base.rect))
        var worst = 0
        for (r, a) in [(200.0, 0.3), (150.0, 1.1), (260.0, 2.0)] {
            let p = out.pixel(Int(640 + r * cos(a)), Int(360 + r * sin(a))), q = out.pixel(Int(640 + r * cos(a + .pi / 3)), Int(360 + r * sin(a + .pi / 3)))
            worst = max(worst, diff(p, q))
        }
        XCTAssertLessThan(worst, 60, "turning by a sixth of a circle gives the same pattern")
    }

    func testPixelArtUsesOnlyItsPalette() {
        let base = LookFixture.input(h, .room)
        let out = h.bitmap(PixelArtLens().render(base).cropped(to: base.rect))
        let palette = PixelArtLens.palette.map { (Int(($0.r * 255).rounded()), Int(($0.g * 255).rounded()), Int(($0.b * 255).rounded())) }
        var off = 0, total = 0
        for x in stride(from: 7, to: 1280, by: 28) {
            for y in stride(from: 7, to: 720, by: 28) {
                let p = out.pixel(x, y)
                total += 1
                if !palette.contains(where: { abs($0.0 - p.r) + abs($0.1 - p.g) + abs($0.2 - p.b) < 8 }) { off += 1 }
            }
        }
        XCTAssertLessThan(Double(off) / Double(total), 0.02, "every block is a palette colour")
    }

    func testComicHasAPanelBorderAndInkedFeatures() {
        let base = LookFixture.input(h, .room)
        let out = h.bitmap(ComicLens().render(base).cropped(to: base.rect))
        let gutter = out.pixel(5, 360)
        XCTAssertGreaterThan(min(gutter.r, gutter.g, gutter.b), 220, "a paper gutter round the panel")
        XCTAssertLessThan(out.pixel(14, 360).g, 40, "inside a black panel line")
        var ink = 0
        for x in 580...700 { for y in 430...450 where max(out.pixel(x, y).r, out.pixel(x, y).g, out.pixel(x, y).b) < 60 { ink += 1 } }
        XCTAssertGreaterThan(ink, 20, "the eyes are inked")
    }

    func testGlitchBlocksStayOnTheGridAndInsideTheFrame() {
        for t in stride(from: 0.0, to: 30, by: 0.05) {
            let burst = GlitchPlan.burst(at: t)
            for block in GlitchPlan.blocks(at: t, burst: burst, size: SyntheticScene.size) {
                XCTAssertEqual(block.rect.minX.truncatingRemainder(dividingBy: 16), 0)
                XCTAssertTrue(CGRect(origin: .zero, size: SyntheticScene.size).contains(block.rect))
            }
        }
        XCTAssertTrue(GlitchPlan.blocks(at: 3, burst: 0.1, size: SyntheticScene.size).isEmpty, "a calm picture has no broken blocks")
    }

    func testMatrixIsCheapToMakeAndBakesItsGlyphsOnTheFirstFrame() {
        let started = CFAbsoluteTimeGetCurrent()
        let lens = MatrixLens()
        XCTAssertLessThan((CFAbsoluteTimeGetCurrent() - started) * 1000, 15, "making the lens on the main thread is quick")
        let out = lens.render(h.input()).cropped(to: LookFixture.rect)
        XCTAssertEqual(out.extent, LookFixture.rect)
        XCTAssertNotNil(GlyphAtlas.image(glyph: 3))
    }
}
