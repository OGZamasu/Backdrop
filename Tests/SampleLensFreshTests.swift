import CoreImage
import XCTest

/// The fifteen samples added after the first fifteen: each shows off a different part of the format, and each does what its
/// description says. (Every sample, these included, is also rendered at rest, with each expression, tilted, far, close and with
/// nobody there by SampleLensRenderTests.)
final class SampleLensFreshTests: XCTestCase {
    private var rig: SampleLensRig!

    override func setUpWithError() throws { rig = try SampleLensRig() }

    static let fresh = ["Neon Sign", "Rainy Mood", "Boss Mode", "Birthday Party", "Masked Hero", "Kitty Face", "Space Helmet", "Pixel Shades",
                        "Bright Idea", "Gold Medal", "Winter Beanie", "Neon Visor", "Sheriff", "Tropical Sunset", "Anime Sparkle"]

    private func region(_ p: CGPoint, _ half: CGFloat) -> CGRect { CGRect(x: p.x - half, y: p.y - half, width: half * 2, height: half * 2) }

    /// Where a point given in eye-spacings lands on the synthetic person at rest.
    private func at(_ x: Double, _ y: Double, _ scene: SyntheticScene = SampleLensRig.scene()) -> CGPoint { FaceFrame(scene.face()).pixel(SIMD2(x, y)) }

    private func chin(_ x: Double, _ y: Double) -> CGPoint {
        let frame = FaceFrame(SampleLensRig.scene().face())
        return frame.pixel(frame.local(.chin) + SIMD2(x, y))
    }

    private func mouth(_ x: Double, _ y: Double) -> CGPoint {
        let frame = FaceFrame(SampleLensRig.scene().face())
        return frame.pixel(frame.local(.mouth) + SIMD2(x, y))
    }

    private func layers(_ pack: LensPack, _ test: (PackLayer) -> Bool) -> Int { pack.layers.filter(test).count }

    // MARK: What they show off

    func testThereAreFifteenNewOnesAfterTheFirstFifteen() {
        XCTAssertEqual(SampleLenses.all.dropFirst(15).map(\.folder), Self.fresh.map { $0 + ".backdroplens" })
        for name in Self.fresh { XCTAssertNoThrow(try rig.pack(name), name) }
    }

