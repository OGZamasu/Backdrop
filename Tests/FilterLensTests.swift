import CoreImage
import XCTest

/// Shared setup for lens tests: a compositor, services, and a synthetic person, built once.
/// Pixels of a picture, addressed like Core Image does: y counts up from the bottom.
struct Bitmap {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    func pixel(_ x: Int, _ y: Int) -> RGB {
        guard x >= 0, x < width, y >= 0, y < height else { return (0, 0, 0) }
        let i = ((height - 1 - y) * width + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    /// The biggest change in any pixel (sum over red, green and blue) between two pictures, within a region.
    func change(from other: Bitmap, in rect: CGRect) -> Int {
        var worst = 0
        for x in Int(max(0, rect.minX))..<Int(min(Double(width), rect.maxX)) {
            for y in Int(max(0, rect.minY))..<Int(min(Double(height), rect.maxY)) {
                let a = pixel(x, y), b = other.pixel(x, y)
                worst = max(worst, abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b))
            }
        }
        return worst
    }
}

final class LensHarness {
    let compositor = Compositor()
    let services: LensServices
    let grid = MatteGrid(outputSize: SyntheticScene.size)
    let ciContext: CIContext

    init() {
        ciContext = compositor.context
        services = LensServices(context: compositor.context, size: SyntheticScene.size)
    }

    func input(_ scene: SyntheticScene = SyntheticScene(), time: Double = 0, dt: Double = 1.0 / 30, background: Bool = true, wantsGrid: Bool = true,
               hands: [HandState] = []) -> LensInput {
        var made = scene.input(time: time, dt: dt, services: services, compositor: compositor, grid: wantsGrid ? grid : nil,
                               background: background ? SyntheticScene.backdrop() : nil)
        made.hands = hands
        return made
    }

    /// The same frame at another moment, without redrawing the scene.
    func at(_ base: LensInput, time: Double, dt: Double = 1.0 / 30, hands: [HandState]? = nil) -> LensInput {
        LensInput(time: time, dt: dt, rect: base.rect, camera: base.camera, matte: base.matte, background: base.background,
                  composed: base.composed, matteGrid: base.matteGrid, face: base.face, services: base.services, hands: hands ?? base.hands)
    }

    func average(_ image: CIImage, _ rect: CGRect) -> (r: Double, g: Double, b: Double) {
        let area = image.cropped(to: rect).applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
        var px = [Float](repeating: 0, count: 4)
        ciContext.render(area, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: TestSupport.srgb)
        return (Double(px[0]), Double(px[1]), Double(px[2]))
    }

    func pixel(_ image: CIImage, _ x: Int, _ y: Int) -> RGB { TestSupport.pixel(image, x: x, y: y, context: ciContext) }

    /// A picture read out now. Lens pictures are lazy and share drawing buffers, so anything compared later has to be captured first.
    func bitmap(_ image: CIImage) -> Bitmap {
        let rect = compositor.rect
        let width = Int(rect.width), height = Int(rect.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        ciContext.render(image, toBitmap: &bytes, rowBytes: width * 4, bounds: rect, format: .RGBA8, colorSpace: TestSupport.srgb)
        return Bitmap(width: width, height: height, bytes: bytes)
    }

    /// Mean and worst milliseconds to make and actually render a frame.
    func cost(of lens: Lens, base: LensInput, frames: Int = 90) -> (mean: Double, worst: Double) {
        let buffer = compositor.makeOutputBuffer()!
        var durations: [Double] = []
        for i in 0..<frames {
            let started = CFAbsoluteTimeGetCurrent()
            compositor.render(lens.render(at(base, time: Double(i) / 30)), into: buffer)
            durations.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
        }
        return (durations.reduce(0, +) / Double(frames), durations.max() ?? 0)
    }
}

final class FilterLensTests: XCTestCase {
    private let h = LensHarness()

    private func diff(_ a: RGB, _ b: RGB) -> Int { abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) }

    // MARK: Aura

