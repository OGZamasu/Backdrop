import CoreImage
import XCTest

/// A silhouette that is solid rectangles, or nothing.
private struct SceneBlocks: MatteQuery {
    var rects: [CGRect] = []
    func coverage(x: Double, y: Double) -> Double { rects.contains { $0.contains(CGPoint(x: x, y: y)) } ? 1 : 0 }
}

/// Where the picture changed since the last frame, with a strength that the test chooses.
private struct SceneMotion: MatteQuery {
    var rect: CGRect
    var strength = 1.0
    func coverage(x: Double, y: Double) -> Double { rect.contains(CGPoint(x: x, y: y)) ? strength : 0 }
}

private let sceneFrame = CGSize(width: 1280, height: 720)
/// A person sitting in the middle of the frame: head and shoulders, much as the synthetic scene draws them.
private let sceneHead = CGRect(x: 540, y: 300, width: 200, height: 258)
private let sceneBody = CGRect(x: 370, y: 0, width: 540, height: 290)
private let scenePerson = SceneBlocks(rects: [sceneBody, sceneHead])

/// Every scene there is, with its cast, so the same checks run on each.
private func sceneCasts() -> [(name: String, cast: SceneCast)] {
    [("safari", SafariCast.cast), ("jungle", JungleCast.cast), ("deep sea", DeepSeaCast.cast), ("dino park", DinoCast.cast), ("haunted", HauntedCast.cast)]
}

private func sceneSpecies(_ cast: SceneCast, _ id: Int) -> SceneSpecies { cast.species[cast.roster[id]] }

private func sceneStepAll(_ world: inout SceneWorld, seconds: Double, context: SceneContext, every: ((SceneWorld) -> Void)? = nil) {
    let steps = Int(seconds * 30)
    for _ in 0..<steps {
        world.step(1.0 / 30, context: context)
        every?(world)
    }
}

private func sceneDistance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { hypot(a.x - b.x, a.y - b.y) }

final class SceneModelTests: XCTestCase {
    private func context(person: Bool = true, motion: MatteQuery? = nil, hands: [HandState] = []) -> SceneContext {
        SceneContext(size: sceneFrame, matte: person ? scenePerson : nil, motion: motion, hands: hands)
    }

    // MARK: Seeing the person

    func testTheAnimalsFindThePersonFromTheirSilhouette() throws {
        let person = try XCTUnwrap(ScenePerson.find(in: scenePerson, size: sceneFrame))
        XCTAssertEqual(Double(person.box.minX), 370, accuracy: 40)
        XCTAssertEqual(Double(person.box.maxX), 910, accuracy: 40)
        XCTAssertEqual(Double(person.top), 558, accuracy: 8)
        XCTAssertEqual(Double(person.head.x), 640, accuracy: 20)
        XCTAssertEqual(person.headRadius, 100, accuracy: 25)
        XCTAssertLessThan(Double(person.chin), 340)
        XCTAssertGreaterThan(Double(person.chin), 250)
        XCTAssertNil(ScenePerson.find(in: SceneBlocks(), size: sceneFrame), "an empty room has nobody in it")
        XCTAssertNil(ScenePerson.find(in: SceneBlocks(rects: [CGRect(x: 100, y: 100, width: 40, height: 40)]), size: sceneFrame), "a speck is not a person")
    }

    // MARK: Life with nobody there

    func testWithNobodyThereTheyWanderAndNoneTakesAnInterest() {
        for (name, cast) in sceneCasts() {
            var world = SceneWorld(cast: cast, seed: 3)
            var noticed = false
            var moved = Set<Int>()
            let start = world.creatures.map(\.pos)
            sceneStepAll(&world, seconds: 40, context: context(person: false)) { w in
                if w.creatures.contains(where: { $0.phase == .noticing || $0.phase == .approaching || $0.phase == .acting }) { noticed = true }
                for c in w.creatures where c.phase != .away && sceneDistance(c.pos, start[c.id]) > 40 { moved.insert(c.id) }
            }
            XCTAssertFalse(noticed, "\(name): nobody there to notice")
            XCTAssertGreaterThanOrEqual(moved.count, 4, "\(name): the animals are going about their day")
        }
    }

    // MARK: The first seconds

    func testAFirstTimeViewerSeesSomethingHappenWithinAFewSeconds() {
        for (name, cast) in sceneCasts() {
            var world = SceneWorld(cast: cast, seed: 11)
            var firstNotice: Double?, firstAct: Double?
            sceneStepAll(&world, seconds: 10, context: context()) { w in
                if firstNotice == nil, w.creatures.contains(where: { $0.phase == .noticing }) { firstNotice = w.time }
                if firstAct == nil, w.creatures.contains(where: { $0.phase == .acting }) { firstAct = w.time }
            }
            XCTAssertLessThan(firstNotice ?? 99, 3.0, "\(name): something notices you almost at once")
            XCTAssertLessThan(firstAct ?? 99, 9.0, "\(name): and something is doing its thing within a few seconds")
            XCTAssertGreaterThanOrEqual(world.creatures.filter { $0.phase != .away }.count, 5, "\(name): the place is already lived in")
        }
    }

    // MARK: Notice, approach, act, return