    func testEachNewSampleShowsOffItsOwnPartOfTheFormat() throws {
        let neon = try rig.pack("Neon Sign")
        XCTAssertTrue(neon.layers.allSatisfy { $0.anchor == .screen }, "a sign on the wall, not on the face")
        XCTAssertGreaterThan(layers(neon) { $0.show.signal == .faceFound }, 3, "it lights up when someone is there")

        let rain = try rig.pack("Rainy Mood")
        XCTAssertTrue(rain.layers.contains { $0.show.signal == .smile && $0.show.below != nil }, "rain while you are not smiling")
        XCTAssertTrue(rain.layers.contains { $0.show.signal == .smile && $0.show.above != nil }, "sun when you are")
        XCTAssertEqual(rain.emitters.first?.preset, .rainbow)

        let boss = try rig.pack("Boss Mode")
        XCTAssertTrue(boss.layers.contains { $0.anchor == .chin && !$0.followsHead }, "a badge that stays upright")
        XCTAssertTrue(boss.layers.contains { if case .text("BOSS") = $0.content { return true } else { return false } })

        let party = try rig.pack("Birthday Party")
        XCTAssertGreaterThan(layers(party) { $0.anchor == .screen && $0.show.signal == .always }, 10, "bunting that needs nobody")
        XCTAssertEqual(party.emitters.first?.preset, .confetti)

        let hero = try rig.pack("Masked Hero")
        XCTAssertTrue(hero.layers.contains { $0.color.alpha == 0 && ($0.strokeWidth ?? 0) > 0.2 }, "eye holes are the inside of a thick outline")

        let kitty = try rig.pack("Kitty Face")
        XCTAssertTrue(kitty.warps.contains { $0.kind == .pinch && $0.anchor == .nose && $0.show.signal == .always }, "a button nose")
        XCTAssertGreaterThanOrEqual(layers(kitty) { $0.mirror }, 6, "whiskers drawn once and mirrored")

        let helmet = try rig.pack("Space Helmet")
        XCTAssertTrue(helmet.layers.contains { $0.show.signal == .blink && $0.blend == .multiply }, "a sun visor for closed eyes")
        XCTAssertTrue(helmet.layers.contains { $0.blend == .screen }, "glass")

        let pixel = try rig.pack("Pixel Shades")
        XCTAssertTrue(pixel.layers.contains { $0.animation?.kind == .dropIn && $0.anchor == .eyes })
        XCTAssertTrue(pixel.look.isNeutral, "a lens doesn't need a look")

        let idea = try rig.pack("Bright Idea")
        XCTAssertTrue(idea.layers.contains { $0.show.signal == .browRaise && $0.show.below != nil }, "a bulb that is off")
        XCTAssertTrue(idea.layers.contains { $0.show.signal == .browRaise && $0.show.above != nil }, "and on")

        let medal = try rig.pack("Gold Medal")
        XCTAssertTrue(medal.layers.contains { $0.blend == .multiply }, "shading by multiplying")
        XCTAssertGreaterThanOrEqual(medal.emitters.count, 3)

        let beanie = try rig.pack("Winter Beanie")
        XCTAssertTrue(beanie.layers.contains { $0.anchor == .cheekLeft && $0.mirror }, "rosy cheeks")
        XCTAssertTrue(beanie.layers.contains { $0.show.signal == .mouthOpen && $0.animation?.kind == .float }, "breath that drifts")

        let visor = try rig.pack("Neon Visor")
        XCTAssertNotEqual(visor.look.hue, 0, "a hue shift")
        XCTAssertTrue(visor.layers.contains { $0.animation?.kind == .spin })

        XCTAssertLessThan(try rig.pack("Sheriff").look.saturation, 0.5, "old-photo sepia")

        let tropical = try rig.pack("Tropical Sunset")
        let petals = tropical.layers.filter { if case .shape(.circle) = $0.content { return $0.anchor == .eyes } else { return false } }
        XCTAssertGreaterThanOrEqual(Set(petals.map { Int($0.rotation * 180 / .pi) }).count, 5, "petals laid round by turning them")

        let anime = try rig.pack("Anime Sparkle")
        XCTAssertEqual(anime.warps.filter { $0.kind == .bulge && $0.show.signal == .always }.count, 2, "big eyes all the time")
        XCTAssertTrue(anime.layers.contains { $0.anchor == .cheekRight })
    }

    // MARK: What each one does

    func testNeonSignLightsUpWhenSomeoneSitsDownAndBuzzesOnASmile() throws {
        let pack = try rig.pack("Neon Sign")
        let sign = CGRect(x: 90, y: 590, width: 350, height: 50)
        func isLit(_ p: RGB) -> Bool { p.r > 235 && p.g > 200 && p.b > 225 }
        let lonely = rig.render(pack, SampleLensRig.scene(), face: false)
        XCTAssertGreaterThan(lonely.bits.change(from: rig.plain(SampleLensRig.scene()), in: sign), 100, "the sign hangs there with nobody in view")
        XCTAssertFalse(rig.found(lonely.bits, in: sign, where: isLit), "but it is switched off")
        let calm = rig.render(pack, SampleLensRig.scene())
        XCTAssertTrue(rig.found(calm.bits, in: sign, where: isLit), "on once you are there")
        let halo = CGRect(x: 460, y: 560, width: 80, height: 80)
        XCTAssertGreaterThan(rig.brightness(rig.render(pack, SampleLensRig.scene([.smile])).bits, in: halo), rig.brightness(calm.bits, in: halo) + 3, "brighter for a smile")
    }

    func testRainyMoodRainsUntilYouSmile() throws {
        let pack = try rig.pack("Rainy Mood")
        let cloud = at(-0.1, 0.82 + 1.55)
        func isGrey(_ p: RGB) -> Bool { abs(p.r - p.b) < 50 && p.r > 120 && p.r < 210 }
        func isRain(_ p: RGB) -> Bool { p.b > 200 && p.b > p.r + 40 }
        let rain = CGRect(x: at(-1.3, 0).x, y: at(0, 0.9).y, width: at(0.3, 0).x - at(-1.3, 0).x, height: at(0, 1.6).y - at(0, 0.9).y)
        let calm = rig.render(pack, SampleLensRig.scene())
        XCTAssertTrue(isGrey(calm.bits.pixel(Int(cloud.x), Int(cloud.y))), "a grey cloud over the head")
        XCTAssertTrue(rig.found(calm.bits, in: rain, where: isRain), "raining")
        XCTAssertEqual(calm.lens.particleCount, 0)
        let happy = rig.render(pack, SampleLensRig.scene([.smile]))
        XCTAssertTrue(SampleLensRig.isNearWhite(happy.bits.pixel(Int(cloud.x), Int(cloud.y))), "the cloud turns white")
        XCTAssertFalse(rig.found(happy.bits, in: rain, where: isRain), "the rain stops")
        XCTAssertTrue(rig.found(happy.bits, in: region(at(1.25, 3.15), 14), where: SampleLensRig.isGold), "the sun comes out")
        XCTAssertGreaterThan(happy.lens.particleCount, 5, "and the rain turns to a rainbow")
    }

