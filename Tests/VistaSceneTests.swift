import CoreImage
import XCTest

/// A silhouette that is solid rectangles, or nothing.
private struct VistaBlocks: MatteQuery {
    var rects: [CGRect] = []
    func coverage(x: Double, y: Double) -> Double { rects.contains { $0.contains(CGPoint(x: x, y: y)) } ? 1 : 0 }
}

/// Where the picture changed since the last frame, with a strength the test chooses.
private struct VistaMotion: MatteQuery {
    var rect: CGRect
    var strength = 1.0
    func coverage(x: Double, y: Double) -> Double { rect.contains(CGPoint(x: x, y: y)) ? strength : 0 }
}

private let vistaFrame = CGSize(width: 1280, height: 720)
/// A person sitting in the middle of the frame: head and shoulders, much as the synthetic scene draws them.
private let vistaHead = CGRect(x: 540, y: 300, width: 200, height: 258)
private let vistaBody = CGRect(x: 370, y: 0, width: 540, height: 290)
private let vistaPerson = VistaBlocks(rects: [vistaBody, vistaHead])

/// Every Vista scene, with a fresh stage, so the same checks run on each.
private func vistaStages() -> [(name: String, make: () -> VistaStage)] {
    [("arctic", { VistaArcticStage() }), ("space", { VistaSpaceStage() }), ("dragon castle", { VistaDragonStage() }), ("forest", { VistaForestStage() }), ("pirate cove", { VistaPirateStage() })]
}

private func vistaSpecies(_ cast: VistaCast, _ id: Int) -> VistaSpecies { cast.species[cast.roster[id]] }

private func vistaStepAll(_ world: inout VistaWorld, seconds: Double, context: VistaContext, every: ((VistaWorld) -> Void)? = nil) {
    for _ in 0..<Int(seconds * 30) {
        world.step(1.0 / 30, context: context)
        every?(world)
    }
}

private func vistaDistance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { hypot(a.x - b.x, a.y - b.y) }

final class VistaModelTests: XCTestCase {
    private func context(person: Bool = true, motion: MatteQuery? = nil, hands: [HandState] = []) -> VistaContext {
        VistaContext(size: vistaFrame, matte: person ? vistaPerson : nil, motion: motion, hands: hands)
    }

    func testTheCreaturesFindThePersonFromTheirSilhouette() throws {
        let person = try XCTUnwrap(VistaPerson.find(in: vistaPerson, size: vistaFrame))
        XCTAssertEqual(Double(person.box.minX), 370, accuracy: 40)
        XCTAssertEqual(Double(person.top), 558, accuracy: 8)
        XCTAssertEqual(Double(person.head.x), 640, accuracy: 20)
        XCTAssertNil(VistaPerson.find(in: VistaBlocks(), size: vistaFrame), "an empty room has nobody in it")
    }

    func testWithNobodyThereTheyWanderAndNoneTakesAnInterest() {
        for (name, make) in vistaStages() {
            let cast = make().cast
            var world = VistaWorld(cast: cast, seed: 3)
            var noticed = false
            var moved = Set<Int>()
            let start = world.creatures.map(\.pos)
            vistaStepAll(&world, seconds: 40, context: context(person: false)) { w in
                if w.creatures.contains(where: { $0.phase == .noticing || $0.phase == .approaching || $0.phase == .acting }) { noticed = true }
                for c in w.creatures where c.phase != .away && vistaDistance(c.pos, start[c.id]) > 40 { moved.insert(c.id) }
            }
            XCTAssertFalse(noticed, "\(name): nobody there to notice")
            XCTAssertGreaterThanOrEqual(moved.count, 4, "\(name): the creatures are going about their day")
        }
    }

    func testAFirstTimeViewerSeesSomethingHappenWithinAFewSeconds() {
        for (name, make) in vistaStages() {
            var world = VistaWorld(cast: make().cast, seed: 11)
            var firstNotice: Double?, firstAct: Double?
            vistaStepAll(&world, seconds: 10, context: context()) { w in
                if firstNotice == nil, w.creatures.contains(where: { $0.phase == .noticing }) { firstNotice = w.time }
                if firstAct == nil, w.creatures.contains(where: { $0.phase == .acting }) { firstAct = w.time }
            }
            XCTAssertLessThan(firstNotice ?? 99, 3.0, "\(name): something notices you almost at once")
            XCTAssertLessThan(firstAct ?? 99, 9.0, "\(name): and something is doing its thing within a few seconds")
            XCTAssertGreaterThanOrEqual(world.creatures.filter { $0.phase != .away }.count, 5, "\(name): the place is already lived in")
        }
    }

    func testEveryKindNoticesComesOverActsAndGoesBackToItsLife() {
        for (name, make) in vistaStages() {
            for seed in [21, 4] as [UInt64] {
                everyKindActs(name, make().cast, seed: seed)
            }
        }
    }