    func testEveryKindNoticesApproachesActsAndGoesBackToItsLife() {
        for (name, cast) in sceneCasts() {
            var world = SceneWorld(cast: cast, seed: 21)
            var seen = [Set<String>](repeating: [], count: cast.roster.count)
            var returned = Set<Int>()
            var lastPhase = world.creatures.map(\.phase)
            sceneStepAll(&world, seconds: 240, context: context()) { w in
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
            for id in actors {
                XCTAssertTrue(seen[id].contains("noticing") && seen[id].contains("approaching"), "\(name) \(sceneSpecies(cast, id).name): looks, then comes")
            }
            XCTAssertGreaterThanOrEqual(returned.count, max(1, actors.count - 2), "\(name): and then goes back to being an animal")
        }
    }

    // MARK: Staying off your face

    func testNothingInFrontOfThePersonEverCoversTheirFace() {
        for (name, cast) in sceneCasts() {
            for seed in [1, 2, 3] as [UInt64] {
                var world = SceneWorld(cast: cast, seed: seed)
                var worst = 0.0
                var offender = ""
                sceneStepAll(&world, seconds: 180, context: context()) { w in
                    guard let person = w.person else { return }
                    for c in w.creatures where c.phase != .away && c.depth >= w.layout.frontDepth {
                        let sp = w.cast.species[c.species]
                        let overlap = w.bounds(of: c).intersection(person.faceZone)
                        // A monkey sitting on a head stands on the crown of it, a few pixels into the zone; anything else must be clear.
                        let allowed = sp.act == .climb ? 16.0 : 0.0
                        if !overlap.isNull, overlap.height > allowed, overlap.width * overlap.height > worst {
                            worst = Double(overlap.width * overlap.height)
                            offender = "\(sp.name) in \(c.phase)"
                        }
                    }
                }
                XCTAssertEqual(worst, 0, "\(name) seed \(seed): \(offender) sat on the face")
            }
        }
    }

    // MARK: Being scared

    func testWavingYourArmsSendsThemRunning() {
        for (name, cast) in sceneCasts() {
            var world = SceneWorld(cast: cast, seed: 31)
            sceneStepAll(&world, seconds: 6, context: context())
            // Arms flung about across the whole picture.
            let wave = SceneMotion(rect: CGRect(x: 100, y: 100, width: 1080, height: 540))
            var fled = false, backed = false
            sceneStepAll(&world, seconds: 1.5, context: context(motion: wave)) { w in
                if w.creatures.contains(where: { $0.phase == .fleeing }) { fled = true }
                if w.creatures.contains(where: { $0.phase == .backingOff }) { backed = true }
            }
            XCTAssertTrue(fled, "\(name): somebody bolts")
            let timid = world.creatures.filter { sceneSpecies(cast, $0.id).temper != .brute && $0.phase != .away && $0.phase != .entering }
            XCTAssertTrue(timid.allSatisfy { $0.phase == .fleeing }, "\(name): everything that can run is running (\(timid.map { "\($0.phase)" }))")
            if cast.species.contains(where: { $0.temper == .brute }) { XCTAssertTrue(backed, "\(name): the big ones back off") }
        }
    }

    func testTheBigOnesBackOffFacingYouAndComeBack() throws {
        let cast = SafariCast.cast
        var world = SceneWorld(cast: cast, seed: 5)
        let lion = try XCTUnwrap(world.creatures.firstIndex { sceneSpecies(cast, $0.id).name == "lion" })
        sceneStepAll(&world, seconds: 3, context: context())
        world.attract(lion)
        // Wait until it is at the person's side, then wave at it.
        var tries = 0
        while world.creatures[lion].phase != .acting, tries < 900 { world.step(1.0 / 30, context: context()); tries += 1 }
        XCTAssertEqual(world.creatures[lion].phase, .acting)
        let before = world.creatures[lion].pos.x
        let wave = SceneMotion(rect: CGRect(x: 0, y: 0, width: 1280, height: 720))
        sceneStepAll(&world, seconds: 0.4, context: context(motion: wave))
        XCTAssertEqual(world.creatures[lion].phase, .backingOff, "a lion in the middle of a roar flinches")
        XCTAssertEqual(world.creatures[lion].dir, before < 640 ? 1 : -1, "and keeps its eyes on you")
        var cameBack = false
        sceneStepAll(&world, seconds: 40, context: context()) { w in
            if w.creatures[lion].phase == .wandering || w.creatures[lion].phase == .noticing { cameBack = true }
        }
        XCTAssertTrue(cameBack, "then it goes about its business again")
    }

    func testPreyBoltsOffScreenAndReturnsLater() throws {
        let cast = SafariCast.cast
        var world = SceneWorld(cast: cast, seed: 8)
        let zebra = try XCTUnwrap(world.creatures.firstIndex { sceneSpecies(cast, $0.id).name == "zebra" })
        sceneStepAll(&world, seconds: 2, context: context())
        world.stage(zebra, x: 250)
        sceneStepAll(&world, seconds: 0.5, context: context())
        let wave = SceneMotion(rect: CGRect(x: 100, y: 100, width: 600, height: 500))
        sceneStepAll(&world, seconds: 0.3, context: context(motion: wave))
        XCTAssertEqual(world.creatures[zebra].phase, .fleeing)
        XCTAssertLessThan(world.creatures[zebra].dir, 0, "away from you, which from there is left")
        var away = false, back = false
        sceneStepAll(&world, seconds: 70, context: context()) { w in
            if w.creatures[zebra].phase == .away { away = true }
            if away, w.creatures[zebra].phase == .entering || w.creatures[zebra].phase == .wandering { back = true }
        }
        XCTAssertTrue(away && back, "it runs off the edge of the picture, and walks back in")
    }

    func testSteppingIntoThePictureInAFlurryFrightensNobody() {
        for (name, cast) in sceneCasts() {
            var world = SceneWorld(cast: cast, seed: 2)
            // The person has only just arrived, and everything in the silhouette is changing as they sit down.
            let flurry = SceneMotion(rect: CGRect(x: 0, y: 0, width: 1280, height: 720))
            var scared = false
            sceneStepAll(&world, seconds: 1.1, context: context(motion: flurry)) { w in
                if w.creatures.contains(where: { $0.phase == .fleeing || $0.phase == .backingOff }) { scared = true }
            }
            XCTAssertFalse(scared, "\(name): coming into view is not a wave")
        }
    }

    func testStandingStillOrFidgetingScaresNothing() {
        for (name, cast) in sceneCasts() {
            var world = SceneWorld(cast: cast, seed: 41)
            // Edge flicker: a faint change everywhere. And a twitch: a small patch that changes completely.
            let flicker = SceneMotion(rect: CGRect(x: 0, y: 0, width: 1280, height: 720), strength: 0.25)
            var scared = false
            sceneStepAll(&world, seconds: 20, context: context(motion: flicker)) { w in
                if w.creatures.contains(where: { $0.phase == .fleeing || $0.phase == .backingOff }) { scared = true }
            }
            XCTAssertFalse(scared, "\(name): matte flicker is not a wave")
            let twitch = SceneMotion(rect: CGRect(x: 560, y: 420, width: 60, height: 60))
            sceneStepAll(&world, seconds: 10, context: context(motion: twitch)) { w in
                if w.creatures.contains(where: { $0.phase == .fleeing || $0.phase == .backingOff }) { scared = true }
            }
            XCTAssertFalse(scared, "\(name): a twitch is not a wave")
        }
    }

    func testItCopesWithAPersonWhoFillsTheFrameIsTinyOrSitsAtTheEdge() {
        let shapes: [(String, SceneBlocks)] = [
            ("filling the frame", SceneBlocks(rects: [CGRect(x: 0, y: 0, width: 1280, height: 300), CGRect(x: 480, y: 280, width: 320, height: 420)])),
            ("far away", SceneBlocks(rects: [CGRect(x: 580, y: 180, width: 120, height: 120), CGRect(x: 615, y: 290, width: 50, height: 70)])),
            ("at the left edge", SceneBlocks(rects: [CGRect(x: 0, y: 0, width: 330, height: 280), CGRect(x: 90, y: 270, width: 150, height: 250)])),
        ]
        for (name, cast) in sceneCasts() {
            for (shape, matte) in shapes {
                var world = SceneWorld(cast: cast, seed: 17)
                var acted = false
                var worst = 0.0
                for _ in 0..<(30 * 150) {
                    world.step(1.0 / 30, context: SceneContext(size: sceneFrame, matte: matte))
                    guard let person = world.person else { continue }
                    for c in world.creatures {
                        XCTAssertTrue(c.pos.x.isFinite && c.pos.y.isFinite, "\(name) \(shape)")
                        if c.phase == .acting { acted = true }
                        guard c.phase != .away, c.depth >= world.layout.frontDepth, world.cast.species[c.species].act != .climb else { continue }
                        let overlap = world.bounds(of: c).intersection(person.faceZone)
                        if !overlap.isNull { worst = max(worst, Double(overlap.width * overlap.height)) }
                    }
                }
                XCTAssertTrue(acted, "\(name), person \(shape): somebody still comes to you")
                XCTAssertEqual(worst, 0, "\(name), person \(shape): and still keeps off your face")
            }
        }
    }

    // MARK: Determinism, limits and odd input

    func testTheSameSeedAndTheSameViewGiveTheSameDay() {
        for (name, cast) in sceneCasts() {
            var a = SceneWorld(cast: cast, seed: 77), b = SceneWorld(cast: cast, seed: 77), c = SceneWorld(cast: cast, seed: 78)
            let wave = SceneMotion(rect: CGRect(x: 300, y: 100, width: 700, height: 500))
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
        for (name, cast) in sceneCasts() {
            XCTAssertLessThanOrEqual(cast.roster.count, 12, "\(name)")
            XCTAssertGreaterThanOrEqual(cast.roster.count, 8, "\(name)")
            var world = SceneWorld(cast: cast, seed: 5)
            var most = 0
            let wave = SceneMotion(rect: CGRect(x: 100, y: 100, width: 1080, height: 540))
            for i in 0..<(30 * 120) {
                world.step(1.0 / 30, context: context(motion: i % 600 < 30 ? wave : nil))
                most = max(most, world.creatures.filter { $0.phase != .away }.count)
            }
            XCTAssertLessThanOrEqual(most, 12, "\(name)")
            XCTAssertLessThanOrEqual(most, cast.cap)
        }
    }

    func testAHugeTimeStepOrAMissingPersonDoesNotBreakAnything() {
        for (name, cast) in sceneCasts() {
            var world = SceneWorld(cast: cast, seed: 9)
            world.step(0, context: context())
            world.step(30, context: context())
            world.step(-1, context: context())
            world.step(0.2, context: SceneContext(size: sceneFrame))
            sceneStepAll(&world, seconds: 10, context: context())
            // The person walks out in the middle of it all.
            sceneStepAll(&world, seconds: 10, context: context(person: false))
            for c in world.creatures {
                XCTAssertTrue(c.pos.x.isFinite && c.pos.y.isFinite && abs(c.pos.x) < 3000 && abs(c.pos.y) < 3000, "\(name) \(sceneSpecies(cast, c.id).name) is somewhere sensible: \(c.pos)")
                XCTAssertTrue(c.depth >= 0 && c.depth <= 1)
            }
            XCTAssertTrue(world.creatures.allSatisfy { $0.phase != .acting && $0.phase != .approaching }, "\(name): with nobody to come to, they stop coming")
        }
    }

    // MARK: Hands

    func testABirdLandsOnARaisedOpenHandAndFliesOffWhenItGoes() throws {
        for (name, cast) in sceneCasts() where cast.species.contains(where: \.perchesOnHand) {
            let birds = cast.roster.indices.filter { sceneSpecies(cast, $0).perchesOnHand }
            var world = SceneWorld(cast: cast, seed: 14)
            // A hand held up to the side of the person.
            let hand = HandFixtures.openPalm(at: CGPoint(x: 1010, y: 330), size: 90)
            let knuckle = hand[.middleMCP], tip = hand[.middleTip]
            let palm = CGPoint(x: knuckle.x + (tip.x - knuckle.x) * 0.55, y: knuckle.y + (tip.y - knuckle.y) * 0.55)
            var landed: Int?
            sceneStepAll(&world, seconds: 25, context: context(hands: [hand])) { w in
                for id in birds {
                    let c = w.creatures[id]
                    if c.phase == .acting, c.landedAt != nil, abs(c.pos.x - Double(palm.x)) < 60, abs(c.pos.y - Double(palm.y)) < 100 { landed = id }
                }
            }
            let bird = try XCTUnwrap(landed, "\(name): a bird sits on your hand")
            // Hand goes down: it leaves.
            sceneStepAll(&world, seconds: 3, context: context())
            XCTAssertNotEqual(world.creatures[bird].phase, .acting, "\(name): and flies off when the hand is gone")
        }
    }

    func testOnlyOneBirdLandsOnAHandAtATime() {
        for (name, cast) in sceneCasts() where cast.species.contains(where: \.perchesOnHand) {
            var world = SceneWorld(cast: cast, seed: 3)
            let hand = HandFixtures.openPalm(at: CGPoint(x: 1010, y: 330), size: 90)
            var most = 0
            sceneStepAll(&world, seconds: 60, context: context(hands: [hand])) { w in
                most = max(most, w.creatures.filter { $0.onHand && $0.phase == .acting }.count)
            }
            XCTAssertLessThanOrEqual(most, 1, "\(name): one bird to a hand")
        }
    }

    func testAHandThatFlickersOutForAMomentDoesNotShakeTheBirdOff() throws {
        for (name, cast) in sceneCasts() where cast.species.contains(where: \.perchesOnHand) {
            let birds = cast.roster.indices.filter { sceneSpecies(cast, $0).perchesOnHand }
            var world = SceneWorld(cast: cast, seed: 14)
            let hand = HandFixtures.openPalm(at: CGPoint(x: 1010, y: 330), size: 90)
            var sitting: Int?
            for _ in 0..<(30 * 25) where sitting == nil {
                world.step(1.0 / 30, context: context(hands: [hand]))
                sitting = birds.first { world.creatures[$0].phase == .acting && world.creatures[$0].landedAt != nil && world.creatures[$0].onHand }
            }
            let bird = try XCTUnwrap(sitting, "\(name): a bird landed on the hand")
            sceneStepAll(&world, seconds: 1, context: context(hands: [hand]))
            // Tracking drops for a third of a second.
            sceneStepAll(&world, seconds: 0.33, context: context())
            XCTAssertEqual(world.creatures[bird].phase, .acting, "\(name): tracking blinks all the time; the bird stays")
        }
    }

    func testAMonkeyClimbsOntoYourHeadAndSitsAboveYourFace() throws {
        for (name, cast) in sceneCasts() where cast.species.contains(where: { $0.act == .climb }) {
            var world = SceneWorld(cast: cast, seed: 6)
            let monkey = try XCTUnwrap(world.creatures.firstIndex { sceneSpecies(cast, $0.id).act == .climb })
            sceneStepAll(&world, seconds: 2, context: context())
            world.attract(monkey)
            var sat = false
            var feet = 0.0
            sceneStepAll(&world, seconds: 25, context: context()) { w in
                let c = w.creatures[monkey]
                guard let person = w.person, c.phase == .acting, c.landedAt != nil else { return }
                let rect = w.bounds(of: c)
                if abs(Double(rect.midX) - Double(person.head.x)) < 40, Double(rect.minY) > Double(person.top) - 30 { sat = true; feet = Double(rect.minY) }
            }
            XCTAssertTrue(sat, "\(name): it ends up sitting on your head")
            XCTAssertGreaterThan(feet, Double(sceneHead.maxY) - 30, "\(name): with its feet on your hair, not on your forehead")
        }
    }
}

// MARK: - Drawing

/// A scene with a flat sky and one zebra, to see which side of the person it is drawn on.
private final class FlatTestScene: SceneStyle {
    let look = SceneLook()
    let hint = "test"
    let cast: SceneCast
    init() {
        var layout = SceneLayout()
        layout.farGround = 250
        let zebra = SceneSpecies(name: "zebra", glyph: "🦓", facesRight: false, height: 170, aspect: 1.16, speed: 100, home: 0.2)
        cast = SceneCast(species: [zebra], roster: [0], layout: layout, cap: 12, visibleAtStart: 1)
    }
    func paintBackdrop(_ ctx: CGContext, frame: SceneFrame) {
        ctx.setFillColor(CGColor(red: 0.9, green: 0.8, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: frame.size))
    }
    func paintForeground(_ ctx: CGContext, frame: SceneFrame) {}
}

final class SceneLayerTests: XCTestCase {
    private let h = LensHarness()

    private func differsFromBackdrop(_ p: RGB) -> Bool { abs(p.r - 230) + abs(p.g - 204) + abs(p.b - 51) > 60 }
    private func difference(_ a: RGB, _ b: RGB) -> Int { abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) }

    func testAnAnimalFarAwayIsHiddenByThePersonAndOneCloseUpIsInFrontOfThem() {
        let base = h.input(SyntheticScene(center: CGPoint(x: 640, y: 420)), background: false)
        let shirt = h.pixel(base.composed, 640, 150)

        // Far away, right behind the person's body: not a trace of it.
        let far = SceneLens(style: FlatTestScene(), seed: 1)
        far.stage(0, x: 640, depth: 0.1)
        let farFrame = far.render(h.at(base, time: 0))
        var hidden = true
        for y in stride(from: 100, through: 260, by: 8) { for x in stride(from: 520, through: 760, by: 8) where difference(h.pixel(farFrame, x, y), h.pixel(base.composed, x, y)) > 30 { hidden = false } }
        XCTAssertTrue(hidden, "the far animal is hidden behind the person; shirt \(shirt)")

        // Beside them, outside the silhouette, it shows.
        far.stage(0, x: 1100, depth: 0.1)
        let besideFar = far.render(h.at(base, time: 0.05))
        var seen = false
        for y in stride(from: 240, through: 330, by: 6) { for x in stride(from: 1040, through: 1160, by: 6) where differsFromBackdrop(h.pixel(besideFar, x, y)) { seen = true } }
        XCTAssertTrue(seen, "away from the person the far animal is in the picture")

        // The same animal close up, at the foot of the picture over the person's chest: drawn on top.
        let near = SceneLens(style: FlatTestScene(), seed: 1)
        near.stage(0, x: 480, depth: 0.92)
        let nearFrame = near.render(h.at(base, time: 0))
        var covers = false
        for y in stride(from: 100, through: 240, by: 8) { for x in stride(from: 400, through: 560, by: 8) where difference(h.pixel(nearFrame, x, y), h.pixel(base.composed, x, y)) > 90 { covers = true } }
        XCTAssertTrue(covers, "the near animal is drawn over the person")
    }
}

final class SceneRenderTests: XCTestCase {
    private let h = LensHarness()