    func testBossModeWearsATieGetsPromotedAndHasAMug() throws {
        let pack = try rig.pack("Boss Mode")
        let calm = rig.render(pack, SampleLensRig.scene())
        let tie = chin(0, -1.8)
        let p = calm.bits.pixel(Int(tie.x), Int(tie.y))
        XCTAssertTrue(p.r > 150 && p.g < 80 && p.b < 90, "a red tie below the chin (\(p))")
        let banner = CGRect(x: 430, y: 570, width: 420, height: 70)
        let mug = CGRect(x: 1060, y: 60, width: 140, height: 120)
        XCTAssertFalse(rig.found(calm.bits, in: banner, where: SampleLensRig.isGold))
        XCTAssertFalse(rig.found(calm.bits, in: mug, where: SampleLensRig.isNearWhite))
        XCTAssertTrue(rig.found(rig.render(pack, SampleLensRig.scene([.browRaise])).bits, in: banner, where: SampleLensRig.isGold), "PROMOTED! for raised eyebrows")
        XCTAssertTrue(rig.found(rig.render(pack, SampleLensRig.scene([.smile])).bits, in: mug, where: SampleLensRig.isNearWhite), "a mug for a smile")
    }

    func testBirthdayPartyHasBuntingAlwaysAndBalloonsForASmile() throws {
        let pack = try rig.pack("Birthday Party")
        let top = CGRect(x: 0, y: 590, width: 1280, height: 130)
        XCTAssertGreaterThan(rig.render(pack, SampleLensRig.scene(), face: false).bits.change(from: rig.plain(SampleLensRig.scene()), in: top), 150, "bunting with nobody there")
        let calm = rig.render(pack, SampleLensRig.scene())
        let hat = FaceFrame(SampleLensRig.scene().face())
        let rotated = SIMD2(-0.1 * cos(-16 * Double.pi / 180) - 0.2 * sin(-16 * Double.pi / 180), -0.1 * sin(-16 * Double.pi / 180) + 0.2 * cos(-16 * Double.pi / 180))
        let point = hat.pixel(SIMD2(0.45, 0.78 + 1.55) + rotated)
        let c = calm.bits.pixel(Int(point.x), Int(point.y))
        XCTAssertGreaterThan(c.b, c.r + 100, "a blue party hat (\(c))")
        let balloon = CGRect(x: 100, y: 290, width: 80, height: 80)
        XCTAssertFalse(rig.found(calm.bits, in: balloon, where: SampleLensRig.isRed))
        let smiling = rig.render(pack, SampleLensRig.scene([.smile]))
        XCTAssertTrue(rig.found(smiling.bits, in: balloon, where: SampleLensRig.isRed), "a red balloon")
        XCTAssertGreaterThan(smiling.lens.particleCount, 10, "confetti")
    }

    func testMaskedHeroLeavesTheEyesClearAndPowsAndBams() throws {
        let pack = try rig.pack("Masked Hero")
        let scene = SampleLensRig.scene()
        let calm = rig.render(pack, scene)
        let bridge = at(0, 0.06)
        XCTAssertTrue(SampleLensRig.isRed(calm.bits.pixel(Int(bridge.x), Int(bridge.y))), "a red mask between the eyes")
        var bare = pack
        bare.layers = []
        let unmasked = rig.render(bare, scene)
        for eye in [scene.face().leftEye, scene.face().rightEye] {
            XCTAssertLessThanOrEqual(calm.bits.change(from: unmasked.bits, in: region(eye, 7)), SampleLensRig.noise, "the eye at \(eye) shows through")
        }
        let pow = region(at(2.15, 1.15), 40)
        let bam = region(at(-2.2, -0.4), 40)
        func isBlue(_ p: RGB) -> Bool { p.b > 220 && p.r < 120 }
        XCTAssertFalse(rig.found(calm.bits, in: pow, where: SampleLensRig.isGold))
        XCTAssertTrue(rig.found(rig.render(pack, SampleLensRig.scene([.browRaise])).bits, in: pow, where: SampleLensRig.isGold), "POW! for raised eyebrows")
        XCTAssertFalse(rig.found(calm.bits, in: bam, where: isBlue))
        XCTAssertTrue(rig.found(rig.render(pack, SampleLensRig.scene([.mouthOpen])).bits, in: bam, where: isBlue), "BAM! for an open mouth")
    }

