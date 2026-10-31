import CoreImage
import XCTest

// MARK: - Shared setup

/// The sample lenses installed into a scratch Lenses folder the way Backdrop does it on first run, and a way to render them over the
/// synthetic person. Pictures are saved (when BACKDROP_TEST_OUTPUT is set) so the lenses can be looked at, not just measured.
/// Shared with the tests of the newer samples (SampleLensFreshTests).
final class SampleLensRig {
    let h = LensHarness()
    let folder: URL
    let packs: [LensPack]
    let everything = CGRect(x: 0, y: 0, width: 1280, height: 720)
    static let expressions: [PackSignal] = [.smile, .browRaise, .mouthOpen, .blink]
    /// Two renderings of the same scene can differ by a few levels (the cut-out edge is refined on the GPU), so "no difference" allows for that.
    static let noise = 12

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("backdrop-sample-lenses-\(UUID().uuidString)", isDirectory: true)
        try SampleLenses.install(into: folder)
        packs = LensPackFolder.scan(folder).packs
    }

    deinit { try? FileManager.default.removeItem(at: folder) }

    func pack(_ name: String) throws -> LensPack { try XCTUnwrap(packs.first { $0.name == name }, "no sample called \(name)") }

    /// A person in the middle of the picture, with these readings turned all the way up.
    static func scene(_ signals: Set<PackSignal> = [], center: CGPoint = CGPoint(x: 640, y: 390), scale: Double = 1, roll: Double = 0) -> SyntheticScene {
        SyntheticScene(center: center, scale: scale, roll: roll, mouthOpen: signals.contains(.mouthOpen) ? 1 : 0,
                       browRaise: signals.contains(.browRaise) ? 1 : 0, blink: signals.contains(.blink) ? 1 : 0, smile: signals.contains(.smile) ? 1 : 0)
    }

    /// The picture with no lens on it.
    func plain(_ scene: SyntheticScene) -> Bitmap { h.bitmap(h.input(scene).composed) }

    /// Runs a lens for a second and a half of steady video and returns the last frame, with the lens (to count its particles).
    @discardableResult
    func render(_ pack: LensPack, _ scene: SyntheticScene, face: Bool = true, frames: Int = 45, save: String? = nil) -> (bits: Bitmap, lens: PackLens, picture: CIImage) {
        var frame = h.input(scene)
        if !face {
            frame = LensInput(time: 0, dt: 1.0 / 30, rect: frame.rect, camera: frame.camera, matte: frame.matte, background: frame.background,
                              composed: frame.composed, matteGrid: frame.matteGrid, face: nil, services: frame.services)
        }
        let lens = PackLens(pack)
        var out = frame.composed
        for i in 0..<frames { out = lens.render(h.at(frame, time: Double(i) / 30)) }
        if let save { Output.save(out, as: "samplelens-\(Self.slug(pack.name))-\(save).png") }
        return (h.bitmap(out), lens, out)
    }

    static func slug(_ name: String) -> String { name.lowercased().replacingOccurrences(of: " ", with: "-") }

    // MARK: What a lens listens to

    /// Whether a trigger switches its part on when the reading goes up (a `below` on its own switches it on when the reading is low).
    static func reveals(_ t: PackTrigger) -> Bool { t.above != nil || t.below == nil }

    /// Every expression a lens reads, for switching things on or off.
    static func readings(of pack: LensPack) -> Set<PackSignal> {
        let triggers = pack.layers.map(\.show) + pack.warps.map(\.show) + pack.emitters.map(\.show)
        return Set(triggers.map(\.signal)).intersection(expressions)
    }

    /// The lens without whatever this expression switches on.
    static func removing(_ signal: PackSignal, from pack: LensPack) -> LensPack {
        var copy = pack
        copy.layers.removeAll { $0.show.signal == signal && reveals($0.show) }
        copy.warps.removeAll { $0.show.signal == signal && reveals($0.show) }
        copy.emitters.removeAll { $0.show.signal == signal && reveals($0.show) }
        return copy
    }

    // MARK: Looking at pixels

    func found(_ bits: Bitmap, in rect: CGRect, where test: (RGB) -> Bool) -> Bool {
        for x in stride(from: Int(max(0, rect.minX)), to: Int(min(1280, rect.maxX)), by: 2) {
            for y in stride(from: Int(max(0, rect.minY)), to: Int(min(720, rect.maxY)), by: 2) where test(bits.pixel(x, y)) { return true }
        }
        return false
    }

    /// Mean of red + green + blue over a patch, so "lighter" and "darker" are one number.
    func brightness(_ bits: Bitmap, in rect: CGRect) -> Double {
        var total = 0.0, count = 0.0
        for x in stride(from: Int(rect.minX), to: Int(rect.maxX), by: 4) {
            for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: 4) {
                let p = bits.pixel(x, y)
                total += Double(p.r + p.g + p.b); count += 1
            }
        }
        return total / max(1, count)
    }

    static func isRed(_ p: RGB) -> Bool { p.r > 200 && p.g < 90 && p.b < 100 }
    static func isGold(_ p: RGB) -> Bool { p.r > 220 && p.g > 150 && p.b < 110 }
    static func isNearWhite(_ p: RGB) -> Bool { p.r > 225 && p.g > 225 && p.b > 225 }
}

// MARK: - The files

final class SampleLensFormatTests: XCTestCase {
    private var rig: SampleLensRig!

    override func setUpWithError() throws { rig = try SampleLensRig() }

    private static let originalFive = ["Halo and Horns", "Heart Eyes", "Golden Hour", "Bubble Talk", "Name Tag"]