    func testEverySceneRendersAtFullSizeWithAndWithoutAPersonAndWithHands() throws {
        XCTAssertFalse(SceneCatalog.all.isEmpty)
        let base = h.input(background: false)
        let hand = HandFixtures.openPalm(at: CGPoint(x: 1000, y: 340), size: 90)
        for info in SceneCatalog.all {
            let lens = info.make()
            (lens as? SceneLens)?.paintNow()
            XCTAssertEqual(info.category, .scenes)
            XCTAssertTrue(lens.needs.contains(.matte), "\(info.name)")
            XCTAssertTrue(lens.wantsMatteGrid)
            XCTAssertNotNil(lens.status, "\(info.name) has a hint")
            var out = base.composed
            for i in 0..<20 { out = lens.render(h.at(base, time: Double(i) / 30, hands: lens.needs.contains(.hands) ? [hand] : [])) }
            XCTAssertEqual(out.extent, base.rect, info.name)
            Output.save(out, as: "scene-\(info.id)-person.png")

            // The scene is there and the person is in it: their face is still on top at the centre.
            let face = h.pixel(out, 640, 400), plain = h.pixel(base.composed, 640, 400)
            XCTAssertLessThan(abs(face.r - plain.r) + abs(face.g - plain.g) + abs(face.b - plain.b), 60, "\(info.name): your face is not covered")
            let corner = h.pixel(out, 30, 690), room = h.pixel(base.composed, 30, 690)
            XCTAssertGreaterThan(abs(corner.r - room.r) + abs(corner.g - room.g) + abs(corner.b - room.b), 30, "\(info.name): the room is gone")

            // Nobody there at all: no matte, no grid.
            let empty = LensInput(time: 0, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: nil, background: nil, composed: base.camera, matteGrid: nil,
                                  face: nil, services: base.services)
            let fresh = info.make()
            XCTAssertEqual(fresh.render(empty).extent, base.rect, "\(info.name) with no one in view, on its very first frame")
            (fresh as? SceneLens)?.paintNow()
            let lonely = fresh.render(empty)
            XCTAssertEqual(lonely.extent, base.rect, "\(info.name) with no one in view")
            Output.save(lonely, as: "scene-\(info.id)-empty.png")
            // A grid that says nobody is in it.
            let blank = LensInput(time: 0, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: base.matte, background: nil, composed: base.camera,
                                  matteGrid: MatteGrid(outputSize: base.rect.size), face: nil, services: base.services)
            XCTAssertEqual(info.make().render(blank).extent, base.rect, "\(info.name) with an empty matte")
        }
    }