    private func everyKindActs(_ name: String, _ cast: VistaCast, seed: UInt64) {
        var world = VistaWorld(cast: cast, seed: seed)
        var seen = [Set<String>](repeating: [], count: cast.roster.count)
        var returned = Set<Int>()
        var lastPhase = world.creatures.map(\.phase)
        vistaStepAll(&world, seconds: 240, context: context()) { w in
            for c in w.creatures {
                if c.phase != lastPhase[c.id] {
                    seen[c.id].insert("\(c.phase)")
                    if seen[c.id].contains("acting"), c.phase == .wandering { returned.insert(c.id) }
                }
                lastPhase[c.id] = c.phase
            }
        }
        let actors = seen.indices.filter { seen[$0].contains("acting") }
        XCTAssertGreaterThanOrEqual(actors.count, cast.roster.count / 2, "\(name): most of the cast gets round to you in four minutes")
        let kinds = Set(actors.map { cast.roster[$0] })
        XCTAssertEqual(kinds.count, cast.species.count, "\(name) seed \(seed): every kind does its thing (missing: \(cast.species.indices.filter { !kinds.contains($0) }.map { cast.species[$0].name }))")
        for id in actors where vistaSpecies(cast, id).body != .prop {
            XCTAssertTrue(seen[id].contains("noticing") && seen[id].contains("approaching"), "\(name) \(vistaSpecies(cast, id).name): looks, then comes")
        }
        XCTAssertGreaterThanOrEqual(returned.count, max(1, actors.count - 2), "\(name): and then goes back to its life")
    }

    func testNothingInFrontOfThePersonEverCoversTheirFace() {
        for (name, make) in vistaStages() {
            let cast = make().cast
            for seed in [1, 2, 3] as [UInt64] {
                var world = VistaWorld(cast: cast, seed: seed)
                var worst = 0.0
                var offender = ""
                vistaStepAll(&world, seconds: 180, context: context()) { w in
                    guard let person = w.person else { return }
                    for c in w.creatures where c.phase != .away && c.depth >= w.layout.frontDepth {
                        let overlap = w.bounds(of: c).intersection(person.faceZone)
                        if !overlap.isNull, overlap.width * overlap.height > worst {
                            worst = Double(overlap.width * overlap.height)
                            offender = "\(w.cast.species[c.species].name) in \(c.phase)"
                        }
                    }
                }
                XCTAssertEqual(worst, 0, "\(name) seed \(seed): \(offender) sat on the face")
            }
        }
    }

    func testWavingYourArmsSendsThemRunning() {
        for (name, make) in vistaStages() {
            let cast = make().cast
            var world = VistaWorld(cast: cast, seed: 31)
            vistaStepAll(&world, seconds: 6, context: context())
            let wave = VistaMotion(rect: CGRect(x: 100, y: 100, width: 1080, height: 540))
            var fled = false
            vistaStepAll(&world, seconds: 1.5, context: context(motion: wave)) { w in
                if w.creatures.contains(where: { $0.phase == .fleeing }) { fled = true }
            }
            XCTAssertTrue(fled, "\(name): somebody bolts")
            let timid = world.creatures.filter { [.prey, .curious].contains(vistaSpecies(cast, $0.id).temper) && $0.phase != .away && $0.phase != .entering }
            XCTAssertTrue(timid.allSatisfy { $0.phase == .fleeing }, "\(name): everything that can run is running (\(timid.map { "\($0.phase)" }))")
        }
    }

    func testSteppingIntoThePictureOrFidgetingFrightensNobody() {
        for (name, make) in vistaStages() {
            let cast = make().cast
            var world = VistaWorld(cast: cast, seed: 2)
            let flurry = VistaMotion(rect: CGRect(x: 0, y: 0, width: 1280, height: 720))
            var scared = false
            vistaStepAll(&world, seconds: 1.1, context: context(motion: flurry)) { w in
                if w.creatures.contains(where: { $0.phase == .fleeing || $0.phase == .backingOff }) { scared = true }
            }
            XCTAssertFalse(scared, "\(name): coming into view is not a wave")
            let flicker = VistaMotion(rect: CGRect(x: 0, y: 0, width: 1280, height: 720), strength: 0.25)
            vistaStepAll(&world, seconds: 15, context: context(motion: flicker)) { w in
                if w.creatures.contains(where: { $0.phase == .fleeing || $0.phase == .backingOff }) { scared = true }
            }
            XCTAssertFalse(scared, "\(name): matte flicker is not a wave")
        }
    }