    func testThereAreThirtyAndTheFirstFiveAreStillThere() {
        XCTAssertEqual(SampleLenses.all.count, 30)
        XCTAssertEqual(SampleLenses.all.prefix(5).map(\.folder), Self.originalFive.map { $0 + ".backdroplens" })
        XCTAssertEqual(SampleLenses.originalFolders, Self.originalFive.map { $0 + ".backdroplens" }, "a library set up by the first versions is told apart by these")
        XCTAssertEqual(rig.packs.count, SampleLenses.all.count)
    }

    func testEverySampleLoadsWithNoWarningsOrProblems() {
        let (packs, problems) = LensPackFolder.scan(rig.folder)
        XCTAssertEqual(problems, [], "every sample must load")
        XCTAssertEqual(packs.count, SampleLenses.all.count)
        for pack in packs { XCTAssertEqual(pack.warnings, [], "\(pack.name) has warnings") }
    }

    func testNamesIdsFoldersAndGlyphsAreAllDifferent() {
        let packs = rig.packs
        XCTAssertEqual(Set(packs.map(\.name)).count, packs.count, "names")
        XCTAssertEqual(Set(packs.map(\.id)).count, packs.count, "ids")
        XCTAssertEqual(Set(SampleLenses.all.map(\.folder)).count, SampleLenses.all.count, "folders")
        XCTAssertEqual(Set(packs.map(\.glyph)).count, packs.count, "each has a glyph of its own")
        let builtIn = Set(LensCatalog.all.map { $0.name.lowercased() })
        for pack in packs { XCTAssertFalse(builtIn.contains(pack.name.lowercased()), "\(pack.name) is also the name of a built-in lens") }
    }