    func testTheCatalogEntriesAreWiredUpRight() {
        XCTAssertEqual(Set(SceneCatalog.all.map(\.id)).count, SceneCatalog.all.count)
        for info in SceneCatalog.all {
            XCTAssertTrue(info.id.hasPrefix("scene-"), info.id)
            XCTAssertEqual(info.glyph.count, 1, "\(info.name): the glyph is one emoji")
            XCTAssertFalse(info.blurb.isEmpty)
            let lens = info.make()
            XCTAssertEqual(lens.needs.contains(.hands), info.needsHands, info.name)
            XCTAssertEqual(lens.needs.contains(.face), info.needsFace, info.name)
            XCTAssertFalse(lens.status?.title.isEmpty ?? true, "\(info.name) says what to do")
        }
    }

    func testRestartingGivesAFreshWorld() {
        let lens = SceneLens(style: SafariScene(), seed: 3)
        let base = h.input(background: false)
        for i in 0..<60 { _ = lens.render(h.at(base, time: Double(i) / 30)) }
        XCTAssertGreaterThan(lens.world.time, 1.9)
        lens.restart()
        XCTAssertEqual(lens.world.time, 0)
    }
}

/// A lens that does nothing, to measure what an ordinary frame costs on this machine at this moment.
private final class SceneDoNothingLens: Lens {
    let needs: LensNeeds = [.matte]
    func render(_ input: LensInput) -> CIImage { input.composed }
}

/// CPU time used by this thread, in seconds: unlike the wall clock, it does not count time spent waiting for a busy machine.
private func sceneThreadSeconds() -> Double {
    var ts = timespec()
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
    return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
}

final class SceneCostTests: XCTestCase {
    private let h = LensHarness()

