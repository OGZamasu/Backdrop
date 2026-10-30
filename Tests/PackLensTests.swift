import CoreImage
import XCTest

/// Renders lens folders over the synthetic person and checks what ends up on screen.
final class PackLensRenderTests: XCTestCase {
    private let h = LensHarness()
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("backdrop-pack-render-\(UUID().uuidString)", isDirectory: true)

    override func setUpWithError() throws { try SampleLenses.install(into: folder) }
    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func pack(_ name: String) throws -> LensPack { try LensPack.load(from: folder.appendingPathComponent(name + ".backdroplens")) }

    /// Runs a lens for a second of video at a steady scene and returns the last frame as pixels, and as a picture saved for looking at.
    private func run(_ lens: Lens, scene: SyntheticScene, seconds: Double = 1.2, save: String? = nil) -> Bitmap {
        let frame = h.input(scene)
        var out = frame.composed
        for i in 0..<Int(seconds * 30) { out = lens.render(h.at(frame, time: Double(i) / 30)) }
        if let save { Output.save(out, as: save) }
        return h.bitmap(out)
    }

    private func plain(_ scene: SyntheticScene) -> Bitmap { h.bitmap(h.input(scene).composed) }

    private func isGold(_ p: RGB) -> Bool { p.r > 200 && p.g > 150 && p.b < 130 }
    private func isRed(_ p: RGB) -> Bool { p.r > 170 && p.g < 90 && p.b < 100 }

    func testHaloAndHornsAnswerToASmileAndRaisedBrows() throws {
        let pack = try pack("Halo and Horns")
        let still = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let above = CGRect(x: 500, y: 380 + 150, width: 280, height: 120)      // over the head
        let forehead = CGRect(x: 580, y: 380 + 90, width: 120, height: 50)          // where the horns go, below the halo

        let calm = run(PackLens(pack), scene: still, save: "pack-halo-calm.png")
        XCTAssertEqual(calm.change(from: plain(still), in: above), 0, "no smile, no halo")
        XCTAssertEqual(calm.change(from: plain(still), in: forehead), 0, "and no horns")

        var smiling = still; smiling.smile = 1
        let smile = run(PackLens(pack), scene: smiling, save: "pack-halo-smile.png")
        XCTAssertTrue((Int(above.minX)..<Int(above.maxX)).contains { x in (Int(above.minY)..<Int(above.maxY)).contains { isGold(smile.pixel(x, $0)) } }, "a gold ring over the head")
        XCTAssertEqual(smile.change(from: plain(smiling), in: forehead), 0, "but still no horns")

        var surprised = still; surprised.browRaise = 1
        let brows = run(PackLens(pack), scene: surprised, save: "pack-horns.png")
        XCTAssertTrue((Int(forehead.minX)..<Int(forehead.maxX)).contains { x in (Int(forehead.minY)..<Int(forehead.maxY)).contains { isRed(brows.pixel(x, $0)) } }, "red horns on the forehead")
        // Mirrored: red on both sides of the middle.
        let left = (580..<640).contains { x in (Int(forehead.minY)..<Int(forehead.maxY)).contains { isRed(brows.pixel(x, $0)) } }
        let right = (640..<700).contains { x in (Int(forehead.minY)..<Int(forehead.maxY)).contains { isRed(brows.pixel(x, $0)) } }
        XCTAssertTrue(left && right, "a horn on each side")
    }

    func testHeartEyesSitOnBothEyesAndFollowATiltedHead() throws {
        let pack = try pack("Heart Eyes")
        var tilted = SyntheticScene(center: CGPoint(x: 640, y: 380)); tilted.roll = 0.5
        let straight = SyntheticScene(center: CGPoint(x: 640, y: 380))
        for (scene, name) in [(straight, "pack-hearts.png"), (tilted, "pack-hearts-tilted.png")] {
            let bits = run(PackLens(pack), scene: scene, save: name)
            let face = scene.face()
            for eye in [face.leftEye, face.rightEye] {
                let region = CGRect(x: eye.x - 30, y: eye.y - 30, width: 60, height: 60)
                XCTAssertGreaterThan(bits.change(from: plain(scene), in: region), 200, "something is drawn over the eye at \(eye)")
            }
        }
    }