    func testEverySampleHasANameGlyphDescriptionAndTags() throws {
        for sample in SampleLenses.all {
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(sample.json.utf8)) as? [String: Any], sample.folder)
            for key in ["name", "glyph", "description", "tags"] { XCTAssertNotNil(root[key], "\(sample.folder) has no \(key)") }
        }
        for pack in rig.packs {
            XCTAssertTrue((3...60).contains(pack.name.count), pack.name)
            XCTAssertEqual(pack.glyph.count, 1, "\(pack.name): the glyph is one emoji")
            XCTAssertEqual(pack.glyph.unicodeScalars.first?.properties.isEmoji, true, "\(pack.name): the glyph is an emoji")
            XCTAssertTrue((20...300).contains(pack.summary.count), "\(pack.name): a sentence saying what it does")
            XCTAssertNotEqual(pack.summary, "A lens from your Lenses folder.", "\(pack.name) has no description of its own")
            XCTAssertTrue((1...16).contains(pack.tags.count), "\(pack.name) tags")
            XCTAssertEqual(Set(pack.tags).count, pack.tags.count, "\(pack.name) repeats a tag")
        }
    }

    // MARK: The format's rules

    private static let colourSyntax = try! NSRegularExpression(pattern: "^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$")
    private static let top: Set<String> = ["format", "name", "author", "glyph", "description", "tags", "layers", "warps", "emitters", "look"]
    private static let layerKeys: Set<String> = ["type", "image", "emoji", "text", "shape", "color", "stroke", "strokeWidth", "anchor", "offset", "size", "width",
                                                 "rotation", "follow", "opacity", "blend", "mirror", "weight", "show", "animate"]
    private static let warpKeys: Set<String> = ["kind", "anchor", "offset", "radius", "strength", "show"]
    private static let emitterKeys: Set<String> = ["preset", "anchor", "offset", "show", "rate", "size"]
    private static let lookKeys: Set<String> = ["saturation", "contrast", "brightness", "hue", "vignette", "tint", "tintAmount"]
    private static let showKeys: Set<String> = ["when", "above", "below", "fade"]
    private static let animateKeys: Set<String> = ["kind", "speed", "amount"]

    /// What a part may say: only keys the format knows (a misspelt one is silently ignored by the reader), numbers inside the range the
    /// reader would otherwise quietly clamp, and colours the reader can parse.
    private func check(_ part: [String: Any], keys: Set<String>, ranges: [String: ClosedRange<Double>], label: String) {
        for key in part.keys { XCTAssertTrue(keys.contains(key), "\(label): “\(key)” is not something a lens can say") }
        for (key, range) in ranges {
            guard let value = part[key] else { continue }
            guard let number = value as? Double else { XCTFail("\(label): \(key) should be a number"); continue }
            XCTAssertTrue(range.contains(number), "\(label): \(key) \(number) is outside \(range)")
        }
        for key in ["color", "stroke", "tint"] {
            guard let colour = part[key] else { continue }
            guard let text = colour as? String else { XCTFail("\(label): \(key) should be text"); continue }
            XCTAssertNotNil(Self.colourSyntax.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), "\(label): “\(text)” isn't #RGB, #RRGGBB or #RRGGBBAA")
        }
        if let offset = part["offset"] {
            let pair = offset as? [Double]
            XCTAssertEqual(pair?.count, 2, "\(label): offset is [x, y]")
            XCTAssertTrue(pair?.allSatisfy { (-20.0...20.0).contains($0) } ?? false, "\(label): offset is out of range")
        }
        if let show = part["show"] as? [String: Any] {
            check(show, keys: Self.showKeys, ranges: ["above": 0...1, "below": 0...1, "fade": 0.01...3], label: label + " show")
            XCTAssertNotNil(show["when"], "\(label): show says when")
        }
        if let animate = part["animate"] as? [String: Any] {
            check(animate, keys: Self.animateKeys, ranges: ["speed": 0.05...10, "amount": 0...2], label: label + " animate")
        }
    }

    func testEverySampleKeepsToTheFormatsRulesAndLimits() throws {
        for sample in SampleLenses.all {
            let name = sample.folder
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(sample.json.utf8)) as? [String: Any], name)
            XCTAssertEqual(root["format"] as? Int, 1, "\(name): format 1")
            for key in root.keys { XCTAssertTrue(Self.top.contains(key), "\(name): “\(key)” is not a lens.json key") }
            XCTAssertLessThan(sample.json.utf8.count, LensPack.maxManifestBytes, name)

            let layers = root["layers"] as? [[String: Any]] ?? []
            let warps = root["warps"] as? [[String: Any]] ?? []
            let emitters = root["emitters"] as? [[String: Any]] ?? []
            XCTAssertLessThanOrEqual(layers.count, LensPack.maxLayers, "\(name) layers")
            XCTAssertLessThanOrEqual(warps.count, LensPack.maxWarps, "\(name) warps")
            XCTAssertLessThanOrEqual(emitters.count, LensPack.maxEmitters, "\(name) emitters")

            for (i, layer) in layers.enumerated() {
                let label = "\(name) layer \(i + 1)"
                check(layer, keys: Self.layerKeys, ranges: ["strokeWidth": 0.001...2, "size": 0.01...20, "width": 0.01...20, "opacity": 0...1, "weight": 0...1], label: label)
                XCTAssertNotEqual(layer["type"] as? String, "image", "\(label): a sample is a single file, so it has no pictures")
                XCTAssertLessThanOrEqual((layer["text"] as? String)?.count ?? 0, 80, "\(label) text")
                XCTAssertLessThanOrEqual((layer["emoji"] as? String)?.count ?? 0, LensPack.maxEmojiLength, "\(label) emoji")
            }
            for (i, warp) in warps.enumerated() {
                check(warp, keys: Self.warpKeys, ranges: ["radius": 0.05...5, "strength": 0...1], label: "\(name) warp \(i + 1)")
            }
            for (i, emitter) in emitters.enumerated() {
                check(emitter, keys: Self.emitterKeys, ranges: ["rate": 0.1...2, "size": 0.2...2], label: "\(name) emitter \(i + 1)")
            }
            if let look = root["look"] as? [String: Any] {
                check(look, keys: Self.lookKeys, ranges: ["saturation": 0...3, "contrast": 0.25...4, "brightness": -1...1, "hue": -360...360, "vignette": 0...2, "tintAmount": 0...1],
                      label: "\(name) look")
            }
        }
    }

    // MARK: Range

    func testTogetherTheSamplesShowOffTheWholeFormat() {
        let packs = rig.packs
        let layers = packs.flatMap(\.layers), warps = packs.flatMap(\.warps), emitters = packs.flatMap(\.emitters)

        let shapes = Set(layers.compactMap { layer -> PackShape? in if case .shape(let s) = layer.content { return s } else { return nil } })
        XCTAssertEqual(shapes, Set(PackShape.allCases), "every shape")
        XCTAssertTrue(layers.contains { if case .emoji = $0.content { return true } else { return false } }, "emoji")
        XCTAssertTrue(layers.contains { if case .text = $0.content { return true } else { return false } }, "text")
        XCTAssertEqual(Set(layers.compactMap { $0.animation?.kind }), Set(PackAnimationKind.allCases), "every animation")
        XCTAssertEqual(Set(layers.map(\.blend)), Set(PackBlend.allCases), "every blend")
        XCTAssertEqual(Set(emitters.map(\.preset)), Set(PackEmitter.Preset.allCases), "every emitter preset")
        XCTAssertEqual(Set(warps.map(\.kind)), Set(PackWarp.Kind.allCases), "bulge and pinch")
        let anchors = Set(layers.map(\.anchor) + warps.map(\.anchor) + emitters.map(\.anchor))
        XCTAssertEqual(anchors, Set(PackAnchor.allCases), "every anchor")
        let triggers = layers.map(\.show) + warps.map(\.show) + emitters.map(\.show)
        XCTAssertEqual(Set(triggers.map(\.signal)), Set(PackSignal.allCases), "every trigger")
        XCTAssertTrue(triggers.contains { $0.below != nil }, "a trigger that waits for a low reading")
        XCTAssertTrue(triggers.contains { $0.fade > 0.3 }, "a slow fade")

        XCTAssertTrue(layers.contains { $0.mirror }, "mirror")
        XCTAssertTrue(layers.contains { !$0.followsHead }, "an upright layer")
        XCTAssertTrue(layers.contains { $0.stroke != nil && $0.strokeWidth != nil }, "an outline")
        XCTAssertTrue(layers.contains { $0.opacity < 1 }, "opacity")
        XCTAssertTrue(layers.contains { $0.rotation != 0 }, "rotation")
        XCTAssertTrue(layers.contains { $0.weight != 0.8 }, "text weight")
        XCTAssertTrue(layers.contains { $0.width != $0.size }, "a width of its own")

        let looks = packs.map(\.look)
        XCTAssertTrue(looks.contains { $0.saturation != 1 }, "saturation")
        XCTAssertTrue(looks.contains { $0.contrast != 1 }, "contrast")
        XCTAssertTrue(looks.contains { $0.brightness != 0 }, "brightness")
        XCTAssertTrue(looks.contains { $0.hue != 0 }, "hue")
        XCTAssertTrue(looks.contains { $0.vignette > 0 }, "vignette")
        XCTAssertTrue(looks.contains { $0.tint != nil }, "tint")
    }

    func testEachSampleListensForTheExpressionsItsDescriptionPromises() {
        let expected: [String: Set<PackSignal>] = [
            "Halo and Horns": [.smile, .browRaise], "Heart Eyes": [.smile], "Golden Hour": [], "Bubble Talk": [.mouthOpen], "Name Tag": [],
            "Rockstar": [.smile, .mouthOpen], "Lovestruck": [.smile], "Brain Freeze": [.mouthOpen], "Sleepy Head": [.blink], "Superstar": [.smile],
            "Retro Arcade": [.smile, .browRaise, .mouthOpen], "Disco Fever": [.smile, .mouthOpen], "Chill Mode": [.smile], "On Air": [.mouthOpen],
            "Wizard Eyes": [.browRaise],
            "Neon Sign": [.smile], "Rainy Mood": [.smile], "Boss Mode": [.smile, .browRaise], "Birthday Party": [.smile],
            "Masked Hero": [.browRaise, .mouthOpen], "Kitty Face": [.smile, .mouthOpen], "Space Helmet": [.mouthOpen, .blink], "Pixel Shades": [.smile],
            "Bright Idea": [.browRaise], "Gold Medal": [.smile], "Winter Beanie": [.mouthOpen], "Neon Visor": [.browRaise, .mouthOpen],
            "Sheriff": [.smile, .mouthOpen], "Tropical Sunset": [.smile], "Anime Sparkle": [.smile],
        ]
        XCTAssertEqual(Set(expected.keys), Set(rig.packs.map(\.name)), "the table covers every sample")
        for pack in rig.packs { XCTAssertEqual(SampleLensRig.readings(of: pack), expected[pack.name], pack.name) }
        let all = rig.packs.flatMap { SampleLensRig.readings(of: $0) }
        XCTAssertEqual(Set(all), Set(SampleLensRig.expressions), "smile, raised eyebrows, an open mouth and a blink all do something")
    }
}