    /// Milliseconds of this thread's CPU time per frame to make and render a frame, and the wall-clock mean for the record.
    private func cost(of lens: Lens, base: LensInput, frames: Int, from start: Double) -> (cpu: Double, wall: Double) {
        let buffer = h.compositor.makeOutputBuffer()!
        let c0 = sceneThreadSeconds(), w0 = CFAbsoluteTimeGetCurrent()
        for i in 0..<frames { h.compositor.render(lens.render(h.at(base, time: start + Double(i) / 30)), into: buffer) }
        return ((sceneThreadSeconds() - c0) * 1000 / Double(frames), (CFAbsoluteTimeGetCurrent() - w0) * 1000 / Double(frames))
    }

    func testEverySceneIsCheapEnoughToRunEveryFrame() {
        let base = h.input(background: false)
        let plain = (0..<3).map { _ in cost(of: SceneDoNothingLens(), base: base, frames: 60, from: 0).cpu }.min() ?? 0
        for info in SceneCatalog.all {
            let lens = info.make()
            (lens as? SceneLens)?.paintNow()
            for i in 0..<45 { _ = lens.render(h.at(base, time: Double(i) / 30)) }       // let the animals come out
            // A long run, so that animals come close and act; the best of three stands for the cost.
            let runs = (0..<3).map { cost(of: lens, base: base, frames: 120, from: 1.5 + Double($0) * 4) }
            let cpu = runs.map(\.cpu).min() ?? 0, wall = runs.map(\.wall).min() ?? 0
            print("SCENE COST \(info.name): \(String(format: "%.2f", cpu - plain)) ms of CPU a frame over a plain frame (wall \(String(format: "%.1f", wall)) ms)")
            XCTAssertLessThan(cpu - plain, 5.5, "\(info.name) costs \(String(format: "%.1f", cpu)) ms of CPU a frame, \(String(format: "%.1f", plain)) of it a plain frame")
        }
    }

    /// Making a scene is instant (it is done on the main thread); the painting happens a little at a time on the first frames, and
    /// no frame waits long for it.
    func testMakingAScenePaintsItQuicklyAndAFewFramesAtATime() {
        let base = h.input(background: false)
        for info in SceneCatalog.all {
            let started = CFAbsoluteTimeGetCurrent()
            let lens = info.make()
            let made = (CFAbsoluteTimeGetCurrent() - started) * 1000
            XCTAssertLessThan(made, 60, "\(info.name) took \(Int(made)) ms to make")
            var worst = 0.0, frames = 0
            var shown = false
            while !shown, frames < 120 {
                let t0 = CFAbsoluteTimeGetCurrent()
                let out = lens.render(h.at(base, time: Double(frames) / 30))
                _ = h.pixel(out, 30, 690)
                worst = max(worst, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
                frames += 1
                let corner = h.pixel(out, 30, 690), room = h.pixel(base.composed, 30, 690)
                shown = abs(corner.r - room.r) + abs(corner.g - room.g) + abs(corner.b - room.b) > 30
            }
            XCTAssertTrue(shown, "\(info.name) shows up")
            print("SCENE \(info.name): made in \(Int(made)) ms, shown after \(frames) frames, worst frame \(Int(worst)) ms")
            XCTAssertLessThan(worst, 150, "\(info.name): a first frame took \(Int(worst)) ms")
        }
    }
}

// MARK: - Pictures to look at

/// Pictures of the scenes, tiled into contact sheets, saved only when BACKDROP_TEST_OUTPUT is set. Nothing is asserted here.
final class SceneLookTests: XCTestCase {
    private let h = LensHarness()

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"] != nil, "set TEST_RUNNER_BACKDROP_TEST_OUTPUT to save pictures")
    }