    func testGoldenHourNeedsNoFaceAndChangesTheWholePicture() throws {
        let lens = PackLens(try pack("Golden Hour"))
        XCTAssertTrue(lens.needs.isEmpty)
        let scene = SyntheticScene()
        let base = h.input(scene)
        let lonely = LensInput(time: 0, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: nil, background: nil, composed: base.composed,
                               matteGrid: nil, face: nil, services: base.services)
        Output.save(lens.render(lonely), as: "pack-golden-hour.png")
        let out = h.bitmap(lens.render(lonely)), before = h.bitmap(base.composed)
        // Warmer: more red than blue than before, in the middle of the room.
        let a = out.pixel(200, 600), b = before.pixel(200, 600)
        XCTAssertGreaterThan(a.r - a.b, b.r - b.b, "tinted warm")
        XCTAssertGreaterThan(out.change(from: before, in: CGRect(x: 100, y: 100, width: 50, height: 50)), 5)
        XCTAssertNil(lens.status, "nothing to say about a face")
    }

    func testBubblesComeFromAnOpenMouthOnly() throws {
        let pack = try pack("Bubble Talk")
        var shut = SyntheticScene(center: CGPoint(x: 640, y: 440)); shut.mouthOpen = 0
        var open = shut; open.mouthOpen = 1
        let quiet = PackLens(pack)
        _ = run(quiet, scene: shut)
        XCTAssertEqual(quiet.particleCount, 0)
        let blowing = PackLens(pack)
        _ = run(blowing, scene: open, save: "pack-bubbles.png")
        XCTAssertGreaterThan(blowing.particleCount, 3)
        blowing.restart()
        XCTAssertEqual(blowing.particleCount, 0)
    }

    func testNameTagIsPinnedToThePictureNotTheFace() throws {
        let lens = PackLens(try pack("Name Tag"))
        XCTAssertTrue(lens.needs.isEmpty)
        let scene = SyntheticScene(center: CGPoint(x: 300, y: 420))
        let bits = run(lens, scene: scene, save: "pack-name-tag.png")
        XCTAssertTrue((560..<720).contains { x in (20..<130).contains { isRed(bits.pixel(x, $0)) } }, "a red tag at the bottom middle of the picture")
        var elsewhere = scene; elsewhere.center = CGPoint(x: 900, y: 420)
        let moved = run(PackLens(try pack("Name Tag")), scene: elsewhere)
        XCTAssertEqual(bits.pixel(640, 60).r, moved.pixel(640, 60).r, accuracy: 2, "it doesn't move when the person does")
    }