// MARK: - Rendering

final class SampleLensRenderTests: XCTestCase {
    private var rig: SampleLensRig!

    override func setUpWithError() throws { rig = try SampleLensRig() }

    func testEverySampleRendersAtFullSizeAtRestAndWithEachExpression() {
        for pack in rig.packs {
            let rest = rig.render(pack, SampleLensRig.scene(), save: "neutral")
            XCTAssertEqual(rest.picture.extent, rig.everything, "\(pack.name) at rest")
            for signal in SampleLensRig.readings(of: pack) {
                let on = rig.render(pack, SampleLensRig.scene([signal]), save: signal.rawValue)
                XCTAssertEqual(on.picture.extent, rig.everything, "\(pack.name) with \(signal)")
                XCTAssertGreaterThan(on.bits.change(from: rig.plain(SampleLensRig.scene([signal])), in: rig.everything), 40, "\(pack.name) with \(signal) changes the picture")
            }
        }
    }

    func testEverySampleRendersWithNobodyThere() {
        for pack in rig.packs {
            let lonely = rig.render(pack, SampleLensRig.scene(), face: false, save: "noface")
            XCTAssertEqual(lonely.picture.extent, rig.everything, pack.name)
            XCTAssertEqual(lonely.lens.particleCount, 0, "\(pack.name): nothing to emit from")
            if pack.needsFace { XCTAssertEqual(lonely.lens.status?.title, "Looking for your face…", pack.name) } else { XCTAssertNil(lonely.lens.status, pack.name) }
        }
    }

    func testNothingPinnedToAFaceIsDrawnWhenThereIsNoFace() {
        for pack in rig.packs {
            // What is left when only the always-on parts of the picture itself remain.
            var onlyThePicture = pack
            onlyThePicture.layers.removeAll { $0.anchor != .screen || $0.show.needsFace }
            onlyThePicture.warps = []
            onlyThePicture.emitters = []
            let lonely = rig.render(pack, SampleLensRig.scene(), face: false)
            let expected = rig.render(onlyThePicture, SampleLensRig.scene(), face: false)
            XCTAssertLessThanOrEqual(lonely.bits.change(from: expected.bits, in: rig.everything), SampleLensRig.noise, "\(pack.name) draws only what belongs to the picture")
        }
    }

    func testEverySampleRendersOnATiltedHeadAndFarFromTheCamera() {
        for pack in rig.packs {
            let everything: Set<PackSignal> = [.smile, .browRaise, .mouthOpen]
            let tilted = rig.render(pack, SampleLensRig.scene(everything, center: CGPoint(x: 520, y: 360), scale: 0.85, roll: 0.4), save: "tilted")
            XCTAssertEqual(tilted.picture.extent, rig.everything, "\(pack.name) tilted")
            let far = rig.render(pack, SampleLensRig.scene(everything, center: CGPoint(x: 900, y: 300), scale: 0.45), save: "far")
            XCTAssertEqual(far.picture.extent, rig.everything, "\(pack.name) far away")
            let close = rig.render(pack, SampleLensRig.scene(everything, center: CGPoint(x: 640, y: 330), scale: 1.7), save: "close")
            XCTAssertEqual(close.picture.extent, rig.everything, "\(pack.name) close up")
        }
    }

    func testAHugeFrameTimeAndAFaceThatComesAndGoesDoNotBreakAnything() {
        for pack in rig.packs {
            let lens = PackLens(pack)
            let faceFrame = rig.h.input(SampleLensRig.scene([.smile, .mouthOpen]))
            let empty = LensInput(time: 0, dt: 1.0 / 30, rect: faceFrame.rect, camera: faceFrame.camera, matte: faceFrame.matte, background: faceFrame.background,
                                  composed: faceFrame.composed, matteGrid: faceFrame.matteGrid, face: nil, services: faceFrame.services)
            for i in 0..<40 { _ = lens.render(rig.h.at(i % 7 < 3 ? empty : faceFrame, time: Double(i) / 30)) }
            let jump = lens.render(rig.h.at(faceFrame, time: 100, dt: 5))
            XCTAssertEqual(jump.extent, rig.everything, pack.name)
            XCTAssertLessThanOrEqual(lens.particleCount, 480, "\(pack.name) keeps to the particle budget")
            lens.restart()
            XCTAssertEqual(lens.particleCount, 0, pack.name)
        }
    }