    private func sheet(_ lens: SceneLens, scene: SyntheticScene = SyntheticScene(), seconds: Double, every: Double, name: String, columns: Int = 3,
                       hands: [HandState] = [], attract: String? = nil) {
        let base = h.input(scene, background: false)
        lens.paintNow()
        var t = 0.0, next = every
        var tiles: [CIImage] = []
        if let attract { _ = lens.render(h.at(base, time: 0)); lens.attract(attract) }
        while t < seconds {
            let out = lens.render(h.at(base, time: t, hands: hands))
            t += 1.0 / 30
            if t >= next {
                next += every
                let small = out.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
                if let cg = h.ciContext.createCGImage(small, from: small.extent) { tiles.append(CIImage(cgImage: cg)) }
            }
        }
        let rows = (tiles.count + columns - 1) / columns
        var sheet = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 640 * columns, height: 360 * rows))
        for (i, tile) in tiles.enumerated() {
            let x = CGFloat(i % columns) * 640, y = CGFloat(rows - 1 - i / columns) * 360
            sheet = tile.transformed(by: CGAffineTransform(translationX: x, y: y)).composited(over: sheet)
        }
        Output.save(sheet, as: "\(name).png")
    }

    /// The person throws themselves about for a second or so, in the middle of it, and the sheet shows what the animals do.
    private func fleeSheet(_ lens: SceneLens, name: String) {
        lens.paintNow()
        var t = 0.0, next = 0.5
        var tiles: [CIImage] = []
        let still = h.input(SyntheticScene(), background: false)
        // A few seconds of peace, so that the animals have come out.
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

    func testBirdsOnAHandAndAMonkeyOnAHead() {
        let hand = HandFixtures.openPalm(at: CGPoint(x: 1010, y: 300), size: 100)
        shot(SceneLens(style: JungleScene(), hands: true, seed: 5), of: "parrot", hands: [hand], name: "jungle-parrot-on-hand", seconds: 30, after: 3.2)
        shot(SceneLens(style: JungleScene(), hands: true, seed: 5), of: "butterfly", hands: [hand], name: "jungle-butterfly-on-hand", seconds: 30, after: 3.2)
        shot(SceneLens(style: SafariScene(), hands: true, seed: 5), of: "vulture", hands: [hand], name: "safari-vulture-on-hand", seconds: 40, after: 3.2)
        shot(SceneLens(style: JungleScene(), hands: true, seed: 5), of: "monkey", name: "jungle-monkey-sits", seconds: 30, after: 4.0)
    }

    func testWavingScaresThemOff() {
        fleeSheet(SceneLens(style: SafariScene(), hands: true, seed: 5), name: "safari-flee")
        fleeSheet(SceneLens(style: JungleScene(), hands: true, seed: 5), name: "jungle-flee")
        fleeSheet(SceneLens(style: DeepSeaScene(), seed: 5), name: "deep-sea-flee")
    }

    /// Runs until a creature of `kind` has been in `phase` for `after` seconds, then saves that frame at full size.
    private func shot(_ lens: SceneLens, of kind: String, scene: SyntheticScene = SyntheticScene(), hands: [HandState] = [], name: String, seconds: Double = 25,
                      after: Double = 1.0, phase: SceneCreature.Phase = .acting) {
        let base = h.input(scene, background: false)
        lens.paintNow()
        var t = 0.0
        _ = lens.render(h.at(base, time: 0, hands: hands))
        lens.attract(kind)
        while t < seconds {
            let out = lens.render(h.at(base, time: t, hands: hands))
            t += 1.0 / 30
            if lens.world.creatures.contains(where: { lens.world.cast.species[$0.species].name == kind && $0.phase == phase && $0.phaseTime > after }) {
                Output.save(out, as: "\(name).png")
                return
            }
        }
    }

    func testJungleAtSeveralMoments() {
        sheet(SceneLens(style: JungleScene(), hands: true, seed: 5), seconds: 24, every: 4, name: "jungle-sheet")
        for kind in ["monkey", "parrot", "snake", "tiger", "gorilla", "frog", "butterfly"] {
            shot(SceneLens(style: JungleScene(), hands: true, seed: 5), of: kind, name: "jungle-\(kind)", seconds: 30, after: kind == "monkey" ? 3.0 : 1.0)
        }
    }

    func testDeepSeaAtSeveralMoments() {
        sheet(SceneLens(style: DeepSeaScene(), seed: 5), seconds: 24, every: 4, name: "deep-sea-sheet")
        for kind in ["shark", "blue fish", "tropical fish", "turtle", "jellyfish", "octopus", "pufferfish", "dolphin"] {
            shot(SceneLens(style: DeepSeaScene(), seed: 5), of: kind, name: "deep-sea-\(kind)", seconds: 30, after: kind == "shark" ? 3.5 : 1.0)
        }
    }

    func testDinoParkAtSeveralMoments() {
        sheet(SceneLens(style: DinoScene(), seed: 5), seconds: 24, every: 4, name: "dino-sheet")
        for kind in ["t-rex", "raptor", "triceratops", "brontosaurus", "pterodactyl", "baby rex", "lizard"] {
            shot(SceneLens(style: DinoScene(), seed: 5), of: kind, name: "dino-\(kind)", seconds: 30, after: 1.0)
        }
    }

    func testHauntedManorAtSeveralMoments() {
        sheet(SceneLens(style: HauntedScene(), seed: 5), seconds: 24, every: 4, name: "haunted-sheet")
        for kind in ["ghost", "bat", "spider", "pumpkin"] {
            shot(SceneLens(style: HauntedScene(), seed: 5), of: kind, name: "haunted-\(kind)", seconds: 30, after: 1.2)
        }
    }

    func testSafariAtSeveralMoments() {
        sheet(SceneLens(style: SafariScene(), hands: true, seed: 5), seconds: 24, every: 4, name: "safari-sheet")
        sheet(SceneLens(style: SafariScene(), hands: true, seed: 5), seconds: 7.2, every: 0.8, name: "safari-lion", attract: "lion")
        for kind in ["lion", "elephant", "rhino", "zebra", "giraffe", "cheetah", "buffalo", "vulture"] {
            shot(SceneLens(style: SafariScene(), hands: true, seed: 5), of: kind, name: "safari-\(kind)")
        }
    }
}

// MARK: - Model sheets

/// Every hand-drawn creature in six poses (resting, two steps of the walk, running, doing its thing, looking at you), drawn straight
/// from its rig over its own scene, so the art can be judged at full size. Saved only when BACKDROP_TEST_OUTPUT is set.
final class SceneModelSheetTests: XCTestCase {
    static func styles() -> [(String, SceneStyle)] {
        [("safari", SafariScene()), ("jungle", JungleScene()), ("deep-sea", DeepSeaScene()), ("dino", DinoScene()), ("haunted", HauntedScene())]
    }

    /// The poses on a sheet: a label and the actor for it.
    static func poses(_ sp: SceneSpecies) -> [SceneActor] {
        func actor(_ phase: SceneCreature.Phase, time: Double, phaseTime: Double = 0, stride: Double = 0, walk: Double = 0, run: Double = 0,
                   alert: Double = 0, look: Double = 0, open: Double = 0, lift: Double = 0, landed: Bool = false) -> SceneActor {
            var a = SceneActor()
            a.time = time; a.phase = phase; a.phaseTime = phaseTime; a.stride = stride; a.walk = walk; a.run = run
            a.alert = alert; a.look = look; a.act = sp.act; a.actSeconds = sp.actSeconds; a.quirk = 0.3; a.lift = lift; a.landed = landed
            a.pose.open = open
            a.tail = sin(time * 1.3) * 0.5
            a.velocity = SIMD2(walk * (run > 0.5 ? 2.6 : 1) * 0.6, 0)
            return a
        }
        return [
            actor(.wandering, time: 1.0),
            actor(.wandering, time: 2.0, stride: 0.6, walk: 1),
            actor(.wandering, time: 2.3, stride: 2.4, walk: 1),
            actor(.fleeing, time: 3.0, stride: 1.2, walk: 1, run: 1, alert: 0.7),
            actor(.acting, time: 4.0, phaseTime: sp.actSeconds * 0.45, alert: 1, look: 0.35, open: 1, landed: true),
            actor(.noticing, time: 5.0, phaseTime: 0.6, alert: 1, look: 0.45),
        ]
    }