    func testItCopesWithAPersonWhoFillsTheFrameIsTinyOrSitsAtTheEdge() {
        let shapes: [(String, VistaBlocks)] = [
            ("filling the frame", VistaBlocks(rects: [CGRect(x: 0, y: 0, width: 1280, height: 300), CGRect(x: 480, y: 280, width: 320, height: 420)])),
            ("far away", VistaBlocks(rects: [CGRect(x: 580, y: 180, width: 120, height: 120), CGRect(x: 615, y: 290, width: 50, height: 70)])),
            ("at the left edge", VistaBlocks(rects: [CGRect(x: 0, y: 0, width: 330, height: 280), CGRect(x: 90, y: 270, width: 150, height: 250)])),
        ]
        for (name, make) in vistaStages() {
            let cast = make().cast
            for (shape, matte) in shapes {
                var world = VistaWorld(cast: cast, seed: 17)
                var acted = false
                var worst = 0.0
                for _ in 0..<(30 * 150) {
                    world.step(1.0 / 30, context: VistaContext(size: vistaFrame, matte: matte))
                    guard let person = world.person else { continue }
                    for c in world.creatures {
                        XCTAssertTrue(c.pos.x.isFinite && c.pos.y.isFinite, "\(name) \(shape)")
                        if c.phase == .acting { acted = true }
                        guard c.phase != .away, c.depth >= world.layout.frontDepth else { continue }
                        let overlap = world.bounds(of: c).intersection(person.faceZone)
                        if !overlap.isNull { worst = max(worst, Double(overlap.width * overlap.height)) }
                    }
                }
                XCTAssertTrue(acted, "\(name), person \(shape): somebody still comes to you")
                XCTAssertEqual(worst, 0, "\(name), person \(shape): and still keeps off your face")
            }
        }
    }

    func testTheSameSeedAndTheSameViewGiveTheSameDay() {
        for (name, make) in vistaStages() {
            let cast = make().cast
            var a = VistaWorld(cast: cast, seed: 77), b = VistaWorld(cast: cast, seed: 77), c = VistaWorld(cast: cast, seed: 78)
            let wave = VistaMotion(rect: CGRect(x: 300, y: 100, width: 700, height: 500))
            for i in 0..<(30 * 40) {
                let ctx = context(person: i < 900 || i > 960, motion: i % 400 < 20 ? wave : nil)
                a.step(1.0 / 30, context: ctx); b.step(1.0 / 30, context: ctx); c.step(1.0 / 30, context: ctx)
            }
            XCTAssertEqual(a.creatures.map(\.pos.x), b.creatures.map(\.pos.x), "\(name)")
            XCTAssertEqual(a.creatures.map { "\($0.phase)" }, b.creatures.map { "\($0.phase)" }, "\(name)")
            XCTAssertNotEqual(a.creatures.map(\.pos.x), c.creatures.map(\.pos.x), "\(name): another seed is another day")
        }
    }

    func testThereAreNeverMoreThanAHandfulOnScreen() {
        for (name, make) in vistaStages() {
            let cast = make().cast
            XCTAssertLessThanOrEqual(cast.roster.count, 12, "\(name)")
            XCTAssertGreaterThanOrEqual(cast.roster.count, 8, "\(name)")
            XCTAssertGreaterThanOrEqual(cast.species.count, 5, "\(name): five or more kinds of creature")
            XCTAssertLessThanOrEqual(cast.species.count, 8, "\(name)")
            var world = VistaWorld(cast: cast, seed: 5)
            var most = 0
            let wave = VistaMotion(rect: CGRect(x: 100, y: 100, width: 1080, height: 540))
            for i in 0..<(30 * 120) {
                world.step(1.0 / 30, context: context(motion: i % 600 < 30 ? wave : nil))
                most = max(most, world.creatures.filter { $0.phase != .away }.count)
            }
            XCTAssertLessThanOrEqual(most, 12, "\(name)")
            XCTAssertLessThanOrEqual(most, cast.cap)
        }
    }

    func testAHugeTimeStepOrAMissingPersonDoesNotBreakAnything() {
        for (name, make) in vistaStages() {
            let cast = make().cast
            var world = VistaWorld(cast: cast, seed: 9)
            world.step(0, context: context())
            world.step(30, context: context())
            world.step(-1, context: context())
            world.step(0.2, context: VistaContext(size: vistaFrame))
            vistaStepAll(&world, seconds: 10, context: context())
            vistaStepAll(&world, seconds: 10, context: context(person: false))
            for c in world.creatures {
                XCTAssertTrue(c.pos.x.isFinite && c.pos.y.isFinite && abs(c.pos.x) < 3000 && abs(c.pos.y) < 3000, "\(name) \(vistaSpecies(cast, c.id).name) is somewhere sensible: \(c.pos)")
                XCTAssertTrue(c.depth >= 0 && c.depth <= 1)
                XCTAssertTrue(c.rise >= 0 && c.rise <= 1.0001)
            }
            XCTAssertTrue(world.creatures.allSatisfy { $0.phase != .acting && $0.phase != .approaching }, "\(name): with nobody to come to, they stop coming")
        }
    }