    // MARK: Triggers

    func testWhatAnExpressionSwitchesOnIsInvisibleUntilTheExpressionHappens() {
        for pack in rig.packs {
            for signal in SampleLensRig.readings(of: pack) {
                let without = SampleLensRig.removing(signal, from: pack)
                guard without.layers.count != pack.layers.count || without.warps.count != pack.warps.count || without.emitters.count != pack.emitters.count else { continue }
                let rest = SampleLensRig.scene(), on = SampleLensRig.scene([signal])
                XCTAssertLessThanOrEqual(rig.render(pack, rest).bits.change(from: rig.render(without, rest).bits, in: rig.everything), SampleLensRig.noise,
                                         "\(pack.name): nothing of the \(signal) parts shows while the face is at rest")
                XCTAssertGreaterThan(rig.render(pack, on).bits.change(from: rig.render(without, on).bits, in: rig.everything), 40,
                                     "\(pack.name): the \(signal) parts paint something once it happens")
            }
        }
    }

    func testAnExpressionTheLensIgnoresChangesNothingOfWhatItDraws() {
        // Raising the eyebrows must not make Sleepy Head dim or Rockstar play, and so on: each lens answers only to its own.
        for pack in rig.packs {
            let own = SampleLensRig.readings(of: pack)
            for signal in SampleLensRig.expressions where !own.contains(signal) {
                let at = SampleLensRig.scene([signal])
                let before = rig.render(pack, at).bits
                // The same lens run over the same scene with every part driven by its own expressions removed looks identical.
                var bare = pack
                for own in own { bare = SampleLensRig.removing(own, from: bare) }
                XCTAssertLessThanOrEqual(before.change(from: rig.render(bare, at).bits, in: rig.everything), SampleLensRig.noise, "\(pack.name) ignores \(signal)")
            }
        }
    }
}

// MARK: - What each lens does

final class SampleLensBehaviourTests: XCTestCase {
    private var rig: SampleLensRig!
    private let middle = CGPoint(x: 640, y: 390)

    override func setUpWithError() throws { rig = try SampleLensRig() }

    private func region(_ p: CGPoint, _ half: CGFloat) -> CGRect { CGRect(x: p.x - half, y: p.y - half, width: half * 2, height: half * 2) }

    func testRockstarWearsGoldShadesAndSmilesUpLightningAndSparks() throws {
        let pack = try rig.pack("Rockstar")
        let scene = SampleLensRig.scene()
        let calm = rig.render(pack, scene)
        let face = scene.face()
        for eye in [face.leftEye, face.rightEye] {
            let p = calm.bits.pixel(Int(eye.x), Int(eye.y) - 14)
            XCTAssertLessThan(p.r + p.g + p.b, 150, "dark glass over the eye at \(eye)")
        }
        let frame = FaceFrame(face)
        let bolts = [-1.0, 1.0].map { side -> CGRect in let c = frame.pixel(SIMD2(1.75 * side, 0.45)); return CGRect(x: c.x - 35, y: c.y - 70, width: 70, height: 140) }
        for bolt in bolts { XCTAssertFalse(rig.found(calm.bits, in: bolt, where: SampleLensRig.isGold), "no lightning until you smile") }
        XCTAssertEqual(calm.lens.particleCount, 0)

        let smiling = rig.render(pack, SampleLensRig.scene([.smile]))
        for bolt in bolts { XCTAssertTrue(rig.found(smiling.bits, in: bolt, where: SampleLensRig.isGold), "a gold bolt beside the head in \(bolt)") }
        XCTAssertGreaterThan(smiling.lens.particleCount, 5, "sparks fly off the shades")

        let singing = rig.render(pack, SampleLensRig.scene([.mouthOpen]))
        for bolt in bolts { XCTAssertFalse(rig.found(singing.bits, in: bolt, where: SampleLensRig.isGold), "the lightning is for smiles") }
        XCTAssertGreaterThan(singing.lens.particleCount, 5, "fire")
        let mouth = face.mouth
        XCTAssertTrue(rig.found(singing.bits, in: CGRect(x: mouth.x - 60, y: mouth.y - 200, width: 120, height: 180)) { $0.r > 220 && $0.g > 120 && $0.b < 120 }, "flames below the mouth")
    }

    func testLovestruckHeartsAlwaysRiseAndSpillOverWhenYouSmile() throws {
        let pack = try rig.pack("Lovestruck")
        let scene = SampleLensRig.scene()
        let calm = rig.render(pack, scene)
        XCTAssertGreaterThan(calm.lens.particleCount, 2, "hearts drift up from the head even at rest")
        let smiling = rig.render(pack, SampleLensRig.scene([.smile]))
        XCTAssertGreaterThan(smiling.lens.particleCount, calm.lens.particleCount + 3, "and more when you smile")

        let frame = FaceFrame(scene.face())
        let cheek = frame.pixel(frame.local(.cheekLeft)), other = frame.pixel(frame.local(.cheekRight))
        for spot in [cheek, other] {
            let p = calm.bits.pixel(Int(spot.x), Int(spot.y)), q = rig.plain(scene).pixel(Int(spot.x), Int(spot.y))
            XCTAssertGreaterThan(p.r - p.g, q.r - q.g + 15, "a blush on the cheek at \(spot)")
        }
        let eye = scene.face().leftEye
        XCTAssertGreaterThan(smiling.bits.change(from: rig.render(SampleLensRig.removing(.smile, from: pack), SampleLensRig.scene([.smile])).bits, in: region(eye, 40)), 40, "the eye swells on a smile")
    }