    func testKittyFaceHasEarsMeowsAndGetsBigEyes() throws {
        let pack = try rig.pack("Kitty Face")
        let calm = rig.render(pack, SampleLensRig.scene())
        func isGinger(_ p: RGB) -> Bool { p.r > 200 && p.g > 100 && p.g < 150 && p.b < 90 }
        for side in [-1.0, 1.0] { XCTAssertTrue(rig.found(calm.bits, in: region(at(0.78 * side, 1.55), 30), where: isGinger), "a ginger ear") }
        let bubble = region(mouth(2.3, 0.55), 30)
        XCTAssertFalse(rig.found(calm.bits, in: bubble, where: SampleLensRig.isNearWhite))
        XCTAssertTrue(rig.found(rig.render(pack, SampleLensRig.scene([.mouthOpen])).bits, in: bubble, where: SampleLensRig.isNearWhite), "MEOW! in a speech bubble")
        let eye = SampleLensRig.scene().face().leftEye
        let smiling = rig.render(pack, SampleLensRig.scene([.smile])).bits
        XCTAssertGreaterThan(smiling.change(from: rig.render(SampleLensRig.removing(.smile, from: pack), SampleLensRig.scene([.smile])).bits, in: region(eye, 40)), 40, "big round eyes for a smile")
    }

    func testSpaceHelmetBubblesWhenYouTalkAndLowersTheVisorWhenYouCloseYourEyes() throws {
        let pack = try rig.pack("Space Helmet")
        let calm = rig.render(pack, SampleLensRig.scene())
        XCTAssertGreaterThan(calm.bits.change(from: rig.plain(SampleLensRig.scene()), in: region(at(-1.75, -0.1), 10)), 30, "the edge of the glass")
        XCTAssertEqual(calm.lens.particleCount, 0)
        XCTAssertGreaterThan(rig.render(pack, SampleLensRig.scene([.mouthOpen])).lens.particleCount, 3, "air bubbles")
        let forehead = at(0, 0.6)
        let shut = rig.render(pack, SampleLensRig.scene([.blink])).bits.pixel(Int(forehead.x), Int(forehead.y))
        let open = rig.render(SampleLensRig.removing(.blink, from: pack), SampleLensRig.scene([.blink])).bits.pixel(Int(forehead.x), Int(forehead.y))
        XCTAssertLessThan(shut.b, open.b - 20, "a gold visor over the face (\(shut) against \(open))")
    }

    func testPixelShadesWaitOnTheForeheadAndDropOntoTheEyesForASmile() throws {
        let pack = try rig.pack("Pixel Shades")
        let scene = SampleLensRig.scene()
        let calm = rig.render(pack, scene)
        let face = scene.face()
        for eye in [face.leftEye, face.rightEye] {
            XCTAssertLessThanOrEqual(calm.bits.change(from: rig.plain(scene), in: region(eye, 10)), SampleLensRig.noise, "eyes clear at rest")
        }
        let parked = at(-0.52, 0.95 + 0.38)
        let p = calm.bits.pixel(Int(parked.x), Int(parked.y))
        XCTAssertLessThan(p.r + p.g + p.b, 60, "the shades wait on the forehead")
        let smiling = rig.render(pack, SampleLensRig.scene([.smile]))
        for eye in [face.leftEye, face.rightEye] {
            let q = smiling.bits.pixel(Int(eye.x), Int(eye.y) + 4)
            XCTAssertLessThan(q.r + q.g + q.b, 60, "black pixels over the eye at \(eye)")
        }
        XCTAssertTrue(rig.found(smiling.bits, in: CGRect(x: 440, y: 50, width: 400, height: 45), where: SampleLensRig.isNearWhite), "DEAL WITH IT")
    }