    func testAuraGlowsAroundTheOutlineAndLeavesYouAndTheRoomAlone() throws {
        for (style, name) in [(AuraLens.Style.power, "aura-power.png"), (.rainbow, "aura-rainbow.png")] {
            let lens = AuraLens(style: style)
            let base = h.input()
            var out = base.composed
            for i in 0..<30 { out = lens.render(h.at(base, time: Double(i) / 30)) }
            Output.save(out, as: name)

            // 25 px outside the side of the head: the halo.
            let halo = h.pixel(out, 760, 420), plain = h.pixel(base.composed, 760, 420)
            XCTAssertGreaterThan(diff(halo, plain), 60, "\(style): there should be a glow just outside you")
            if style == .power { XCTAssertGreaterThan(halo.r, halo.b + 40, "and it should be warm, got \(halo)") }
            XCTAssertLessThan(diff(h.pixel(out, 640, 400), h.pixel(base.composed, 640, 400)), 6, "your face is untouched")
            XCTAssertLessThan(diff(h.pixel(out, 40, 680), h.pixel(base.composed, 40, 680)), 20, "far from you, the room is untouched")
            XCTAssertGreaterThan(lens.sparkCount, 20, "sparks should be rising by now")
        }
    }

    func testAuraWithNoBackdropStillGlowsOverTheRoom() {
        let lens = AuraLens(style: .power)
        let base = h.input(background: false)
        var out = base.composed
        for i in 0..<10 { out = lens.render(h.at(base, time: Double(i) / 30)) }
        XCTAssertGreaterThan(diff(h.pixel(out, 760, 420), h.pixel(base.composed, 760, 420)), 40)
    }

    // MARK: Ghost trails

    func testGhostTrailsLingerWhereYouWereThenFade() {
        let lens = GhostTrailsLens()
        let still = h.input(SyntheticScene(center: CGPoint(x: 400, y: 420)))
        var out = still.composed
        for i in 0..<10 { out = lens.render(h.at(still, time: Double(i) / 30)) }
        let before = h.pixel(out, 400, 420)

        // Step sideways. Where the head was, the room should be visible, and an echo too.
        let moved = h.input(SyntheticScene(center: CGPoint(x: 900, y: 420)))
        out = lens.render(h.at(moved, time: 0.4))
        Output.save(out, as: "trails-just-moved.png")
        XCTAssertGreaterThan(diff(h.pixel(out, 400, 420), h.pixel(moved.composed, 400, 420)), 40, "an echo is left where your head was")
        XCTAssertLessThan(diff(h.pixel(out, 900, 420), h.pixel(moved.composed, 900, 420)), 8, "while you yourself are drawn normally")
        _ = before

        for i in 0..<60 { out = lens.render(h.at(moved, time: 0.5 + Double(i) / 30)) }
        XCTAssertLessThan(diff(h.pixel(out, 400, 420), h.pixel(moved.composed, 400, 420)), 25, "two seconds later the echo has faded away")
    }

    func testTheFirstFrameHasNoGhost() {
        let lens = GhostTrailsLens()
        let base = h.input()
        let out = lens.render(h.at(base, time: 0))
        XCTAssertLessThan(diff(h.pixel(out, 400, 420), h.pixel(base.composed, 400, 420)), 8)
    }

    // MARK: Plain filters

    func testComicDrawsInkAndChangesThePicture() {
        let base = h.input()
        let out = ComicLens().render(base)
        Output.save(out, as: "comic.png")
        XCTAssertEqual(out.extent, base.rect)
        XCTAssertGreaterThan(diff(h.pixel(out, 640, 300), h.pixel(base.composed, 640, 300)), 15)
        var darkest = 255
        for x in stride(from: 540, to: 740, by: 2) { let p = h.pixel(out, x, 460); darkest = min(darkest, min(p.r, p.g, p.b)) }
        XCTAssertLessThan(darkest, 40, "the outlines should be inked in near-black")
    }

    func testPixelArtMakesFlatBlocks() {
        let base = h.input()
        let out = PixelArtLens(block: 14).render(base)
        Output.save(out, as: "pixel.png")
        // The grid is anchored at the origin, so x 140...153 is one block.
        XCTAssertLessThan(diff(h.pixel(out, 141, 101), h.pixel(out, 151, 109)), 6, "a block is a single colour")
        let colours = Set([100, 300, 500, 650].flatMap { y in stride(from: 7, to: 1280, by: 14).map { x -> Int in let p = h.pixel(out, x, y); return p.r * 65536 + p.g * 256 + p.b } })
        XCTAssertGreaterThan(colours.count, 3, "and blocks across a row take different colours")
        XCTAssertEqual(out.extent, base.rect)
    }