    func testBrainFreezeDropsIciclesAndFrostOnlyWhenYouOpenWide() throws {
        let pack = try rig.pack("Brain Freeze")
        let calm = rig.render(pack, SampleLensRig.scene())
        let tops = CGRect(x: 20, y: 640, width: 1240, height: 80)
        func isIce(_ p: RGB) -> Bool { p.r > 190 && p.g > 225 && p.b > 240 }
        XCTAssertFalse(rig.found(calm.bits, in: tops, where: isIce), "no icicles at rest")
        XCTAssertEqual(calm.lens.particleCount, 0)
        let frame = FaceFrame(SampleLensRig.scene().face())
        let nose = frame.pixel(frame.local(.nose))
        let p = calm.bits.pixel(Int(nose.x), Int(nose.y)), q = rig.plain(SampleLensRig.scene()).pixel(Int(nose.x), Int(nose.y))
        XCTAssertGreaterThan(p.r - p.b, q.r - q.b + 10, "a red, cold nose even at rest")

        let wide = rig.render(pack, SampleLensRig.scene([.mouthOpen]))
        XCTAssertTrue(rig.found(wide.bits, in: tops, where: isIce), "icicles hang from the top of the picture")
        XCTAssertGreaterThan(wide.lens.particleCount, 3, "cold bubbles")
        let side = CGRect(x: 60, y: 250, width: 200, height: 200)
        XCTAssertGreaterThan(rig.brightness(wide.bits, in: side), rig.brightness(rig.plain(SampleLensRig.scene([.mouthOpen])), in: side) + 6, "a frosty wash over the picture")
    }

    func testSleepyHeadDimsAndSendsZsOnlyForEyesHeldShut() throws {
        let pack = try rig.pack("Sleepy Head")
        let calm = rig.render(pack, SampleLensRig.scene())
        let corner = CGRect(x: 60, y: 200, width: 220, height: 200)
        let asleep = rig.render(pack, SampleLensRig.scene([.blink]))
        XCTAssertLessThan(rig.brightness(asleep.bits, in: corner), rig.brightness(calm.bits, in: corner) - 12, "the lights go down")
        let zs = CGRect(x: 380, y: 490, width: 150, height: 210)
        func isZ(_ p: RGB) -> Bool { p.b > 190 && p.r > 140 && p.g > 150 }
        XCTAssertTrue(rig.found(asleep.bits, in: zs, where: isZ), "Zs float up beside the head, on the other side from the cap's tail")
        XCTAssertFalse(rig.found(calm.bits, in: zs, where: isZ), "none when awake")

        // An ordinary blink (a tenth of a second) is nearly invisible; only a long one brings the dark.
        let awake = rig.h.input(SampleLensRig.scene()), shut = rig.h.input(SampleLensRig.scene([.blink]))
        let lens = PackLens(pack)
        var darkest = Double.infinity, time = 0.0
        for i in 0..<60 {
            let frame = (i >= 20 && i < 23) ? shut : awake
            let out = lens.render(rig.h.at(frame, time: time))
            time += 1.0 / 30
            if i >= 20 { darkest = min(darkest, rig.brightness(rig.h.bitmap(out), in: corner)) }
        }
        let resting = rig.brightness(calm.bits, in: corner)
        XCTAssertGreaterThan(darkest, resting - (resting - rig.brightness(asleep.bits, in: corner)) * 0.35, "a quick blink dims far less than a long one (\(darkest))")

        let cap = FaceFrame(SampleLensRig.scene().face()).pixel(SIMD2(0.0, 1.5))
        let p = calm.bits.pixel(Int(cap.x), Int(cap.y))
        XCTAssertGreaterThan(p.b, p.r + 40, "a blue nightcap on the head")
        let other = rig.render(pack, SampleLensRig.scene([.smile]))
        XCTAssertEqual(rig.brightness(other.bits, in: corner), rig.brightness(calm.bits, in: corner), accuracy: 1, "a smile doesn't send the lights down")
    }

    func testSuperstarSpotlightFollowsYouAndTheBannerWaitsForAFace() throws {
        let pack = try rig.pack("Superstar")
        let left = SampleLensRig.scene(center: CGPoint(x: 360, y: 390)), right = SampleLensRig.scene(center: CGPoint(x: 920, y: 390))
        let leftRender = rig.render(pack, left), rightRender = rig.render(pack, right)
        let aboveLeftHead = CGRect(x: 320, y: 560, width: 80, height: 60), aboveRightHead = CGRect(x: 880, y: 560, width: 80, height: 60)
        XCTAssertGreaterThan(rig.brightness(leftRender.bits, in: aboveLeftHead), rig.brightness(rightRender.bits, in: aboveLeftHead) + 8, "the beam is over the head on the left")
        XCTAssertGreaterThan(rig.brightness(rightRender.bits, in: aboveRightHead), rig.brightness(leftRender.bits, in: aboveRightHead) + 8, "and goes with you to the right")

        let banner = CGRect(x: 540, y: 20, width: 200, height: 80)
        XCTAssertTrue(rig.found(rig.render(pack, SampleLensRig.scene()).bits, in: banner, where: SampleLensRig.isGold), "SUPERSTAR in gold")
        XCTAssertFalse(rig.found(rig.render(pack, SampleLensRig.scene(), face: false).bits, in: banner, where: SampleLensRig.isGold), "but only once a face is found")

        let calm = rig.render(pack, SampleLensRig.scene())
        let smiling = rig.render(pack, SampleLensRig.scene([.smile]))
        XCTAssertGreaterThan(smiling.lens.particleCount, calm.lens.particleCount + 5, "confetti joins the sparkles when you smile")
    }