    func testABirdLandsOnARaisedOpenHandAndFliesOffWhenItGoes() throws {
        for (name, make) in vistaStages() {
            let cast = make().cast
            let birds = cast.roster.indices.filter { vistaSpecies(cast, $0).perchesOnHand }
            XCTAssertFalse(birds.isEmpty, "\(name): something here lands on a hand")
            var world = VistaWorld(cast: cast, seed: 14)
            let hand = HandFixtures.openPalm(at: CGPoint(x: 1010, y: 330), size: 90)
            let knuckle = hand[.middleMCP], tip = hand[.middleTip]
            let palm = CGPoint(x: knuckle.x + (tip.x - knuckle.x) * 0.55, y: knuckle.y + (tip.y - knuckle.y) * 0.55)
            var landed: Int?
            var waited = 0.0
            while landed == nil, waited < 25 {
                world.step(1.0 / 30, context: context(hands: [hand]))
                waited += 1.0 / 30
                landed = birds.first { id in
                    let c = world.creatures[id]
                    return c.phase == .acting && c.landedAt != nil && c.onHand && abs(c.pos.x - Double(palm.x)) < 60 && abs(c.pos.y - Double(palm.y)) < 100
                }
            }
            let bird = try XCTUnwrap(landed, "\(name): a bird sits on your hand within 25 seconds")
            vistaStepAll(&world, seconds: 1, context: context(hands: [hand]))
            // Tracking blinks out for a moment: it stays.
            vistaStepAll(&world, seconds: 0.33, context: context())
            XCTAssertEqual(world.creatures[bird].phase, .acting, "\(name): a flicker of tracking does not shake it off")
            vistaStepAll(&world, seconds: 3, context: context())
            XCTAssertNotEqual(world.creatures[bird].phase, .acting, "\(name): and it flies off when the hand is gone")
        }
    }

    func testOnlyOneBirdLandsOnAHandAtATime() {
        for (name, make) in vistaStages() {
            var world = VistaWorld(cast: make().cast, seed: 3)
            let hand = HandFixtures.openPalm(at: CGPoint(x: 1010, y: 330), size: 90)
            var most = 0
            vistaStepAll(&world, seconds: 60, context: context(hands: [hand])) { w in
                most = max(most, w.creatures.filter { $0.onHand && $0.phase == .acting }.count)
            }
            XCTAssertLessThanOrEqual(most, 1, "\(name): one bird to a hand")
        }
    }
}

// MARK: - What each place's creatures do

final class VistaInteractionTests: XCTestCase {
    private let ctx = VistaContext(size: vistaFrame, matte: vistaPerson)

    /// Steps until the first creature of a kind is doing its thing, after sending it over.
    private func untilActing(_ world: inout VistaWorld, _ name: String, seconds: Double = 40, every: ((VistaWorld, VistaCreature) -> Void)? = nil) -> Int? {
        guard let id = world.creatures.first(where: { world.cast.species[$0.species].name == name })?.id else { return nil }
        vistaStepAll(&world, seconds: 2, context: ctx)
        world.attract(id)
        for _ in 0..<Int(seconds * 30) {
            world.step(1.0 / 30, context: ctx)
            every?(world, world.creatures[id])
            if world.creatures[id].phase == .acting { return id }
            if world.creatures[id].phase == .wandering, world.creatures[id].cooldown > 0 { world.attract(id) }
        }
        return nil
    }

    func testTheDragonBreathesFireBesideYouNeverOnYou() throws {
        var world = VistaWorld(cast: VistaDragonCast.cast, seed: 4)
        let dragon = try XCTUnwrap(untilActing(&world, "dragon"), "the dragon comes down to you")
        let person = try XCTUnwrap(world.person)
        let c = world.creatures[dragon]
        XCTAssertLessThan(c.depth, world.layout.frontDepth, "it stays behind you, so its fire is behind you too")
        let aimX = c.aim.x
        XCTAssertTrue(aimX < Double(person.box.minX) || aimX > Double(person.box.maxX), "the fire lands on the ground beside you (aim \(aimX), you \(person.box))")
        XCTAssertFalse(person.faceZone.contains(CGPoint(x: c.aim.x, y: c.aim.y)))
        var embers = 0
        vistaStepAll(&world, seconds: 2, context: ctx) { w in embers = max(embers, w.effectsBehind.particles.filter { $0.kind == VistaFX.ember.rawValue }.count) }
        XCTAssertGreaterThan(embers, 5, "sparks fly")
    }

    func testTheSaucerHoversOverYouAndBeamsSparklesUpAroundYou() throws {
        var world = VistaWorld(cast: VistaSpaceCast.cast, seed: 4)
        let saucer = try XCTUnwrap(untilActing(&world, "flying saucer"))
        vistaStepAll(&world, seconds: 1.5, context: ctx)
        let person = try XCTUnwrap(world.person)
        let c = world.creatures[saucer]
        XCTAssertEqual(c.phase, .acting)
        XCTAssertGreaterThan(c.pos.y, Double(person.top), "it hangs above your head")
        let sparkles = world.effectsBehind.particles.filter { $0.kind == VistaFX.sparkle.rawValue }
        XCTAssertGreaterThan(sparkles.count, 5, "the beam lifts sparkles round you")
        XCTAssertTrue(sparkles.allSatisfy { $0.position.x > Double(person.box.minX) - 80 && $0.position.x < Double(person.box.maxX) + 80 })
    }