    func testDrawEveryCreatureInSixPoses() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"] != nil, "set TEST_RUNNER_BACKDROP_TEST_OUTPUT to save pictures")
        for (scene, style) in Self.styles() {
            while !style.prepare(until: CFAbsoluteTimeGetCurrent() + 1) {}
            let ink = SceneInk(look: style.look, lights: SceneLightBox(look: style.look))
            for (index, sp) in style.cast.species.enumerated() {
                guard let puppet = style.puppet(for: index) else { continue }
                guard let ctx = CGContext(data: nil, width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: 0, space: ScenePaint.space,
                                          bitmapInfo: Sprites.bitmapInfo) else { continue }
                style.paintBackdrop(ctx, frame: SceneFrame(time: 3, size: CGSize(width: 1280, height: 720), shift: .zero))
                ctx.setFillColor(CGColor(gray: 0, alpha: 0.25))
                ctx.fill(CGRect(x: 0, y: 0, width: 1280, height: 720))
                let poses = Self.poses(sp)
                let unit = min(sp.height * 0.95, 300, 400 / max(0.6, sp.aspect))
                for (i, a) in poses.enumerated() {
                    let cellX = Double(i % 3) * 426 + 213, cellY = Double(1 - i / 3) * 360
                    let ground = sp.isGroundBound ? cellY + 30 : cellY + 180
                    ctx.saveGState()
                    ctx.translateBy(x: cellX, y: ground + (sp.isGroundBound ? a.lift * unit : 0))
                    ctx.scaleBy(x: unit, y: unit)
                    ink.begin(ctx, far: 0)
                    puppet.draw(ctx, a, ink)
                    ctx.restoreGState()
                }
                // And small, as it is in the far lane, facing left.
                ctx.saveGState()
                ctx.translateBy(x: 1230, y: 640)
                ctx.scaleBy(x: -unit * 0.42, y: unit * 0.42)
                ink.begin(ctx, far: 1)
                puppet.draw(ctx, poses[1], ink)
                ctx.restoreGState()
                if let image = ctx.makeImage() { Output.save(CIImage(cgImage: image), as: "model-\(scene)-\(sp.name).png") }
            }
        }
    }
}

// MARK: - Rigs and puppets

final class SceneRigTests: XCTestCase {
    func testALegKeepsItsBonesTheirLengthAndBendsTheWayItIsTold() {
        let hip = CGPoint(x: 0, y: 0.5)
        for target in [CGPoint(x: 0.1, y: 0), CGPoint(x: -0.2, y: 0.05), CGPoint(x: 0.05, y: 0.2)] {
            let ahead = SceneRig.knee(hip, target, upper: 0.27, lower: 0.27, bend: 1)
            let behind = SceneRig.knee(hip, target, upper: 0.27, lower: 0.27, bend: -1)
            XCTAssertEqual(hypot(Double(ahead.x - hip.x), Double(ahead.y - hip.y)), 0.27, accuracy: 1e-6)
            XCTAssertEqual(hypot(Double(target.x - ahead.x), Double(target.y - ahead.y)), 0.27, accuracy: 1e-4, "the foot reaches the target")
            XCTAssertGreaterThan(Double(ahead.x), Double(behind.x), "+1 puts the knee ahead of a leg pointing down")
        }
        // Out of reach: a straight leg pointing at it, the foot short of it.
        let far = CGPoint(x: 0, y: -1)
        let knee = SceneRig.knee(hip, far, upper: 0.27, lower: 0.27, bend: 1)
        let foot = SceneRig.reach(knee, far, lower: 0.27)
        XCTAssertEqual(Double(foot.y), 0.5 - 0.54, accuracy: 1e-3)
        XCTAssertTrue(Double(knee.x).isFinite && Double(knee.y).isFinite)
    }

    func testAFootIsPlantedThenSwingsAndNeverJumps() {
        var last = SceneRig.foot(0, duty: 0.6)
        for i in 1...400 {
            let p = Double(i) / 200
            let f = SceneRig.foot(p, duty: 0.6)
            XCTAssertLessThan(abs(f.forward - last.forward), 0.05, "smooth at \(p)")
            XCTAssertGreaterThanOrEqual(f.up, 0)
            if (p - floor(p)) < 0.6 { XCTAssertEqual(f.up, 0, "planted at \(p)") }
            last = f
        }
    }

    func testASpringOvershootsALittleAndSettles() {
        var x = 0.0, v = 0.0, most = 0.0
        for _ in 0..<120 {
            SceneRig.spring(&x, &v, to: 1, frequency: 1.6, damping: 0.55, dt: 1.0 / 30)
            most = max(most, x)
        }
        XCTAssertEqual(x, 1, accuracy: 0.02)
        XCTAssertGreaterThan(most, 1.0)
        XCTAssertLessThan(most, 1.25)
        SceneRig.spring(&x, &v, to: 0, frequency: 1.6, damping: 0.55, dt: 30)
        XCTAssertTrue(x.isFinite && abs(x) < 2, "a huge step does not blow up")
    }

    func testTheActorKnowsWhenAnAnimalIsWalkingRunningAndLookingAtYou() throws {
        let cast = SafariCast.cast
        var world = SceneWorld(cast: cast, seed: 5)
        let lion = try XCTUnwrap(world.creatures.firstIndex { cast.species[$0.species].name == "lion" })
        var memory = SceneRigMemory()
        let person = SceneContext(size: CGSize(width: 1280, height: 720), matte: SceneBlocks(rects: [CGRect(x: 370, y: 0, width: 540, height: 290), CGRect(x: 540, y: 300, width: 200, height: 258)]))
        var walked = false, looked = false
        world.attract(lion)
        for _ in 0..<(30 * 12) {
            world.step(1.0 / 30, context: person)
            let a = world.actor(of: world.creatures[lion], memory: &memory)
            XCTAssertTrue(a.walk >= 0 && a.walk <= 1 && a.run >= 0 && a.run <= 1)
            if a.walk > 0.9 { walked = true }
            if world.creatures[lion].phase == .acting, a.alert > 0.9 { looked = true }
        }
        XCTAssertTrue(walked, "it walked over")
        XCTAssertTrue(looked, "and is alert while it does its thing")
    }
}

final class ScenePuppetTests: XCTestCase {
    private func styles() -> [(String, SceneStyle)] { SceneModelSheetTests.styles() }