    func testRetroArcadeScoreboardChangesWithYourFace() throws {
        let pack = try rig.pack("Retro Arcade")
        let calm = rig.render(pack, SampleLensRig.scene())
        // Scanlines: the picture is darker on a line than between two.
        XCTAssertLessThan(rig.brightness(calm.bits, in: CGRect(x: 90, y: 515, width: 40, height: 2)), rig.brightness(calm.bits, in: CGRect(x: 90, y: 527, width: 40, height: 2)) - 4, "scanlines")
        // A screen with rounded corners: the very corner is dark, a little way in along the edge is not.
        XCTAssertLessThan(rig.brightness(calm.bits, in: CGRect(x: 4, y: 4, width: 16, height: 16)), 60, "a dark rounded corner")
        func isYellow(_ p: RGB) -> Bool { p.r > 200 && p.g > 180 && p.b < 120 }
        XCTAssertTrue(rig.found(calm.bits, in: CGRect(x: 30, y: 640, width: 220, height: 60), where: isYellow), "PLAYER 1 in yellow, top left")
        XCTAssertTrue(rig.found(calm.bits, in: CGRect(x: 1040, y: 640, width: 200, height: 60), where: SampleLensRig.isRed), "three lives, top right")
        let coin = CGRect(x: 520, y: 20, width: 240, height: 60)
        func isPink(_ p: RGB) -> Bool { p.r > 190 && p.g < 120 && p.b > 100 && p.b < 190 }
        func isCyan(_ p: RGB) -> Bool { p.r < 120 && p.g > 180 && p.b > 200 }
        XCTAssertTrue(rig.found(calm.bits, in: coin, where: isPink), "INSERT COIN while you wait")
        XCTAssertFalse(rig.found(calm.bits, in: coin, where: isCyan))

        let smiling = rig.render(pack, SampleLensRig.scene([.smile]))
        XCTAssertFalse(rig.found(smiling.bits, in: coin, where: isPink), "the coin message goes away when you smile…")
        XCTAssertTrue(rig.found(smiling.bits, in: coin, where: isCyan), "…and PRESS START takes its place")
        func isGreen(_ p: RGB) -> Bool { p.g > 200 && p.r < 140 && p.b < 160 }
        let oneUp = CGRect(x: 700, y: 490, width: 170, height: 90)
        XCTAssertTrue(rig.found(smiling.bits, in: oneUp, where: isGreen), "+1UP beside the head")
        XCTAssertFalse(rig.found(calm.bits, in: oneUp, where: isGreen))

        let top = CGRect(x: 420, y: 520, width: 440, height: 110)
        XCTAssertFalse(rig.found(calm.bits, in: top, where: isCyan))
        XCTAssertTrue(rig.found(rig.render(pack, SampleLensRig.scene([.browRaise])).bits, in: top, where: isCyan), "LEVEL UP! when the eyebrows go up")
        let mouth = SampleLensRig.scene().face().mouth
        let wakaZone = CGRect(x: mouth.x + 60, y: mouth.y - 50, width: 240, height: 110)
        XCTAssertFalse(rig.found(calm.bits, in: wakaZone, where: isYellow))
        XCTAssertTrue(rig.found(rig.render(pack, SampleLensRig.scene([.mouthOpen])).bits, in: wakaZone, where: isYellow), "WAKA WAKA! beside an open mouth")
    }

    func testDiscoFeverHangsABallAndPartiesOnSmilesAndSongs() throws {
        let pack = try rig.pack("Disco Fever")
        let calm = rig.render(pack, SampleLensRig.scene())
        let ball = CGRect(x: 580, y: 590, width: 120, height: 90)
        XCTAssertGreaterThan(calm.bits.change(from: rig.plain(SampleLensRig.scene()), in: ball), 250, "a mirror ball at the top")
        func isPink(_ p: RGB) -> Bool { p.r > 230 && p.g < 130 && p.b > 170 }
        let sign = CGRect(x: 480, y: 20, width: 320, height: 80)
        XCTAssertTrue(rig.found(calm.bits, in: sign, where: isPink), "DISCO FEVER in pink")
        XCTAssertTrue(rig.found(rig.render(pack, SampleLensRig.scene(), face: false).bits, in: sign, where: isPink), "the room needs no face")
        XCTAssertGreaterThan(calm.lens.particleCount, 3, "glitter all the time")
        let smiling = rig.render(pack, SampleLensRig.scene([.smile]))
        XCTAssertGreaterThan(smiling.lens.particleCount, calm.lens.particleCount + 10, "confetti")
        let singing = rig.render(pack, SampleLensRig.scene([.mouthOpen]))
        XCTAssertGreaterThan(singing.lens.particleCount, calm.lens.particleCount + 10, "a rainbow")
    }

    func testChillModeIsTealWearsHeadphonesAndWaitsForASmileToSayGoodVibes() throws {
        let pack = try rig.pack("Chill Mode")
        let scene = SampleLensRig.scene()
        let calm = rig.render(pack, scene)
        let plain = rig.plain(scene)
        func coolness(_ b: Bitmap) -> Double {
            var total = 0.0
            for x in stride(from: 800, to: 960, by: 8) { for y in stride(from: 400, to: 560, by: 8) { let p = b.pixel(x, y); total += Double(p.g + p.b - 2 * p.r) } }
            return total
        }
        XCTAssertGreaterThan(coolness(calm.bits), coolness(plain) + 1000, "a cooler, teal picture")
        let frame = FaceFrame(scene.face())
        func isPink(_ p: RGB) -> Bool { p.r > 230 && p.g > 130 && p.g < 190 && p.b > 160 }
        for x in [-1.38, 1.07] {
            let cup = frame.pixel(SIMD2(x, -0.15))
            XCTAssertTrue(isPink(calm.bits.pixel(Int(cup.x), Int(cup.y))), "a pink ear cup at \(cup)")
        }
        let tag = CGRect(x: 60, y: 620, width: 180, height: 70)
        XCTAssertGreaterThan(calm.bits.change(from: plain, in: tag), 150, "the brb tag")
        func isLight(_ p: RGB) -> Bool { p.r > 190 && p.g > 230 && p.b > 220 }
        let chin = frame.pixel(SIMD2(0.0, -1.9))
        let words = CGRect(x: chin.x - 110, y: chin.y - 40, width: 220, height: 80)
        XCTAssertFalse(rig.found(calm.bits, in: words, where: isLight), "no good vibes until you smile")
        XCTAssertTrue(rig.found(rig.render(pack, SampleLensRig.scene([.smile])).bits, in: words, where: isLight), "good vibes on a smile")
    }