    func testThingsThatRiseUpBehindYouRiseFallAndStayBehind() throws {
        for (cast, name) in [(VistaArcticCast.cast, "narwhal"), (VistaPirateCast.cast, "kraken"), (VistaForestCast.cast, "giant cat")] {
            var world = VistaWorld(cast: cast, seed: 6)
            var behind = true
            let id = try XCTUnwrap(untilActing(&world, name, every: { w, c in if c.depth >= w.layout.frontDepth { behind = false } }), "\(name) comes over")
            var highest = 0.0
            vistaStepAll(&world, seconds: 6, context: ctx) { w in
                let c = w.creatures[id]
                highest = max(highest, c.rise)
                if c.depth >= w.layout.frontDepth { behind = false }
            }
            XCTAssertGreaterThan(highest, 0.95, "\(name) rises all the way up")
            XCTAssertLessThan(world.creatures[id].rise, 0.4, "\(name) sinks back down afterwards")
            XCTAssertTrue(behind, "\(name) is always behind you")
        }
    }

    func testTheTreasureChestStaysPutOpensAndSnapsShutWhenYouWave() throws {
        var world = VistaWorld(cast: VistaPirateCast.cast, seed: 8)
        let chest = try XCTUnwrap(world.creatures.firstIndex { world.cast.species[$0.species].name == "treasure chest" })
        let home = world.creatures[chest].pos
        XCTAssertNotEqual(world.creatures[chest].phase, .away, "it is there from the start")
        XCTAssertNotNil(untilActing(&world, "treasure chest"), "it opens for you")
        var coins = 0
        vistaStepAll(&world, seconds: 1.6, context: ctx) { w in coins = max(coins, w.effects.particles.filter { $0.kind == VistaFX.coin.rawValue }.count) }
        XCTAssertGreaterThan(coins, 5, "gold spills out")
        let wave = VistaMotion(rect: CGRect(x: 100, y: 100, width: 1080, height: 540))
        vistaStepAll(&world, seconds: 0.5, context: VistaContext(size: vistaFrame, matte: vistaPerson, motion: wave))
        XCTAssertEqual(world.creatures[chest].phase, .backingOff, "it snaps shut")
        vistaStepAll(&world, seconds: 30, context: ctx)
        XCTAssertEqual(world.creatures[chest].pos, home, "and never walks off")
        XCTAssertNotEqual(world.creatures[chest].phase, .away)
    }

    func testPenguinsComeOverOnTheirBellies() throws {
        var world = VistaWorld(cast: VistaArcticCast.cast, seed: 2)
        var slid = false
        _ = try XCTUnwrap(untilActing(&world, "penguin", every: { _, c in if c.phase == .approaching, c.slide > 0.9 { slid = true } }))
        XCTAssertTrue(slid, "a penguin in a hurry slides")
    }

    func testTheGreeterArrivesQuicklyInEveryPlace() {
        for (name, make) in vistaStages() {
            var world = VistaWorld(cast: make().cast, seed: 30)
            var acted: Double?
            vistaStepAll(&world, seconds: 10, context: ctx) { w in
                if acted == nil, w.creatures.contains(where: { $0.phase == .acting }) { acted = w.time }
            }
            XCTAssertLessThan(acted ?? 99, 9, "\(name): someone comes to say hello within a few seconds")
        }
    }
}

// MARK: - Drawing

final class VistaRenderTests: XCTestCase {
    private let h = LensHarness()

    func testEveryNewSceneRendersAtFullSizeWithAndWithoutAPersonAndWithHands() throws {
        XCTAssertFalse(SceneCatalogMore.all.isEmpty)
        let base = h.input(background: false)
        let hand = HandFixtures.openPalm(at: CGPoint(x: 1000, y: 340), size: 90)
        for info in SceneCatalogMore.all {
            let lens = info.make()
            XCTAssertEqual(info.category, .scenes)
            XCTAssertTrue(info.showsText, "\(info.name): its creatures talk")
            XCTAssertTrue(lens.needs.contains(.matte), "\(info.name)")
            XCTAssertTrue(lens.wantsMatteGrid)
            XCTAssertNotNil(lens.status, "\(info.name) has a hint")
            var out = base.composed
            for i in 0..<24 { out = lens.render(h.at(base, time: Double(i) / 30, hands: lens.needs.contains(.hands) ? [hand] : [])) }
            XCTAssertEqual(out.extent, base.rect, info.name)
            Output.save(out, as: "vista-\(info.id)-person.png")

            let face = h.pixel(out, 640, 400), plain = h.pixel(base.composed, 640, 400)
            XCTAssertLessThan(abs(face.r - plain.r) + abs(face.g - plain.g) + abs(face.b - plain.b), 60, "\(info.name): your face is not covered")
            let corner = h.pixel(out, 30, 690), room = h.pixel(base.composed, 30, 690)
            XCTAssertGreaterThan(abs(corner.r - room.r) + abs(corner.g - room.g) + abs(corner.b - room.b), 30, "\(info.name): the room is gone")

            let empty = LensInput(time: 0, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: nil, background: nil, composed: base.camera, matteGrid: nil,
                                  face: nil, services: base.services)
            let lonely = info.make()
            var alone = base.camera
            for _ in 0..<20 { alone = lonely.render(empty) }
            XCTAssertEqual(alone.extent, base.rect, "\(info.name) with no one in view")
            Output.save(alone, as: "vista-\(info.id)-empty.png")
            let blank = LensInput(time: 0, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: base.matte, background: nil, composed: base.camera,
                                  matteGrid: MatteGrid(outputSize: base.rect.size), face: nil, services: base.services)
            XCTAssertEqual(info.make().render(blank).extent, base.rect, "\(info.name) with an empty matte")
        }
    }