    func testMirrorGivesYouATwin() {
        let base = h.input()
        let out = MirrorLens().render(base)
        Output.save(out, as: "mirror.png")
        for (x, y) in [(200, 300), (100, 500), (560, 400)] {
            XCTAssertLessThan(diff(h.pixel(out, x, y), h.pixel(out, 1280 - 1 - x, y)), 8, "the right half mirrors the left at \(x)")
        }
        XCTAssertLessThan(diff(h.pixel(out, 200, 300), h.pixel(base.composed, 200, 300)), 4, "and the left half is as it was")
    }

    func testKaleidoscopeTurnsThePicture() {
        let base = h.input()
        let lens = KaleidoscopeLens()
        let a = lens.render(h.at(base, time: 0)), b = lens.render(h.at(base, time: 3))
        Output.save(b, as: "kaleidoscope.png")
        XCTAssertEqual(a.extent, base.rect)
        XCTAssertGreaterThan(diff(h.pixel(a, 300, 300), h.pixel(base.composed, 300, 300)), 5)
        XCTAssertGreaterThan(diff(h.pixel(a, 300, 300), h.pixel(b, 300, 300)) + diff(h.pixel(a, 900, 500), h.pixel(b, 900, 500)), 10, "it turns as time passes")
    }

    // MARK: Glitch

    func testGlitchBurstsComeAndGoAtIrregularTimes() {
        let samples = stride(from: 0.0, to: 120.0, by: 1.0 / 30).map { GlitchPlan.burst(at: $0) }
        XCTAssertTrue(samples.allSatisfy { $0 >= 0 && $0 <= 1 })
        let active = Double(samples.filter { $0 > 0.05 }.count) / Double(samples.count)
        XCTAssertGreaterThan(active, 0.04, "it glitches now and then")
        XCTAssertLessThan(active, 0.35, "but not all the time")
        XCTAssertEqual(GlitchPlan.burst(at: 12.34), GlitchPlan.burst(at: 12.34), "the same moment always glitches the same way")
        XCTAssertTrue(GlitchPlan.tears(at: 5, burst: 0, height: 720).isEmpty)
        for tear in GlitchPlan.tears(at: 5, burst: 1, height: 720) {
            XCTAssertTrue((0...720).contains(tear.y) && tear.height >= 8 && abs(tear.shift) <= 160)
        }
    }

    func testGlitchBreaksTheColoursApartMostWhenBursting() throws {
        let base = h.input()
        let lens = GlitchLens()
        let burstTime = try XCTUnwrap(stride(from: 0.0, to: 60, by: 0.05).first { GlitchPlan.burst(at: $0) > 0.9 })
        let calmTime = try XCTUnwrap(stride(from: 0.0, to: 60, by: 0.05).first { GlitchPlan.burst(at: $0) == 0 })
        let burst = lens.render(h.at(base, time: burstTime)), calm = lens.render(h.at(base, time: calmTime))
        Output.save(burst, as: "glitch-burst.png"); Output.save(calm, as: "glitch-calm.png")
        func deviation(_ image: CIImage) -> Int {
            stride(from: 40, to: 1240, by: 37).reduce(0) { $0 + diff(h.pixel(image, $1, 360), h.pixel(base.composed, $1, 360)) + diff(h.pixel(image, $1, 600), h.pixel(base.composed, $1, 600)) }
        }
        XCTAssertGreaterThan(deviation(burst), deviation(calm) * 2, "the picture should be far more broken mid-burst")
        XCTAssertGreaterThan(deviation(calm), 0, "and never perfectly clean")
    }

    // MARK: Matrix

    func testMatrixRainFallsAndFadesBehindItsHead() {
        var rain = MatrixRain(columns: 10, rows: 28, glyphCount: 56, seed: 1)
        let before = rain.columns.map(\.head)
        rain.step(0.5)
        for (a, b) in zip(before, rain.columns.map(\.head)) { XCTAssertGreaterThan(b, a - 1e-9, "the code moves down") }
        let column = rain.columns.indices.first { rain.columns[$0].head > 12 && rain.columns[$0].head < 25 }
        if let c = column {
            let headRow = Int(rain.columns[c].head)
            XCTAssertEqual(rain.brightness(column: c, row: headRow), 1, accuracy: 1e-9, "the head is brightest")
            XCTAssertLessThan(rain.brightness(column: c, row: max(0, headRow - 5)), 1)
            XCTAssertEqual(rain.brightness(column: c, row: min(27, headRow + 2)), 0, "nothing ahead of the head")
        }
        for _ in 0..<2000 { rain.step(0.05) }
        XCTAssertTrue(rain.columns.allSatisfy { $0.head < Double(28 + 30) }, "columns recycle instead of falling forever")
    }