    func testPicturesAreDrawnWhereTheyAreAnchoredAndMirroredOnRequest() throws {
        let dir = folder.appendingPathComponent("Stickers.backdroplens", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        { "format": 1, "name": "Stickers", "layers": [
          { "type": "image", "image": "blue.png", "anchor": "cheekLeft", "size": 0.5 },
          { "type": "image", "image": "green.png", "anchor": "forehead", "offset": [0.7, 0], "size": 0.4, "mirror": true } ] }
        """.write(to: dir.appendingPathComponent("lens.json"), atomically: true, encoding: .utf8)
        let maker = ScratchPNG()
        maker.write("blue.png", in: dir, red: 0, green: 0, blue: 1)
        maker.write("green.png", in: dir, red: 0, green: 1, blue: 0)

        let scene = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let face = scene.face(), frame = FaceFrame(face)
        let bits = run(PackLens(try LensPack.load(from: dir)), scene: scene, save: "pack-stickers.png")
        let cheek = frame.pixel(frame.local(.cheekLeft))
        XCTAssertGreaterThan(bits.pixel(Int(cheek.x), Int(cheek.y)).b, 220, "a blue sticker on the left cheek")
        let forehead = frame.pixel(SIMD2(0.7, 0.95)), mirrored = frame.pixel(SIMD2(-0.7, 0.95))
        XCTAssertGreaterThan(bits.pixel(Int(forehead.x), Int(forehead.y)).g, 220, "a green one on the forehead")
        XCTAssertGreaterThan(bits.pixel(Int(mirrored.x), Int(mirrored.y)).g, 220, "and its twin on the other side")
    }

    func testThingsFadeInAndOutOverTheirFadeTime() throws {
        let dir = folder.appendingPathComponent("Fade.backdroplens", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        { "format": 1, "name": "Fade", "layers": [
          { "type": "shape", "shape": "rect", "color": "#FF0000", "anchor": "eyes", "size": 0.8, "width": 2,
            "show": { "when": "smile", "above": 0.5, "fade": 0.5 } } ] }
        """.write(to: dir.appendingPathComponent("lens.json"), atomically: true, encoding: .utf8)
        let lens = PackLens(try LensPack.load(from: dir))
        var smiling = SyntheticScene(center: CGPoint(x: 640, y: 380)); smiling.smile = 1
        let frame = h.input(smiling)
        // Over the skin, a red rectangle takes the green out of the picture, so green says how much of it is showing.
        func green(after frames: Int) -> Int {
            var out = frame.composed
            for i in 0..<frames { out = lens.render(h.at(frame, time: Double(i) / 30)) }
            return h.bitmap(out).pixel(640, 400).g
        }
        let early = green(after: 3)           // 0.1 s into a 0.5 s fade
        let late = green(after: 30)           // a second later
        XCTAssertGreaterThan(early, late + 60, "still fading in at 0.1 s (green \(early) then \(late))")
        XCTAssertLessThan(late, 30, "fully there once the fade is over")
    }

    func testAnimationsMoveThingsOverTime() throws {
        let dir = folder.appendingPathComponent("Bob.backdroplens", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        { "format": 1, "name": "Bob", "layers": [
          { "type": "shape", "shape": "circle", "color": "#FF0000", "anchor": "headTop", "size": 0.4,
            "animate": { "kind": "bob", "speed": 1, "amount": 0.6 } } ] }
        """.write(to: dir.appendingPathComponent("lens.json"), atomically: true, encoding: .utf8)
        let lens = PackLens(try LensPack.load(from: dir))
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let frame = h.input(scene)
        func topOfRed(at time: Double) -> Int {
            // Warm up the fade, then look at this moment.
            for i in 0..<10 { _ = lens.render(h.at(frame, time: time + Double(i) * 0.001)) }
            let bits = h.bitmap(lens.render(h.at(frame, time: time + 0.01)))
            return (300..<720).last { y in isRed(bits.pixel(640, y)) } ?? -1
        }
        let up = topOfRed(at: 0.25), down = topOfRed(at: 0.75)       // a quarter and three quarters of the way round
        XCTAssertGreaterThan(up, down + 20, "the circle rises and falls (\(up) vs \(down))")
    }

    func testAFaceLensShowsNothingWhenThereIsNoFace() throws {
        let lens = PackLens(try pack("Heart Eyes"))
        let base = h.input()
        let lonely = LensInput(time: 0, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: nil, background: nil, composed: base.composed,
                               matteGrid: nil, face: nil, services: base.services)
        for _ in 0..<20 { _ = lens.render(lonely) }
        XCTAssertEqual(h.bitmap(lens.render(lonely)).change(from: h.bitmap(base.composed), in: base.rect), 0)
        XCTAssertEqual(lens.status?.title, "Looking for your face…")
    }

    func testWarpsBendTheFace() throws {
        let dir = folder.appendingPathComponent("Warp.backdroplens", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        { "format": 1, "name": "Warp", "warps": [
          { "kind": "bulge", "anchor": "leftEye", "radius": 0.6, "strength": 0.8 },
          { "kind": "pinch", "anchor": "mouth", "radius": 0.7, "strength": 0.8, "show": { "when": "mouthOpen", "above": 0.5 } } ] }
        """.write(to: dir.appendingPathComponent("lens.json"), atomically: true, encoding: .utf8)
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let face = scene.face()
        let bits = run(PackLens(try LensPack.load(from: dir)), scene: scene, save: "pack-warp.png")
        XCTAssertGreaterThan(bits.change(from: plain(scene), in: CGRect(x: face.leftEye.x - 40, y: face.leftEye.y - 25, width: 80, height: 50)), 60, "the left eye bulges")
        XCTAssertEqual(bits.change(from: plain(scene), in: CGRect(x: face.mouth.x - 60, y: face.mouth.y - 40, width: 120, height: 80)), 0, "the mouth warp waits for an open mouth")
    }

    func testMirrorFlipsAcrossTheFaceNotJustTheOffset() throws {
        let dir = folder.appendingPathComponent("Twins.backdroplens", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        { "format": 1, "name": "Twins", "layers": [
          { "type": "shape", "shape": "rect", "color": "#00FF00", "anchor": "leftEye", "size": 0.3, "width": 0.3, "mirror": true } ] }
        """.write(to: dir.appendingPathComponent("lens.json"), atomically: true, encoding: .utf8)
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let face = scene.face()
        let bits = run(PackLens(try LensPack.load(from: dir)), scene: scene)
        func isGreen(_ p: CGPoint) -> Bool { let c = bits.pixel(Int(p.x), Int(p.y)); return c.g > 220 && c.r < 60 }
        XCTAssertTrue(isGreen(face.leftEye), "one on the left eye")
        XCTAssertTrue(isGreen(face.rightEye), "and its twin on the right eye, the other side of the face")
    }

    func testADropInLayerDoesNotJumpWhenItStartsToFadeOut() throws {
        let dir = folder.appendingPathComponent("Drop.backdroplens", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        { "format": 1, "name": "Drop", "layers": [
          { "type": "shape", "shape": "rect", "color": "#00FF00", "anchor": "headTop", "size": 0.3, "width": 0.6,
            "animate": { "kind": "dropIn" }, "show": { "when": "browRaise", "above": 0.5, "fade": 0.4 } } ] }
        """.write(to: dir.appendingPathComponent("lens.json"), atomically: true, encoding: .utf8)
        let lens = PackLens(try LensPack.load(from: dir))
        var up = SyntheticScene(center: CGPoint(x: 640, y: 380)); up.browRaise = 1
        let calm = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let raised = h.input(up), relaxed = h.input(calm)
        for i in 0..<45 { _ = lens.render(h.at(raised, time: Double(i) / 30)) }             // landed
        func greenRow(_ bits: Bitmap) -> Int? { (200..<720).last { y in let c = bits.pixel(640, y); return c.g > 200 && c.r < 80 && c.b < 80 } }
        let before = greenRow(h.bitmap(lens.render(h.at(raised, time: 1.5))))
        let first = greenRow(h.bitmap(lens.render(h.at(relaxed, time: 1.53))))              // the first frame of fading out
        let later = greenRow(h.bitmap(lens.render(h.at(relaxed, time: 1.56))))
        XCTAssertNotNil(before)
        if let before, let first { XCTAssertEqual(first, before, accuracy: 6, "it stays where it was while it fades (\(before) then \(first))") }
        if let before, let later { XCTAssertEqual(later, before, accuracy: 6) }
    }

    func testTheGreediestPossibleLensStaysWithinItsParticleBudgetAndTime() throws {
        let dir = folder.appendingPathComponent("Greedy.backdroplens", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let emitters = (0..<20).map { _ in "{ \"preset\": \"fire\", \"rate\": 50, \"size\": 50 }" }.joined(separator: ",")
        try "{ \"format\": 1, \"name\": \"Greedy\", \"emitters\": [\(emitters)] }".write(to: dir.appendingPathComponent("lens.json"), atomically: true, encoding: .utf8)
        let lens = PackLens(try LensPack.load(from: dir))
        var open = SyntheticScene(center: CGPoint(x: 640, y: 420)); open.mouthOpen = 1
        let frame = h.input(open)
        var worst = 0
        for i in 0..<120 { _ = lens.render(h.at(frame, time: Double(i) / 30)); worst = max(worst, lens.particleCount) }
        XCTAssertLessThanOrEqual(worst, 6 * 80 + 1, "six emitters share a fixed budget of particles (\(worst))")
    }

    func testTheExampleLensesAreCheapToRun() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BACKDROP_PERF"] != nil, "a timing test; set TEST_RUNNER_BACKDROP_PERF=1")
        let busy = SyntheticScene(center: CGPoint(x: 640, y: 420), mouthOpen: 1, browRaise: 1, smile: 1)
        let base = h.input(busy)
        for sample in SampleLenses.all {
            let lens = PackLens(try pack(String(sample.folder.dropLast(".backdroplens".count))))
            let cost = h.cost(of: lens, base: base, frames: 45)
            print(String(format: "PACK-COST %@ mean %.1f ms, worst %.1f ms", sample.folder as NSString, cost.mean, cost.worst))
            XCTAssertLessThan(cost.mean, 14, "\(sample.folder) averages \(Int(cost.mean)) ms a frame")
        }
    }

    func testEveryEmitterPresetDrawsSomething() throws {
        for preset in PackEmitter.Preset.allCases {
            let dir = folder.appendingPathComponent("E-\(preset.rawValue).backdroplens", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "{ \"format\": 1, \"name\": \"\(preset.rawValue)\", \"emitters\": [ { \"preset\": \"\(preset.rawValue)\", \"anchor\": \"mouth\" } ] }"
                .write(to: dir.appendingPathComponent("lens.json"), atomically: true, encoding: .utf8)
            let scene = SyntheticScene(center: CGPoint(x: 640, y: 420))
            let lens = PackLens(try LensPack.load(from: dir))
            let bits = run(lens, scene: scene, seconds: 1.0, save: "pack-emitter-\(preset.rawValue).png")
            XCTAssertGreaterThan(lens.particleCount, 0, "\(preset)")
            XCTAssertGreaterThan(bits.change(from: plain(scene), in: CGRect(x: 0, y: 0, width: 1280, height: 720)), 60, "\(preset) is visible")
        }
    }
}

/// Writes plain-colour PNGs for tests.
private struct ScratchPNG {
    func write(_ name: String, in folder: URL, red: Double, green: Double, blue: Double) {
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
    }
}