    func testOnAirLightsUpWhileYouTalkAndNeedsNoFaceToExist() throws {
        let pack = try rig.pack("On Air")
        let sign = CGRect(x: 960, y: 620, width: 270, height: 90)
        func isDimRed(_ p: RGB) -> Bool { p.r > 120 && p.g < 70 && p.b < 70 }
        func isLit(_ p: RGB) -> Bool { p.r > 235 && p.g > 190 && p.b > 185 }
        let calm = rig.render(pack, SampleLensRig.scene())
        XCTAssertTrue(rig.found(calm.bits, in: sign, where: isDimRed), "an unlit red ON AIR sign")
        XCTAssertFalse(rig.found(calm.bits, in: sign, where: isLit))
        XCTAssertTrue(rig.found(rig.render(pack, SampleLensRig.scene(), face: false).bits, in: sign, where: isDimRed), "the sign is there with nobody in view")

        let talking = rig.render(pack, SampleLensRig.scene([.mouthOpen]))
        XCTAssertTrue(rig.found(talking.bits, in: sign, where: isLit), "the sign lights up")
        let edge = CGRect(x: 300, y: 0, width: 600, height: 6)
        let redEdge = rig.brightness(talking.bits, in: edge) - rig.brightness(rig.plain(SampleLensRig.scene([.mouthOpen])), in: edge)
        XCTAssertGreaterThan(redEdge, 40, "and a red frame glows round the picture")
        // Soft: the look lifts the shadows a little and takes the edge off the contrast.
        let backdrop = CGRect(x: 100, y: 100, width: 100, height: 100)
        XCTAssertNotEqual(rig.brightness(calm.bits, in: backdrop), rig.brightness(rig.plain(SampleLensRig.scene()), in: backdrop), accuracy: 3)
    }

    func testWizardEyesBlazeWhenTheEyebrowsGoUp() throws {
        let pack = try rig.pack("Wizard Eyes")
        let scene = SampleLensRig.scene()
        let calm = rig.render(pack, scene)
        let face = scene.face()
        func isMagic(_ p: RGB) -> Bool { p.r < 170 && p.g > 200 && p.b > 220 }
        for eye in [face.leftEye, face.rightEye] {
            XCTAssertFalse(rig.found(calm.bits, in: region(eye, 12), where: isMagic), "plain eyes at rest")
        }
        let frame = FaceFrame(face)
        let beard = frame.pixel(frame.local(.chin) + SIMD2(0, -0.6))
        XCTAssertTrue(SampleLensRig.isNearWhite(calm.bits.pixel(Int(beard.x), Int(beard.y))), "a white beard")
        let hat = frame.pixel(SIMD2(0.1, 2.2))
        let h = calm.bits.pixel(Int(hat.x), Int(hat.y))
        XCTAssertTrue(h.b > h.g + 30 && h.r < 120, "a purple hat (\(h))")

        let amazed = rig.render(pack, SampleLensRig.scene([.browRaise]))
        let amazedFace = SampleLensRig.scene([.browRaise]).face()
        for eye in [amazedFace.leftEye, amazedFace.rightEye] {
            XCTAssertTrue(rig.found(amazed.bits, in: region(eye, 12), where: isMagic), "a glowing eye at \(eye)")
        }
        XCTAssertGreaterThan(amazed.lens.particleCount, calm.lens.particleCount + 5, "sparkles come off the eyes")
    }

    func testTheFirstFiveStillDoWhatTheyAlwaysDid() throws {
        // The first five are the originals: redrawn, but each still does the same thing in the same way.
        XCTAssertEqual(try rig.pack("Halo and Horns").layers.count, 2)
        let tag = try rig.pack("Name Tag")
        XCTAssertTrue(tag.layers.allSatisfy { $0.anchor == .screen }, "the name tag belongs to the picture")
        XCTAssertTrue(tag.layers.contains { if case .text("YOUR NAME") = $0.content { return true } else { return false } }, "with words to change")
        XCTAssertFalse(try rig.pack("Golden Hour").needsFace)
        XCTAssertTrue(try rig.pack("Golden Hour").layers.allSatisfy { $0.anchor == .screen && !$0.show.needsFace })
        let bubbles = try rig.pack("Bubble Talk")
        XCTAssertTrue(bubbles.emitters.allSatisfy { $0.preset == .bubbles && $0.show.signal == .mouthOpen })
        XCTAssertEqual(try rig.pack("Heart Eyes").emitters.first?.preset, .sparkles)
    }

    func testHeartEyesAreDrawnHeartsThatBeat() throws {
        let pack = try rig.pack("Heart Eyes")
        XCTAssertTrue(pack.layers.contains { if case .shape(.heart) = $0.content { return $0.animation?.kind == .pulse } else { return false } })
        let scene = SampleLensRig.scene()
        let bits = rig.render(pack, scene).bits
        for eye in [scene.face().leftEye, scene.face().rightEye] {
            XCTAssertTrue(rig.found(bits, in: region(eye, 14)) { $0.r > 200 && $0.g < 110 }, "a red heart over the eye at \(eye)")
        }
    }
}