    func testBrightIdeaSwitchesOnWhenYouRaiseYourEyebrows() throws {
        let pack = try rig.pack("Bright Idea")
        let glass = at(-0.25, 0.82 + 1.55)
        let calm = rig.render(pack, SampleLensRig.scene())
        let off = calm.bits.pixel(Int(glass.x), Int(glass.y))
        XCTAssertTrue(abs(off.r - off.g) < 40 && off.b >= off.r - 10, "a cool grey bulb at rest (\(off))")
        let lit = rig.render(pack, SampleLensRig.scene([.browRaise]))
        let on = lit.bits.pixel(Int(glass.x), Int(glass.y))
        XCTAssertTrue(on.r > 240 && on.g > 220 && on.b < 200, "a warm lit bulb (\(on))")
        XCTAssertGreaterThan(lit.lens.particleCount, 3, "sparkles")
    }

    func testGoldMedalSwaysAndCrownsAChampionForASmile() throws {
        let pack = try rig.pack("Gold Medal")
        let calm = rig.render(pack, SampleLensRig.scene())
        XCTAssertTrue(rig.found(calm.bits, in: region(chin(0, -2.1), 26), where: SampleLensRig.isGold), "a gold medal on the chest")
        func isLaurel(_ p: RGB) -> Bool { p.r > 180 && p.g > 120 && p.b < 80 }
        for side in [-1.0, 1.0] { XCTAssertTrue(rig.found(calm.bits, in: region(at(1.1 * side, 1.0), 30), where: isLaurel), "laurel leaves") }
        let banner = CGRect(x: 420, y: 580, width: 440, height: 60)
        func isRibbon(_ p: RGB) -> Bool { p.r > 160 && p.g < 60 && p.b < 70 }
        XCTAssertFalse(rig.found(calm.bits, in: banner, where: isRibbon))
        let smiling = rig.render(pack, SampleLensRig.scene([.smile]))
        XCTAssertTrue(rig.found(smiling.bits, in: banner, where: isRibbon), "the CHAMPION banner")
        XCTAssertGreaterThan(smiling.lens.particleCount, calm.lens.particleCount + 10, "confetti and sparkle")
    }

    func testWinterBeanieIsWarmAndShowsYourBreath() throws {
        let pack = try rig.pack("Winter Beanie")
        let calm = rig.render(pack, SampleLensRig.scene())
        let knit = at(0.5, 1.75)
        XCTAssertTrue(SampleLensRig.isRed(calm.bits.pixel(Int(knit.x), Int(knit.y))), "a red knitted hat")
        XCTAssertGreaterThan(rig.render(pack, SampleLensRig.scene(), face: false).bits.change(from: rig.plain(SampleLensRig.scene()), in: CGRect(x: 40, y: 550, width: 100, height: 100)), 100, "snow falls with nobody there")
        let breath = region(mouth(0.85, 0.08), 12)
        let open = rig.render(pack, SampleLensRig.scene([.mouthOpen]))
        let without = rig.render(SampleLensRig.removing(.mouthOpen, from: pack), SampleLensRig.scene([.mouthOpen]))
        XCTAssertGreaterThan(rig.brightness(open.bits, in: breath), rig.brightness(without.bits, in: breath) + 25, "a puff of breath")
    }

    func testCyberVisorIsSeeThroughLocksOnAndListens() throws {
        let pack = try rig.pack("Neon Visor")
        let scene = SampleLensRig.scene()
        let calm = rig.render(pack, scene)
        let eye = scene.face().leftEye
        var lightest = 0, darkest = 765
        for x in Int(eye.x) - 12...Int(eye.x) + 12 {
            let p = calm.bits.pixel(x, Int(eye.y))
            lightest = max(lightest, p.r + p.g + p.b); darkest = min(darkest, p.r + p.g + p.b)
            XCTAssertGreaterThan(p.b, p.r, "a cyan glass over the eye")
        }
        XCTAssertGreaterThan(lightest - darkest, 150, "and the eye shows through it")
        func isMagenta(_ p: RGB) -> Bool { p.r > 220 && p.g < 110 && p.b > 100 }
        let ring = region(FaceFrame(scene.face()).pixel(FaceFrame(scene.face()).local(.face) + SIMD2(1.55, 0.1)), 16)
        XCTAssertFalse(rig.found(calm.bits, in: ring, where: isMagenta))
        XCTAssertTrue(rig.found(rig.render(pack, SampleLensRig.scene([.browRaise])).bits, in: ring, where: isMagenta), "TARGET LOCKED for raised eyebrows")
        let meter = CGRect(x: 980, y: 85, width: 150, height: 65)
        func isCyan(_ p: RGB) -> Bool { p.g > 180 && p.b > 200 && p.r < 120 }
        XCTAssertFalse(rig.found(calm.bits, in: meter, where: isCyan))
        XCTAssertTrue(rig.found(rig.render(pack, SampleLensRig.scene([.mouthOpen])).bits, in: meter, where: isCyan), "a voice meter while you talk")
    }