    func testTheCatalogEntriesAreWiredUpRight() {
        let ids = SceneCatalogMore.all.map(\.id) + SceneCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "no id is used twice")
        for info in SceneCatalogMore.all {
            XCTAssertTrue(info.id.hasPrefix("scene-"), info.id)
            XCTAssertEqual(info.glyph.count, 1, "\(info.name): the glyph is one emoji")
            XCTAssertFalse(info.blurb.isEmpty)
            XCTAssertLessThan(info.blurb.count, 120, "\(info.name): the blurb is one short sentence")
            let lens = info.make()
            XCTAssertEqual(lens.needs.contains(.hands), info.needsHands, info.name)
            XCTAssertEqual(lens.needs.contains(.face), info.needsFace, info.name)
            XCTAssertFalse(lens.status?.title.isEmpty ?? true, "\(info.name) says what to do")
        }
    }

    func testTheSceneFadesInAndRestartingGivesAFreshWorld() {
        let lens = VistaLens(stage: VistaArcticStage(), seed: 3)
        let base = h.input(background: false)
        let first = lens.render(h.at(base, time: 0))
        let corner = h.pixel(first, 30, 690), room = h.pixel(base.composed, 30, 690)
        XCTAssertLessThan(abs(corner.r - room.r) + abs(corner.g - room.g) + abs(corner.b - room.b), 60, "the first frame is still mostly the room")
        for i in 1..<60 { _ = lens.render(h.at(base, time: Double(i) / 30)) }
        XCTAssertTrue(lens.isPainted, "all the painting is done within a couple of seconds")
        XCTAssertGreaterThan(lens.world.time, 1.9)
        lens.restart()
        XCTAssertEqual(lens.world.time, 0)
    }
}

/// Seconds of work done by this thread so far. Unlike the wall clock, it does not count time spent waiting for a busy machine.
private func vistaThreadTime() -> Double {
    var now = timespec()
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &now)
    return Double(now.tv_sec) + Double(now.tv_nsec) / 1e9
}

/// A lens that does nothing, to measure what an ordinary frame costs on this machine at this moment.
private final class VistaDoNothingLens: Lens {
    let needs: LensNeeds = [.matte]
    func render(_ input: LensInput) -> CIImage { input.composed }
}

final class VistaCostTests: XCTestCase {
    private let h = LensHarness()

    /// What a frame of a lens costs this thread: making the picture and rendering it out, over and above a lens that does nothing.
    /// Measured as the thread's own working time, so that a machine busy with other work does not make a scene look slow.
    private func cost(of lens: Lens, base: LensInput, frames: Int, from start: Int) -> Double {
        let buffer = h.compositor.makeOutputBuffer()!
        let started = vistaThreadTime()
        for i in 0..<frames { h.compositor.render(lens.render(h.at(base, time: Double(start + i) / 30)), into: buffer) }
        return (vistaThreadTime() - started) * 1000 / Double(frames)
    }

    func testEveryNewSceneIsCheapEnoughToRunEveryFrame() {
        let base = h.input(background: false)
        for info in SceneCatalogMore.all {
            let lens = info.make()
            for i in 0..<60 { _ = lens.render(h.at(base, time: Double(i) / 30)) }       // let the creatures come out
            let plain = cost(of: VistaDoNothingLens(), base: base, frames: 60, from: 0)
            let mean = cost(of: lens, base: base, frames: 240, from: 60)
            print(String(format: "VISTA COST %@: %.2f ms a frame over a plain %.2f", info.name as NSString, mean - plain, plain))
            XCTAssertLessThan(mean - plain, 5.0, "\(info.name) costs \(String(format: "%.1f", mean - plain)) ms a frame")
        }
    }

