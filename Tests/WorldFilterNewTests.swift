import CoreImage
import XCTest

/// The ten world filters added in round two, and the new rules in the polished older ones.
final class WorldFilterNewTests: XCTestCase {
    private let h = LensHarness()
    private let size = CGSize(width: 1280, height: 720)
    /// The synthetic person's head and shoulders, roughly, as the silhouette grid sees them.
    private var you: MatteGrid { MatteGrid.filled([CGRect(x: 540, y: 300, width: 200, height: 260), CGRect(x: 380, y: 0, width: 520, height: 300)], outputSize: size) }

    private func brightness(_ c: (r: Double, g: Double, b: Double)) -> Double { c.r + c.g + c.b }
    private func length(_ v: SIMD2<Double>) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }

    @discardableResult
    private func play(_ lens: Lens, _ base: LensInput, frames: Int, from start: Int = 0, save: String? = nil) -> CIImage {
        var out = base.composed
        for i in start..<(start + frames) { out = lens.render(h.at(base, time: Double(i) / 30)) }
        if let save { Output.save(out, as: save) }
        return out
    }

    /// The room with nobody in it, as the pipeline hands it over: an empty silhouette.
    private func empty(_ base: LensInput) -> LensInput {
        LensInput(time: 0, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: CIImage(color: .black).cropped(to: base.rect),
                  background: base.background, composed: base.background ?? base.camera, matteGrid: MatteGrid(outputSize: size), face: nil,
                  services: base.services)
    }

    // MARK: Registration

    func testFifteenWorldFiltersAreRegisteredWithShortNames() {
        XCTAssertEqual(WorldFilters.all.map(\.id), ["confetti", "rain", "fireflies", "fireworks", "blossoms", "northern-lights", "spotlight",
                                                    "warp-speed", "campfire", "fog", "bubbles", "disco", "sunbeams", "underwater", "butterflies"])
        for info in WorldFilters.all {
            XCTAssertLessThanOrEqual(info.name.count, 16, info.name)
            XCTAssertLessThanOrEqual(info.blurb.count, 90, info.name)
            XCTAssertTrue(info.blurb.hasSuffix("."), info.name)
            XCTAssertFalse(info.showsText, "\(info.name) puts no words on the picture")
        }
    }

    // MARK: Northern lights

    func testNorthernLightsGlowGreenInTheSkyAndDarkenTheRoom() {
        let lens = WorldNorthernLightsLens()
        let base = h.input()
        let out = play(lens, base, frames: 45, save: "northern-lights.png")
        let sky = h.average(out, CGRect(x: 40, y: 420, width: 360, height: 110))
        XCTAssertGreaterThan(sky.g, sky.r * 1.3, "the curtains are green, got \(sky)")
        let floor = h.average(out, CGRect(x: 40, y: 200, width: 300, height: 120))
        XCTAssertLessThan(brightness(floor), brightness(h.average(base.composed, CGRect(x: 40, y: 200, width: 300, height: 120))) * 0.6, "the night is dark")
        for t in stride(from: 0.0, to: 120, by: 0.7) { XCTAssertTrue((0.55...1).contains(WorldNorthernLightsLens.intensity(at: t))) }
    }

    // MARK: Spotlight

    func testTheSpotlightFindsYouSettlesAndSearchesWhenYouLeave() {
        var rig = WorldSpotlightRig(size: size)
        let target = SIMD2<Double>(900, 380)
        var overshoot = false
        for _ in 0..<90 {
            rig.step(1.0 / 30, target: target, width: 400)
            if rig.aim.x > target.x + 2 { overshoot = true }
        }
        XCTAssertLessThan(length(rig.aim - target), 6, "it settles on you")
        XCTAssertTrue(overshoot, "after swinging a touch past")
        XCTAssertGreaterThan(rig.lock, 0.9)
        let settled = rig.aim
        for _ in 0..<120 { rig.step(1.0 / 30, target: nil, width: 0) }
        XCTAssertGreaterThan(length(rig.aim - settled), 60, "with nobody there it goes looking")
        XCTAssertLessThan(rig.lock, 0.1)
        rig.step(5, target: target, width: 400)
        XCTAssertTrue(rig.aim.x.isFinite && rig.aim.y.isFinite, "a stalled frame does not fling it away")
    }

    func testTheSpotlightLightsYouAndLeavesTheRoomDark() {
        let lens = WorldSpotlightLens()
        let base = h.input()
        let out = play(lens, base, frames: 60, save: "spotlight.png")
        let face = h.average(out, CGRect(x: 600, y: 380, width: 80, height: 60))
        let corner = h.average(out, CGRect(x: 20, y: 20, width: 200, height: 160))
        XCTAssertGreaterThan(brightness(face), brightness(corner) * 4, "you are in the light and the stage is dark")
        XCTAssertGreaterThan(lens.lock, 0.8)
        XCTAssertLessThan(abs(lens.aim.x - 640), 60, "it points at you")
    }

    // MARK: Warp speed

    func testWarpStarsStreamOutwardAndJumpNowAndThen() {
        var field = WorldWarpField(size: size)
        let centre = SIMD2<Double>(640, 400)
        for _ in 0..<10 { field.step(1.0 / 30, centre: centre) }
        let before = field.stars.map { field.project(x: $0.x, y: $0.y, z: $0.z, from: centre) }
        field.step(1.0 / 30, centre: centre)
        let after = field.stars.map { field.project(x: $0.x, y: $0.y, z: $0.z, from: centre) }
        var outward = 0
        for (a, b) in zip(before, after) where length(b - centre) > length(a - centre) { outward += 1 }
        XCTAssertGreaterThan(outward, field.stars.count * 9 / 10, "stars move away from the middle")
        XCTAssertEqual(WorldWarpField.jump(at: 1), 0, "it cruises at first")
        let peak = stride(from: 0.0, to: 20, by: 0.05).map { WorldWarpField.jump(at: $0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.95, "then jumps")
        XCTAssertGreaterThan(WorldWarpField.speed(at: 4.5), WorldWarpField.speed(at: 1) * 4)
        for i in 0..<900 { field.step(i == 200 ? 6 : 1.0 / 30, centre: centre) }
        XCTAssertEqual(field.stars.count, 240)
        XCTAssertTrue(field.stars.allSatisfy { $0.z > 0 && $0.z <= 1 && $0.x.isFinite })
    }

    func testWarpPutsTheVanishingPointBehindYourHead() {
        let lens = WorldWarpLens()
        let base = h.input(SyntheticScene(center: CGPoint(x: 820, y: 420)))
        let out = play(lens, base, frames: 90, save: "warp-speed.png")
        XCTAssertLessThan(abs(lens.vanishingPoint.x - 820), 60)
        let space = h.average(out, CGRect(x: 20, y: 500, width: 200, height: 200))
        XCTAssertGreaterThan(space.b, space.r, "deep blue space")
    }

    // MARK: Campfire

    func testEmbersRiseCoolAndNeverPileUp() {
        var sim = WorldEmberSim(size: size)
        for _ in 0..<30 { sim.step(1.0 / 30, matte: nil) }
        let first = sim.embers.prefix(20).map { ($0.position.y, $0.heat) }
        sim.step(1.0 / 30, matte: nil)
        sim.step(1.0 / 30, matte: nil)
        for (old, new) in zip(first, sim.embers.prefix(20)) {
            XCTAssertGreaterThan(new.position.y, old.0, "embers rise")
            XCTAssertLessThan(new.heat, old.1, "and cool as they go")
        }
        for i in 0..<900 { sim.step(i == 300 ? 5 : 1.0 / 30, matte: you) }
        XCTAssertLessThanOrEqual(sim.embers.count, sim.capacity)
        XCTAssertGreaterThan(sim.embers.count, 60, "a steady stream")
        for t in stride(from: 0.0, to: 60, by: 0.37) { XCTAssertTrue((0.6...1).contains(WorldEmberSim.flicker(at: t))) }
    }

    func testCampfireWarmsYouFromBelow() {
        let lens = WorldCampfireLens()
        let base = h.input()
        let out = play(lens, base, frames: 30, save: "campfire.png")
        let low = h.average(out, CGRect(x: 40, y: 20, width: 260, height: 120)), high = h.average(out, CGRect(x: 40, y: 560, width: 260, height: 140))
        XCTAssertGreaterThan(brightness(low), brightness(high) * 1.6, "brighter near the fire")
        XCTAssertGreaterThan(low.r, low.b * 1.5, "and warm")
        XCTAssertGreaterThan(lens.embers.count, 50)
    }

    // MARK: Fog

    func testFogHazesTheRoomAndThinsAroundYou() {
        let lens = WorldFogLens()
        let base = h.input()
        let out = play(lens, base, frames: 20, save: "fog.png")
        let corner = h.average(out, CGRect(x: 20, y: 20, width: 200, height: 100)), plain = h.average(base.composed, CGRect(x: 20, y: 20, width: 200, height: 100))
        XCTAssertLessThan(abs(corner.r - corner.b), abs(plain.r - plain.b), "the fog greys the colours out")
        let face = h.pixel(out, 640, 420), faceBefore = h.pixel(base.composed, 640, 420)
        XCTAssertLessThan(abs(face.r - faceBefore.r) + abs(face.g - faceBefore.g) + abs(face.b - faceBefore.b), 140, "your face stays readable")
        for t in stride(from: 0.0, to: 200, by: 1.3) { XCTAssertTrue((0.74...1).contains(WorldFogLens.thickness(at: t))) }
    }

    // MARK: Bubbles

    func testBubblesRiseBumpOffYouAndPop() {
        var sim = WorldBubbleSim(size: size)
        let start = sim.bubbles.map(\.position.y)
        for _ in 0..<15 { sim.step(1.0 / 30, matte: nil) }
        var risen = 0
        for (a, b) in zip(start, sim.bubbles.map(\.position.y)) where b > a { risen += 1 }
        XCTAssertGreaterThan(risen, start.count * 2 / 3, "bubbles float up")

        var pressed = WorldBubbleSim(size: size)
        pressed.removeAll()
        // Bubbles drifting into the sides of your head.
        for k in 0..<5 {
            let y = 330 + Double(k) * 40
            pressed.insert(WorldBubbleSim.Bubble(position: SIMD2(505, y), velocity: SIMD2(60, 20), radius: 28, depth: 0.8, phase: 0.2, life: 30, variant: 0))
            pressed.insert(WorldBubbleSim.Bubble(position: SIMD2(775, y), velocity: SIMD2(-60, 20), radius: 28, depth: 0.8, phase: 0.4, life: 30, variant: 1))
        }
        pressed.insert(WorldBubbleSim.Bubble(position: SIMD2(100, 600), velocity: .zero, radius: 20, depth: 0.1, phase: 0.2, life: 30, variant: 1))
        var everInside = false
        for _ in 0..<90 {
            pressed.step(1.0 / 30, matte: you)
            for b in pressed.bubbles where !b.isBehind && you.coverage(x: b.position.x, y: b.position.y) > 0.9 { everInside = true }
        }
        XCTAssertFalse(everInside, "a bubble in front of you is pushed off, never through you")
        XCTAssertGreaterThan(pressed.popCount, 0, "pressed against you long enough, it pops")
        for i in 0..<1800 { pressed.step(i == 50 ? 4 : 1.0 / 30, matte: you) }
        XCTAssertLessThanOrEqual(pressed.bubbles.count, pressed.capacity + 2)
        XCTAssertGreaterThan(pressed.popCount, 5)
    }

    // MARK: Disco

    func testDiscoPulsesOnTheBeatAndItsSpotsSweepAcrossYou() {
        XCTAssertEqual(WorldDiscoLens.beat(at: 0), 1, accuracy: 1e-9)
        let between = WorldDiscoLens.beat(at: 30 / WorldDiscoLens.tempo)
        XCTAssertLessThan(between, 0.15, "a soft pulse, gone by the half beat")
        let lens = WorldDiscoLens()
        let a = lens.spotPositions(at: 1), b = lens.spotPositions(at: 1.5)
        XCTAssertGreaterThan(a.count, 20)
        XCTAssertNotEqual(a.first?.position, b.first?.position, "the spots move as the ball turns")
        let base = h.input()
        let out = play(lens, base, frames: 12, save: "disco.png")
        // Find a spot falling on the shirt and check it lights it.
        let onYou = lens.spotPositions(at: 11.0 / 30).filter { $0.strength > 0.6 && $0.position.x > 420 && $0.position.x < 860 && $0.position.y > 40 && $0.position.y < 200 }
        for s in onYou.prefix(2) {
            let lit = h.pixel(out, Int(s.position.x), Int(s.position.y)), dark = h.pixel(out, Int(s.position.x) + 40, Int(s.position.y) + 36)
            XCTAssertGreaterThan(lit.r + lit.g + lit.b, dark.r + dark.g + dark.b - 30, "a spot on you at \(s.position)")
        }
    }

    // MARK: Sunbeams

    func testSunbeamsFallFromTheWindowAndLightTheDust() {
        let lens = WorldSunbeamsLens()
        XCTAssertGreaterThan(lens.sunlight(at: lens.window + SIMD2(200, -260), time: 1), lens.sunlight(at: SIMD2(1250, 700), time: 1))
        XCTAssertEqual(lens.sunlight(at: SIMD2(1270, 710), time: 1), 0, accuracy: 0.05, "the top right corner is out of the light")
        let base = h.input()
        let out = play(lens, base, frames: 20, save: "sunbeams.png")
        let lit = h.average(out, CGRect(x: 60, y: 480, width: 200, height: 180)), shade = h.average(out, CGRect(x: 1040, y: 520, width: 200, height: 160))
        XCTAssertGreaterThan(brightness(lit), brightness(shade) * 1.3, "the window side is in the sun")
        XCTAssertGreaterThan(lit.r, lit.b, "and the light is warm")
    }

    // MARK: Underwater

    func testUnderwaterTurnsTheRoomSeaGreenAndBubblesRise() {
        let lens = WorldUnderwaterLens()
        let base = h.input()
        let out = play(lens, base, frames: 30, save: "underwater.png")
        let water = h.average(out, CGRect(x: 40, y: 360, width: 300, height: 300))
        XCTAssertGreaterThan(water.g, water.r * 1.3, "sea green, got \(water)")
        XCTAssertGreaterThan(water.b, water.r * 1.3)
        XCTAssertGreaterThan(lens.bubbleCount, 3, "bubbles rise from the floor")
        let top = h.average(out, CGRect(x: 20, y: 600, width: 1240, height: 100)), bottom = h.average(out, CGRect(x: 20, y: 20, width: 300, height: 100))
        XCTAssertGreaterThan(brightness(top), brightness(bottom), "lighter toward the surface")
    }

    // MARK: Butterflies

    func testButterfliesLandOnTopOfYouAndFlyOffWhenYouMove() {
        let perches = WorldButterflySim.perches(in: you)
        XCTAssertFalse(perches.isEmpty)
        for p in perches { XCTAssertGreaterThan(you.coverage(x: p.x, y: p.y - 12), 0.5, "a perch is on you: \(p)") }
        XCTAssertTrue(perches.contains { $0.y > 520 }, "including the top of the head")
        XCTAssertTrue(WorldButterflySim.perches(in: MatteGrid(outputSize: size)).isEmpty, "nowhere to land with nobody there")

        var sim = WorldButterflySim(size: size)
        var landed = false
        for _ in 0..<900 {
            sim.step(1.0 / 30, perches: perches, matte: you, disturbance: nil)
            if let b = sim.flies.first(where: { $0.state == .resting }) {
                landed = true
                XCTAssertGreaterThan(you.coverage(x: b.position.x, y: b.position.y - 12), 0.4, "resting on you")
                XCTAssertFalse(b.isBehind)
                break
            }
        }
        XCTAssertTrue(landed, "within half a minute one comes to rest on you")
        guard let resting = sim.flies.firstIndex(where: { $0.state == .resting }) else { return }
        sim.step(1.0 / 30, perches: perches, matte: you, disturbance: (sim.flies[resting].position + SIMD2(30, 0), 0.9))
        XCTAssertEqual(sim.flies[resting].state, .leaving, "a wave nearby sends it off")
        for i in 0..<300 { sim.step(i == 100 ? 6 : 1.0 / 30, perches: [], matte: nil, disturbance: nil) }
        XCTAssertTrue(sim.flies.allSatisfy { $0.state != .resting && $0.position.x.isFinite }, "with nobody there nothing rests")
        XCTAssertTrue(sim.flies.allSatisfy { $0.position.x > -60 && $0.position.x < 1340 && $0.position.y > -60 && $0.position.y < 780 })
    }

    func testTheSameSeedFliesTheSameWay() {
        var a = WorldButterflySim(size: size, seed: 4), b = WorldButterflySim(size: size, seed: 4)
        let perches = WorldButterflySim.perches(in: you)
        for _ in 0..<200 {
            a.step(1.0 / 30, perches: perches, matte: you, disturbance: nil)
            b.step(1.0 / 30, perches: perches, matte: you, disturbance: nil)
        }
        XCTAssertEqual(a.flies.map(\.position), b.flies.map(\.position))
    }

    // MARK: Polished older filters

    func testSnowAlreadyInFrontOfYouFallsPastInsteadOfSticking() {
        var field = SnowField(size: size)
        let block = MatteGrid.filled([CGRect(x: 0, y: 0, width: 1280, height: 720)], outputSize: size)
        // Fill the sky with nobody there, then step in front of all of it at once.
        for _ in 0..<120 { field.step(1.0 / 30, matte: nil) }
        let inView = field.particles.particles.filter { $0.position.y < 700 }.count
        field.step(1.0 / 30, matte: block)
        XCTAssertGreaterThan(inView, 300)
        XCTAssertLessThanOrEqual(field.landedCount, 3, "flakes only land by coming down onto you: just the odd new one at the top")
    }

    func testGhostTrailsKeepAFewCopiesAndForgetThem() {
        let lens = GhostTrailsLens()
        let base = h.input()
        for i in 0..<60 { _ = lens.render(h.at(base, time: Double(i) / 30)) }
        XCTAssertGreaterThan(lens.echoCount, 5)
        XCTAssertLessThanOrEqual(lens.echoCount, Int(GhostTrailsLens.lifetime / GhostTrailsLens.interval) + 2, "only the last second is kept")
        _ = lens.render(h.at(base, time: 0))
        XCTAssertLessThanOrEqual(lens.echoCount, 1, "starting over forgets them")
    }

    func testConfettiBehindYouNeverLandsOnYou() {
        var field = ConfettiCannonSim(size: size)
        field.firesByItself = false
        for i in 0..<30 {
            field.insert(ConfettiCannonSim.Piece(position: SIMD2(560 + Double(i) * 6, 650), velocity: SIMD2(0, -120), angle: 0, spin: 0, flip: 0, flipRate: 0,
                                                 size: 14, colour: 1, shape: .rectangle, life: 30, swayPhase: 0, swayRate: 0, lightness: 0.5, depth: 0.1))
        }
        for _ in 0..<150 { field.step(1.0 / 30, matte: you) }
        XCTAssertEqual(field.restingCount, 0, "it passes behind you")
    }

    func testAuraSparksRiseFromYourTopAndSides() {
        let lens = AuraLens(style: .power)
        let base = h.input()
        _ = play(lens, base, frames: 20)
        XCTAssertGreaterThan(lens.sparkCount, 30)
        let rainbow = AuraLens(style: .rainbow)
        let out = play(rainbow, base, frames: 20, save: "aura-rainbow-new.png")
        // Round the outline the colours differ: the rainbow goes all the way round.
        let left = h.pixel(out, 522, 420), right = h.pixel(out, 758, 420)
        XCTAssertGreaterThan(abs(left.r - right.r) + abs(left.g - right.g) + abs(left.b - right.b), 30, "\(left) vs \(right)")
    }

    // MARK: Every new filter

    func testEveryNewFilterCopesWithNobodyAHugeDtAndARestart() {
        let base = h.input()
        let nobody = empty(base)
        for info in WorldFilters.all {
            let lens = info.make()
            let out = play(lens, base, frames: 4)
            XCTAssertEqual(out.extent, base.rect, info.name)
            var lonely = nobody.composed
            for i in 0..<20 { lonely = lens.render(h.at(nobody, time: Double(i) / 30)) }
            XCTAssertEqual(lonely.extent, base.rect, "\(info.name) with nobody there")
            let bitmap = h.bitmap(lonely)
            XCTAssertGreaterThan(bitmap.change(from: h.bitmap(nobody.composed), in: base.rect), 40, "\(info.name) still does something in an empty room")
            _ = lens.render(LensInput(time: 30, dt: 8, rect: base.rect, camera: base.camera, matte: base.matte, background: base.background,
                                      composed: base.composed, matteGrid: base.matteGrid, face: nil, services: base.services))
            lens.restart()
            XCTAssertEqual(lens.render(h.at(base, time: 0)).extent, base.rect, "\(info.name) after a restart")
        }
    }

    /// What each filter in the area adds to a frame, printed so it can be watched. The 9 ms gate for the catalog filters is
    /// `WorldFilterTests.testEveryWorldFilterIsCheap`; this one only catches something that has become several times slower.
    func testWhatEachWorldFilterCosts() {
        let base = h.input()
        let buffer = h.compositor.makeOutputBuffer()!
        func median(_ lens: Lens) -> Double {
            var times: [Double] = []
            for i in 0..<80 {
                let started = CFAbsoluteTimeGetCurrent()
                h.compositor.render(lens.render(h.at(base, time: Double(i) / 30)), into: buffer)
                if i >= 20 { times.append((CFAbsoluteTimeGetCurrent() - started) * 1000) }
            }
            return times.sorted()[times.count / 2]
        }
        final class Nothing: Lens {
            let needs: LensNeeds = []
            func render(_ input: LensInput) -> CIImage { input.composed }
        }
        let baseline = median(Nothing())
        for info in WorldFilterGalleryTests.items {
            let added = median(info.make()) - baseline
            print(String(format: "WORLD-COST %@ adds %.2f ms", info.name, added))
            XCTAssertLessThan(added, 20, info.name)
        }
    }

    func testTheFirstFrameOfEachFilterIsQuick() {
        let base = h.input()
        for info in WorldFilters.all + [LensCatalog.info(for: "aura"), LensCatalog.info(for: "snow"), LensCatalog.info(for: "ghost-trails")].compactMap({ $0 }) {
            let made = CFAbsoluteTimeGetCurrent()
            let lens = info.make()
            let built = (CFAbsoluteTimeGetCurrent() - made) * 1000
            XCTAssertLessThan(built, 30, "\(info.name) takes \(Int(built)) ms to make, on the main thread")
            let started = CFAbsoluteTimeGetCurrent()
            _ = h.bitmap(lens.render(h.at(base, time: 0)))
            let first = (CFAbsoluteTimeGetCurrent() - started) * 1000
            print(String(format: "WORLD-FIRST %@ make %.1f ms, first frame %.1f ms", info.name, built, first))
            // Generous: these run unoptimised on a shared machine. Catches baking something big on the first frame.
            XCTAssertLessThan(first, 250, "\(info.name) first frame")
        }
    }
}