    func testMatrixTurnsEverythingGreenOverBlackWithRainBehindYou() {
        let lens = MatrixLens()
        let base = h.input()
        var out = base.composed
        for i in 0..<40 { out = lens.render(h.at(base, time: Double(i) / 30)) }
        Output.save(out, as: "matrix.png")
        let room = h.average(out, CGRect(x: 20, y: 20, width: 300, height: 300))
        XCTAssertGreaterThan(room.g, room.r * 2 + 0.005, "the room is green")
        let face = h.average(out, CGRect(x: 580, y: 380, width: 120, height: 80))
        XCTAssertGreaterThan(face.g, face.r, "and so is the person, got \(face)")
        XCTAssertGreaterThan(face.g, 0.15, "still clearly visible")
        var lit = 0
        for x in stride(from: 10, to: 300, by: 4) { for y in stride(from: 380, to: 700, by: 4) where h.pixel(out, x, y).g > 90 { lit += 1 } }
        XCTAssertGreaterThan(lit, 30, "there is code raining in the background")
    }

    // MARK: Snow

    func testSnowCatchesOnAPersonAndMelts() {
        var field = SnowField(size: SyntheticScene.size)
        let block = MatteGrid.filled([CGRect(x: 400, y: 100, width: 300, height: 300)], outputSize: SyntheticScene.size, cellSize: 4)
        for _ in 0..<300 { field.step(1.0 / 30, matte: block) }     // ten seconds
        XCTAssertGreaterThan(field.particles.particles.count, 200, "a steady snowfall")
        XCTAssertLessThan(field.particles.particles.count, 900)
        XCTAssertGreaterThan(field.landedCount, 3, "some has caught on the block")
        for p in field.particles.particles where p.kind == SnowField.restingKind {
            XCTAssertGreaterThan(block.coverage(x: p.position.x, y: p.position.y), 0.3, "a resting flake is on the block, at \(p.position)")
        }
        XCTAssertTrue(field.particles.particles.allSatisfy { $0.position.y > -10 }, "and the rest falls out of frame")
        // Take the block away: whatever was resting falls on.
        let away = MatteGrid(outputSize: SyntheticScene.size)
        field.step(1.0 / 30, matte: away)
        XCTAssertEqual(field.landedCount, 0, "with nothing there any more, nothing rests")
    }

    func testSnowRendersFlakesAndSettlesOnTheHead() {
        let lens = SnowLens()
        let base = h.input()
        var out = base.composed
        for i in 0..<300 { out = lens.render(h.at(base, time: Double(i) / 30)) }
        Output.save(out, as: "snow.png")
        XCTAssertGreaterThan(lens.flakeCount, 200)
        XCTAssertGreaterThan(lens.landedCount, 2, "flakes have settled on you")
        var white = 0
        for x in stride(from: 10, to: 400, by: 3) { for y in stride(from: 10, to: 700, by: 3) where min(h.pixel(out, x, y).r, h.pixel(out, x, y).g, h.pixel(out, x, y).b) > 215 { white += 1 } }
        XCTAssertGreaterThan(white, 15, "there are visible flakes in the room")
    }

    // MARK: Speed

    func testEveryFilterIsCheapEnough() {
        let base = h.input()
        let lenses: [(String, Lens)] = [("aura", AuraLens(style: .power)), ("trails", GhostTrailsLens()), ("comic", ComicLens()),
                                        ("pixel", PixelArtLens()), ("mirror", MirrorLens()), ("kaleidoscope", KaleidoscopeLens()),
                                        ("glitch", GlitchLens()), ("matrix", MatrixLens()), ("snow", SnowLens())]
        for (name, lens) in lenses {
            let cost = h.cost(of: lens, base: base)
            print(String(format: "LENS-COST %@ mean %.1f ms, worst %.1f ms", name, cost.mean, cost.worst))
            // Aura, the heaviest, is about 9 ms on a quiet Mac and 11 while the camera is live and the screen is busy, so this
            // catches a lens that has doubled in cost, not ordinary load.
            XCTAssertLessThan(cost.mean, 14, "\(name) averages \(Int(cost.mean)) ms a frame")
        }
    }
}