    /// Where a frame's time goes, piece by piece, printed for whoever is tuning a scene.
    func testWhereTheTimeGoes() throws {
        let canvas = try XCTUnwrap(CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: Sprites.bitmapInfo))
        let base = h.input(background: false)
        for (name, make) in vistaStages() {
            let fresh = make()
            let steps = (0..<fresh.bakeSteps).map { i -> String in
                let started = vistaThreadTime()
                fresh.bake(step: i)
                return String(format: "%.1f", (vistaThreadTime() - started) * 1000)
            }
            print("VISTA BAKE \(name): " + steps.joined(separator: " ") + " ms")
            let stage = make()
            let lens = VistaLens(stage: stage, seed: 5)
            for i in 0..<120 { _ = lens.render(h.at(base, time: Double(i) / 30)) }
            let frame = VistaFrame(time: 4, size: vistaFrame, shift: .zero, person: lens.world.person)
            // Time this thread spent working, so that other work on a busy machine does not count.
            func time(_ body: () -> Void) -> Double {
                let started = vistaThreadTime()
                for _ in 0..<30 { body() }
                return (vistaThreadTime() - started) * 1000 / 30
            }
            let backdrop = time { canvas.clear(CGRect(origin: .zero, size: vistaFrame)); stage.paintBackdrop(canvas, frame) }
            let foreground = time { canvas.clear(CGRect(origin: .zero, size: vistaFrame)); stage.paintForeground(canvas, frame) }
            let whole = time { _ = lens.render(h.at(base, time: 4)) }
            lens.drawsCreatures = false
            let empty = time { _ = lens.render(h.at(base, time: 4)) }
            lens.drawsCreatures = true
            lens.tintsDistance = false
            let untinted = time { _ = lens.render(h.at(base, time: 4)) }
            lens.tintsDistance = true
            // The same, for one of the first five scenes, to compare under the same load.
            let safari = SceneLens(style: SafariScene(), hands: true, seed: 5)
            for i in 0..<120 { _ = safari.render(h.at(base, time: Double(i) / 30)) }
            let reference = time { _ = safari.render(h.at(base, time: 4)) }
            print(String(format: "VISTA TIME %@: backdrop %.2f ms, foreground %.2f ms, whole render call %.2f ms, without creatures %.2f ms, without haze %.2f ms; safari render call %.2f ms",
                         name as NSString, backdrop, foreground, whole, empty, untinted, reference))
        }
    }

    func testMakingASceneIsInstantAndNoFrameHitches() {
        let base = h.input(background: false)
        for info in SceneCatalogMore.all {
            let started = vistaThreadTime()
            let lens = info.make()
            let make = (vistaThreadTime() - started) * 1000
            XCTAssertLessThan(make, 20, "\(info.name) took \(Int(make)) ms to make")
            var slowest = 0.0
            for i in 0..<12 {
                let begun = vistaThreadTime()
                _ = lens.render(h.at(base, time: Double(i) / 30))
                slowest = max(slowest, (vistaThreadTime() - begun) * 1000)
            }
            print(String(format: "VISTA FIRST FRAMES %@: make %.1f ms, slowest of the first twelve frames %.1f ms", info.name as NSString, make, slowest))
            XCTAssertLessThan(slowest, 40, "\(info.name): the painting is spread over the first frames, not done in one")
        }
    }
}

/// The new scenes in the real frame pipeline, next to one of the first five, taking turns so that a busy machine weighs on both alike.
final class VistaPipelineCostTests: XCTestCase {
    func testInThePipelineTheNewScenesCostAboutWhatTheFirstOnesDo() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BACKDROP_PERF"] != nil, "set TEST_RUNNER_BACKDROP_PERF=1 to measure")
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 420))
        let camera = scene.cameraBuffer()
        func measure(_ make: () -> Lens?) -> (wall: Double, cpu: Double) {
            let pipeline = FramePipeline()
            pipeline.matteOverride = { _ in scene.matteBuffer() }
            pipeline.handsOverride = { [] }
            let gradient = Background(id: UUID(), name: "g", kind: .gradient(.graphite), origin: .builtIn)
            pipeline.setBackground(gradient, source: GradientSource(preset: .graphite))
            pipeline.setLens(make())
            pipeline.onOutput = { _, _ in }
            var wall = 0.0, cpu = 0.0
            for i in 0..<75 {
                let started = CFAbsoluteTimeGetCurrent()
                var thread = 0.0
                pipeline.queue.sync {
                    let begun = vistaThreadTime()
                    pipeline.process(camera, at: .zero)
                    thread = vistaThreadTime() - begun
                }
                if i >= 30 { wall += CFAbsoluteTimeGetCurrent() - started; cpu += thread }
            }
            return (wall * 1000 / 45, cpu * 1000 / 45)
        }
        let plain = measure { nil }
        print(String(format: "VISTA PIPELINE no lens: wall %.1f ms, cpu %.1f ms", plain.wall, plain.cpu))
        for info in SceneCatalog.all.prefix(1) + SceneCatalogMore.all {
            let r = measure { info.make() }
            print(String(format: "VISTA PIPELINE %@: wall +%.1f ms, cpu +%.1f ms", info.name as NSString, r.wall - plain.wall, r.cpu - plain.cpu))
            XCTAssertLessThan(r.cpu - plain.cpu, 9, info.name)
        }
    }
}

// MARK: - Pictures to look at