    /// Draws a puppet on a clear canvas in units, and returns the box (in units, about its anchor) of everything it painted.
    private func paintedBox(_ puppet: ScenePuppet, _ a: SceneActor, look: SceneLook, unit: Double = 120, far: Double = 0, facing: Double = 1) -> CGRect? {
        let size = 1200
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: ScenePaint.space, bitmapInfo: Sprites.bitmapInfo),
              let data = ctx.data else { return nil }
        let ink = SceneInk(look: look, lights: SceneLightBox(look: look))
        ctx.translateBy(x: 600, y: 600)
        ctx.scaleBy(x: CGFloat(unit * facing), y: CGFloat(unit))
        ink.begin(ctx, far: far)
        puppet.draw(ctx, a, ink)
        let bytes = data.bindMemory(to: UInt8.self, capacity: size * size * 4)
        var minX = size, maxX = -1, minY = size, maxY = -1
        for y in stride(from: 0, to: size, by: 2) {
            for x in stride(from: 0, to: size, by: 2) where bytes[(y * size + x) * 4 + 3] > 40 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return nil }
        // Rows in memory run top down.
        return CGRect(x: (Double(minX) - 600) / unit, y: (600 - Double(maxY)) / unit, width: Double(maxX - minX) / unit, height: Double(maxY - minY) / unit)
    }

    func testEveryCreatureInTheFiveScenesIsDrawnByHand() {
        for (scene, style) in styles() {
            for (i, sp) in style.cast.species.enumerated() {
                XCTAssertNotNil(style.puppet(for: i), "\(scene) \(sp.name) has a rig")
                XCTAssertTrue(sp.glyph.isEmpty && sp.painted, "\(scene) \(sp.name) is not an emoji")
            }
        }
    }

    func testEveryPoseOfEveryCreatureIsDrawnAndStaysInsideTheRoomTheRendererGivesIt() {
        for (scene, style) in styles() {
            for (i, sp) in style.cast.species.enumerated() {
                guard let puppet = style.puppet(for: i) else { continue }
                for (k, a) in SceneModelSheetTests.poses(sp).enumerated() {
                    for facing in [1.0, -1.0] {
                        guard let box = paintedBox(puppet, a, look: style.look, far: k == 1 ? 1 : 0, facing: facing) else {
                            XCTFail("\(scene) \(sp.name) pose \(k): nothing drawn")
                            continue
                        }
                        // The renderer keeps each creature's drawing in a picture this big about its anchor.
                        let room = SceneRenderer.room(for: sp)
                        XCTAssertTrue(room.insetBy(dx: -0.02, dy: -0.02).contains(box), "\(scene) \(sp.name) pose \(k) spills out of its picture: \(box)")
                        XCTAssertGreaterThan(box.height, sp.group > 1 ? 0.2 : 0.3, "\(scene) \(sp.name) pose \(k) is drawn at a sensible size: \(box)")
                    }
                }
            }
        }
    }

    func testOddActorValuesDoNotBreakAnyRig() {
        var a = SceneActor()
        a.time = 1e6; a.stride = -4e5; a.walk = 1; a.run = 1; a.lift = 3; a.look = 9; a.alert = 1; a.tail = -40
        a.phase = .acting; a.phaseTime = 1e4; a.pose.open = 1; a.landed = true; a.velocity = SIMD2(500, -500)
        for (_, style) in styles() {
            for i in style.cast.species.indices {
                guard let puppet = style.puppet(for: i) else { continue }
                for act in [SceneSpecies.Act.roar, .trumpet, .stomp, .chestBeat, .lean, .hop, .climb, .perch, .orbit, .lunge, .boo, .drop, .rear, .snap] {
                    a.act = act
                    XCTAssertNotNil(paintedBox(puppet, a, look: style.look, unit: 40))
                }
            }
        }
    }

    func testAHeldFrameIsReusedBetweenPosesAndRedrawnWhenDueOrWhenTheAnimalChangesSize() {
        let held = SceneHeldFrame()
        var draws = 0
        func draw(frame: Int, unit: Double) {
            if held.fresh(frame: frame, every: 3, unit: unit, facing: 1, phase: .wandering, key: 0) { return }
            held.redraw(extent: CGRect(x: -50, y: 0, width: 100, height: 100), anchor: CGPoint(x: 100.4, y: 50.7), frame: frame, unit: unit, facing: 1, phase: .wandering, key: 0) { ctx in
                draws += 1
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                ctx.fill(CGRect(x: -10, y: 0, width: 20, height: 20))
            }
        }
        for f in 0..<9 { draw(frame: f, unit: 100) }
        XCTAssertEqual(draws, 3, "drawn on threes")
        draw(frame: 9, unit: 110)
        XCTAssertEqual(draws, 4, "drawn again as soon as it changes size")
        XCTAssertNotNil(held.image)
    }
}

final class SceneLensFadeTests: XCTestCase {
    private let h = LensHarness()

    func testAFreshSceneShowsTheRoomUntilItIsPaintedThenFadesIn() {
        let base = h.input(background: false)
        let lens = SceneLens(style: HauntedScene(), seed: 4)
        let first = lens.render(h.at(base, time: 0))
        let room = h.pixel(base.composed, 30, 690), shown = h.pixel(first, 30, 690)
        XCTAssertLessThan(abs(room.r - shown.r) + abs(room.g - shown.g) + abs(room.b - shown.b), 6, "nothing pops in on the very first frame")
        var t = 0.0
        var seen: [Int] = []
        while t < 3 {
            let out = lens.render(h.at(base, time: t))
            let p = h.pixel(out, 30, 690)
            seen.append(abs(room.r - p.r) + abs(room.g - p.g) + abs(room.b - p.b))
            t += 1.0 / 30
        }
        XCTAssertGreaterThan(seen.last ?? 0, 40, "the scene is there in the end")
        // It comes in over several frames, never in one jump.
        for k in 1..<seen.count { XCTAssertLessThan(seen[k] - seen[k - 1], 80, "frame \(k) jumps") }
    }

    func testAPaintedSceneIsNotFadedAgainAfterARestart() {
        let base = h.input(background: false)
        let lens = SceneLens(style: DinoScene(), seed: 4)
        // It paints and fades in on its own, then plays for a while before the restart.
        for i in 0..<90 { _ = lens.render(h.at(base, time: Double(i) / 30)) }
        let out = lens.render(h.at(base, time: 3))
        let room = h.pixel(base.composed, 30, 690), p = h.pixel(out, 30, 690)
        XCTAssertGreaterThan(abs(room.r - p.r) + abs(room.g - p.g) + abs(room.b - p.b), 40)
        lens.restart()
        let again = h.pixel(lens.render(h.at(base, time: 0)), 30, 690)
        XCTAssertGreaterThan(abs(room.r - again.r) + abs(room.g - again.g) + abs(room.b - again.b), 40)
    }
}