    func testSheriffIsSepiaWithAHatAndShoutsYeeHaw() throws {
        let pack = try rig.pack("Sheriff")
        let calm = rig.render(pack, SampleLensRig.scene())
        let plain = rig.plain(SampleLensRig.scene())
        let room = calm.bits.pixel(200, 600), before = plain.pixel(200, 600)
        XCTAssertLessThan(room.b - room.g, before.b - before.g - 30, "the purple room turns to old-photo brown (\(room) from \(before))")
        let crown = at(0, 1.69)
        let h = calm.bits.pixel(Int(crown.x), Int(crown.y))
        XCTAssertTrue(h.r > h.g && h.g > h.b && h.r > 120, "a brown hat (\(h))")
        let shout = region(at(2.5, 1.35), 50)
        XCTAssertFalse(rig.found(calm.bits, in: shout, where: SampleLensRig.isGold))
        XCTAssertTrue(rig.found(rig.render(pack, SampleLensRig.scene([.mouthOpen])).bits, in: shout, where: SampleLensRig.isGold), "YEE-HAW!")
        XCTAssertGreaterThan(rig.render(pack, SampleLensRig.scene([.smile])).lens.particleCount, 3, "the star glints")
    }

    func testTropicalSunsetHasAFlowerPalmsAndAWarmGlow() throws {
        let pack = try rig.pack("Tropical Sunset")
        let calm = rig.render(pack, SampleLensRig.scene())
        func isPetal(_ p: RGB) -> Bool { p.r > 200 && p.g > 50 && p.g < 140 && p.b > 100 && p.b < 190 }
        XCTAssertTrue(rig.found(calm.bits, in: region(at(1.2, 0.62), 30), where: isPetal), "a hibiscus by the ear")
        func isLeaf(_ p: RGB) -> Bool { p.g > p.r + 5 && p.g >= p.b - 10 }
        XCTAssertTrue(rig.found(rig.render(pack, SampleLensRig.scene(), face: false).bits, in: CGRect(x: 0, y: 620, width: 140, height: 100), where: isLeaf), "palm leaves in the corner, face or not")
        let warm = calm.bits.pixel(1100, 400), before = rig.plain(SampleLensRig.scene()).pixel(1100, 400)
        XCTAssertGreaterThan(warm.r - warm.b, before.r - before.b + 10, "a coral glow")
        XCTAssertGreaterThan(rig.render(pack, SampleLensRig.scene([.smile])).lens.particleCount, 5, "the flowers sparkle for a smile")
    }

    func testAnimeSparkleAlwaysHasBigEyesAndStarsForASmile() throws {
        let pack = try rig.pack("Anime Sparkle")
        let scene = SampleLensRig.scene()
        var noWarps = pack
        noWarps.warps = []
        let eye = scene.face().leftEye
        XCTAssertGreaterThan(rig.render(pack, scene).bits.change(from: rig.render(noWarps, scene).bits, in: region(eye, 30)), 40, "big eyes, smiling or not")
        let cheek = FaceFrame(scene.face())
        let blush = cheek.pixel(cheek.local(.cheekLeft))
        func isPink(_ p: RGB) -> Bool { p.r > 220 && p.g < 170 && p.b > 120 }
        XCTAssertTrue(rig.found(rig.render(pack, scene).bits, in: region(blush, 16), where: isPink), "blush lines")
        XCTAssertGreaterThan(rig.render(pack, SampleLensRig.scene([.smile])).lens.particleCount, 3, "sparkles for a smile")
    }
}