/// Pictures of the scenes, saved only when BACKDROP_TEST_OUTPUT is set. Nothing is asserted here.
final class VistaLookTests: XCTestCase {
    private let h = LensHarness()

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"] != nil, "set TEST_RUNNER_BACKDROP_TEST_OUTPUT to save pictures")
    }

    private func sheet(_ lens: VistaLens, scene: SyntheticScene = SyntheticScene(), seconds: Double, every: Double, name: String, hands: [HandState] = []) {
        let base = h.input(scene, background: false)
        var t = 0.0, next = every
        var tiles: [CIImage] = []
        while t < seconds {
            let out = lens.render(h.at(base, time: t, hands: hands))
            t += 1.0 / 30
            if t >= next {
                next += every
                let small = out.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
                if let cg = h.ciContext.createCGImage(small, from: small.extent) { tiles.append(CIImage(cgImage: cg)) }
            }
        }
        let columns = 3, rows = (tiles.count + columns - 1) / columns
        var sheet = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 640 * columns, height: 360 * rows))
        for (i, tile) in tiles.enumerated() {
            sheet = tile.transformed(by: CGAffineTransform(translationX: CGFloat(i % columns) * 640, y: CGFloat(rows - 1 - i / columns) * 360)).composited(over: sheet)
        }
        Output.save(sheet, as: "\(name).png")
    }

    /// Runs until a creature of `kind` has been doing its thing for `after` seconds, then saves that frame at full size.
    private func shot(_ make: () -> VistaStage, of kind: String, scene: SyntheticScene = SyntheticScene(), hands: [HandState] = [], name: String,
                      seconds: Double = 30, after: Double = 1.0) {
        let lens = VistaLens(stage: make(), seed: 5)
        lens.paintEverything()
        let base = h.input(scene, background: false)
        var t = 0.0
        for _ in 0..<3 { _ = lens.render(h.at(base, time: t, hands: hands)); t += 1.0 / 30 }
        lens.attract(kind)
        while t < seconds {
            let out = lens.render(h.at(base, time: t, hands: hands))
            t += 1.0 / 30
            if lens.world.creatures.contains(where: { lens.world.cast.species[$0.species].name == kind && $0.phase == .acting && $0.phaseTime > after }) {
                Output.save(out, as: "\(name).png")
                return
            }
        }
    }

    private func fleeSheet(_ make: () -> VistaStage, name: String) {
        let lens = VistaLens(stage: make(), seed: 5)
        var t = 0.0, next = 0.5
        var tiles: [CIImage] = []
        let still = h.input(SyntheticScene(), background: false)
        while t < 7 { _ = lens.render(h.at(still, time: t)); t += 1.0 / 30 }
        let start = t
        while t < start + 4.5 {
            let waving = t - start > 0.4 && t - start < 1.6
            let scene = SyntheticScene(center: CGPoint(x: 640 + (waving ? 150 * sin((t - start) * 16) : 0), y: 420 + (waving ? 40 * sin((t - start) * 23) : 0)))
            let out = lens.render(h.at(h.input(scene, background: false), time: t))
            t += 1.0 / 30
            if t - start >= next {
                next += 0.5
                let small = out.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
                if let cg = h.ciContext.createCGImage(small, from: small.extent) { tiles.append(CIImage(cgImage: cg)) }
            }
        }
        let columns = 3, rows = (tiles.count + columns - 1) / columns
        var sheet = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 640 * columns, height: 360 * rows))
        for (i, tile) in tiles.enumerated() {
            sheet = tile.transformed(by: CGAffineTransform(translationX: CGFloat(i % columns) * 640, y: CGFloat(rows - 1 - i / columns) * 360)).composited(over: sheet)
        }
        Output.save(sheet, as: "\(name).png")
    }

    private func everything(_ name: String, _ make: @escaping () -> VistaStage) {
        sheet(VistaLens(stage: make(), seed: 5), seconds: 24, every: 4, name: "vista-\(name)-sheet")
        sheet(VistaLens(stage: make(), seed: 5), scene: SyntheticScene(center: CGPoint(x: 360, y: 380), scale: 0.7, roll: 0.25), seconds: 18, every: 6,
              name: "vista-\(name)-tilted")
        let hand = HandFixtures.openPalm(at: CGPoint(x: 1010, y: 300), size: 100)
        for kind in make().cast.species.map(\.name) {
            let birdy = make().cast.species.first { $0.name == kind }?.perchesOnHand ?? false
            shot(make, of: kind, hands: birdy ? [hand] : [], name: "vista-\(name)-\(kind.replacingOccurrences(of: " ", with: "-"))", after: birdy ? 3.0 : 1.0)
        }
        fleeSheet(make, name: "vista-\(name)-flee")
    }

    func testArctic() { everything("arctic") { VistaArcticStage() } }
    func testSpace() { everything("space") { VistaSpaceStage() } }
    func testDragonCastle() { everything("dragon") { VistaDragonStage() } }
    func testEnchantedForest() { everything("forest") { VistaForestStage() } }
    func testPirateCove() { everything("pirate") { VistaPirateStage() } }
}
