import CoreImage
import XCTest

/// The weather, light and particle filters from round one: confetti, rain, fireflies, fireworks and falling blossoms (round two's are in WorldFilterNewTests).
final class WorldFilterTests: XCTestCase {
    private let h = LensHarness()
    private let size = CGSize(width: 1280, height: 720)
    /// The synthetic person's head and shoulders, roughly, as the silhouette grid sees them.
    private var head: MatteGrid { MatteGrid.filled([CGRect(x: 540, y: 300, width: 200, height: 260)], outputSize: size) }

    private func diff(_ a: RGB, _ b: RGB) -> Int { abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) }
    private func brightness(_ p: RGB) -> Int { p.r + p.g + p.b }

    /// Runs a lens for a number of frames from `start`, saving the pictures asked for, and returns the last.
    @discardableResult
    private func play(_ lens: Lens, _ base: LensInput, frames: Int, from start: Int = 0, save: [Int: String] = [:]) -> CIImage {
        var out = base.composed
        for i in start..<(start + frames) {
            out = lens.render(h.at(base, time: Double(i) / 30))
            if let name = save[i] { Output.save(out, as: name) }
        }
        return out
    }

    // MARK: Registration

    func testTheWorldFiltersAreRegisteredAndNeedWhatTheyUse() {
        XCTAssertEqual(Array(WorldFilters.all.map(\.id).prefix(5)), ["confetti", "rain", "fireflies", "fireworks", "blossoms"])
        XCTAssertEqual(WorldFilters.all.count, 15)
        for info in WorldFilters.all {
            XCTAssertEqual(info.category, .filters)
            XCTAssertFalse(info.needsHands)
            XCTAssertFalse(info.needsFace)
            XCTAssertNotNil(LensCatalog.info(for: info.id))
            XCTAssertTrue(info.make().needs.contains(.matte), "\(info.name) puts things around the silhouette")
        }
    }

    // MARK: Confetti

    func testCannonsThrowConfettiUpAndInward() {
        var field = ConfettiCannonSim(size: size)
        field.firesByItself = false
        field.fire(side: 0, count: 80)
        XCTAssertEqual(field.pieces.count, 80)
        for _ in 0..<12 { field.step(1.0 / 30, matte: nil) }
        let top = field.pieces.map(\.position.y).max() ?? 0
        XCTAssertGreaterThan(top, 330, "the burst climbs well up the picture")
        XCTAssertGreaterThan(field.pieces.map(\.position.x).max() ?? 0, 280, "and leans in toward the middle")

        var right = ConfettiCannonSim(size: size)
        right.firesByItself = false
        right.fire(side: 1, count: 40)
        for _ in 0..<12 { right.step(1.0 / 30, matte: nil) }
        XCTAssertLessThan(right.pieces.map(\.position.x).min() ?? 1280, 1000, "the right cannon throws to the left")
    }

    func testConfettiSlowsDownTumblesAndEventuallyLeaves() {
        var field = ConfettiCannonSim(size: size)
        field.firesByItself = false
        field.fire(side: 0, count: 60)
        let spun = field.pieces.map(\.flip)
        for _ in 0..<45 { field.step(1.0 / 30, matte: nil) }
        let speeds = field.pieces.map { ($0.velocity.x * $0.velocity.x + $0.velocity.y * $0.velocity.y).squareRoot() }
        XCTAssertLessThan(speeds.max() ?? 0, 330, "a second and a half on, air drag has slowed it to a drift")
        XCTAssertNotEqual(field.pieces.map(\.flip), spun, "the paper tumbles end over end")
        for _ in 0..<600 { field.step(1.0 / 30, matte: nil) }
        XCTAssertTrue(field.pieces.isEmpty, "twenty seconds later it has all fallen out of the picture")
    }

    func testConfettiHopsOnceThenSettlesOnYouAndFallsWhenYouLeave() {
        var field = ConfettiCannonSim(size: size)
        field.firesByItself = false
        let rect = CGRect(x: 540, y: 300, width: 200, height: 260)
        let you = MatteGrid.filled([rect], outputSize: size)
        func piece(x: Double) -> ConfettiCannonSim.Piece {
            ConfettiCannonSim.Piece(position: SIMD2(x, 640), velocity: SIMD2(0, -120), angle: 0, spin: 0, flip: 0, flipRate: 0, size: 14, colour: 1,
                                  shape: .rectangle, life: 30, swayPhase: 0, swayRate: 0, lightness: 0.5)
        }
        for i in 0..<20 { field.insert(piece(x: 560 + Double(i) * 8)) }
        var hopped = false, peak = 0
        for _ in 0..<150 {
            field.step(1.0 / 30, matte: you)
            if field.pieces.contains(where: { $0.bounced && !$0.resting && $0.velocity.y > 20 }) { hopped = true }
            if field.restingCount > peak {
                peak = field.restingCount
                for p in field.pieces where p.resting {
                    XCTAssertTrue(rect.insetBy(dx: -12, dy: -14).contains(CGPoint(x: p.position.x, y: p.position.y)), "resting at \(p.position)")
                }
            }
        }
        XCTAssertTrue(hopped, "the first touch is a little hop")
        XCTAssertGreaterThan(peak, 10, "and then the paper sits on your head")
        for _ in 0..<15 { field.step(1.0 / 30, matte: MatteGrid(outputSize: size)) }
        XCTAssertEqual(field.restingCount, 0, "step out of the way and it falls")
        XCTAssertGreaterThan(field.pieces.count, 0)
    }

    func testConfettiNeverGrowsWithoutLimitAndSurvivesAHugeDt() {
        var field = ConfettiCannonSim(size: size)
        for i in 0..<900 { field.step(i == 100 ? 5.0 : 1.0 / 30, matte: head) }
        XCTAssertLessThanOrEqual(field.pieces.count, field.capacity)
        XCTAssertTrue(field.pieces.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })
        XCTAssertGreaterThan(field.shots, 8, "the cannons keep firing")
    }

    func testConfettiLensColoursTheRoomAndTheCannonsShowAtTheCorners() {
        let lens = ConfettiCannonLens()
        let base = h.input()
        let out = play(lens, base, frames: 100, save: [10: "confetti-burst.png", 40: "confetti-air.png", 99: "confetti-late.png"])
        XCTAssertEqual(out.extent, base.rect)
        XCTAssertGreaterThan(lens.pieceCount, 80)
        // The left cannon is a red barrel in the corner.
        XCTAssertGreaterThan(diff(h.pixel(out, 40, 24), h.pixel(base.composed, 40, 24)), 60)
        // Your face is only touched when a piece happens to fall past; most of it is exactly as it was.
        let calm = h.pixel(out, 640, 420), plain = h.pixel(base.composed, 640, 420)
        XCTAssertLessThan(diff(calm, plain), 255)
    }

    func testConfettiWithNobodyInViewStillFalls() {
        let lens = ConfettiCannonLens()
        let base = h.input()
        let lonely = LensInput(time: 0, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: nil, background: nil, composed: base.camera,
                               matteGrid: nil, face: nil, services: base.services)
        for _ in 0..<30 { _ = lens.render(lonely) }
        XCTAssertGreaterThan(lens.pieceCount, 50)
        XCTAssertEqual(lens.restingCount, 0, "with no one there it has nothing to land on")
    }

    // MARK: Rain

    func testRainFallsAtAnAngleAndKeepsComing() {
        var storm = RainstormSim(size: size)
        let before = storm.near.map(\.position)
        storm.step(1.0 / 30, matte: nil)
        let after = storm.near.map(\.position)
        var moved = 0
        for (a, b) in zip(before, after) where b.y < a.y && b.x < a.x { moved += 1 }
        XCTAssertGreaterThanOrEqual(moved, storm.near.count - 10, "nearly every drop moves down and to the left on the wind")
        for _ in 0..<300 { storm.step(1.0 / 30, matte: nil) }
        XCTAssertEqual(storm.near.count, 100)
        XCTAssertEqual(storm.far.count, 160)
        XCTAssertGreaterThan(storm.near.filter { $0.position.y > 360 }.count, 15, "and the top half of the picture is never left dry")
    }

    func testRainSplashesOffTheTopOfYouAndNeverFallsThroughYou() {
        var storm = RainstormSim(size: size)
        let you = head
        var onHead = 0
        for _ in 0..<150 {
            storm.step(1.0 / 30, matte: you)
            for p in storm.splashes.particles where p.age < 0.04 && p.position.x > 530 && p.position.x < 750 && p.position.y > 540 && p.position.y < 600 { onHead += 1 }
            XCTAssertTrue(storm.near.allSatisfy { you.coverage(x: $0.position.x, y: $0.position.y) < 0.5 }, "a near drop must not be inside you")
        }
        XCTAssertGreaterThan(storm.splashCount, 25)
        XCTAssertGreaterThan(onHead, 20, "splashes start at the top of your silhouette")
        XCTAssertLessThanOrEqual(storm.splashes.particles.count, 260)
    }

    func testLightningFlashesTwiceThenDarkensAgain() {
        XCTAssertEqual(RainstormSim.flash(sinceStrike: -1), 0)
        XCTAssertEqual(RainstormSim.flash(sinceStrike: 0.025), 1, accuracy: 0.01)
        XCTAssertLessThan(RainstormSim.flash(sinceStrike: 0.14), 0.25, "dips between the two flashes")
        XCTAssertGreaterThan(RainstormSim.flash(sinceStrike: 0.225), 0.55, "then flashes again")
        XCTAssertLessThan(RainstormSim.flash(sinceStrike: 0.9), 0.01)

        var storm = RainstormSim(size: size)
        XCTAssertNil(storm.bolt)
        storm.strike()
        let bolt = storm.bolt
        XCTAssertNotNil(bolt)
        XCTAssertGreaterThan(bolt?.points.count ?? 0, 30, "a jagged bolt, not a straight line")
        XCTAssertGreaterThan(bolt?.points.first?.y ?? 0, 700, "it starts at the top of the sky")
        XCTAssertLessThan(bolt?.points.last?.y ?? 999, 320, "and comes a good way down")
        for _ in 0..<12 { storm.step(1.0 / 30, matte: nil) }
        XCTAssertNil(storm.bolt, "gone after a third of a second")
    }

    func testRainGradesTheWholePictureDarkAndCoolAndAFlashLightsItUp() {
        let lens = RainstormLens()
        let base = h.input()
        let sample = CGRect(x: 20, y: 480, width: 220, height: 200)
        let plain = h.average(base.composed, sample)
        let out = play(lens, base, frames: 30, save: [29: "rain.png"])
        let rain = h.average(out, sample)
        XCTAssertLessThan(rain.r + rain.g + rain.b, (plain.r + plain.g + plain.b) * 0.92, "darker than the room was")
        XCTAssertGreaterThan(rain.b / max(0.01, rain.r), plain.b / max(0.01, plain.r), "and cooler")

        lens.strike()
        let lit = lens.render(h.at(base, time: 1.0))
        Output.save(lit, as: "rain-lightning.png")
        let flashed = h.average(lit, sample)
        XCTAssertGreaterThan(flashed.r + flashed.g + flashed.b, (rain.r + rain.g + rain.b) * 1.5, "a strike lights the whole room")
        var later = lit
        for i in 0..<30 { later = lens.render(h.at(base, time: 1.1 + Double(i) / 30)) }
        let settled = h.average(later, sample)
        XCTAssertLessThan(settled.r + settled.g + settled.b, (flashed.r + flashed.g + flashed.b) * 0.7)
    }

    func testTheSameSeedMakesTheSameStorm() {
        var a = RainstormSim(size: size, seed: 7), b = RainstormSim(size: size, seed: 7), c = RainstormSim(size: size, seed: 8)
        for _ in 0..<60 { a.step(1.0 / 30, matte: head); b.step(1.0 / 30, matte: head); c.step(1.0 / 30, matte: head) }
        XCTAssertEqual(a.near.map(\.position), b.near.map(\.position))
        XCTAssertNotEqual(a.near.map(\.position), c.near.map(\.position))
    }

    // MARK: Fireflies

    func testFirefliesWanderInsideThePictureAndBlinkOnAndOff() {
        var glade = FireflyGladeSim(size: size)
        var levels: [Double] = []
        for _ in 0..<900 {
            glade.step(1.0 / 30, interest: nil)
            levels.append(FireflyGladeSim.glow(of: glade.flies[0]))
        }
        for f in glade.flies {
            XCTAssertTrue(f.position.x > -40 && f.position.x < 1320 && f.position.y > -40 && f.position.y < 760, "stays near the picture: \(f.position)")
        }
        XCTAssertGreaterThan(levels.max() ?? 0, 0.85, "it lights up")
        XCTAssertLessThan(levels.min() ?? 1, 0.02, "and goes dark")
        XCTAssertGreaterThan(levels.filter { $0 < 0.02 }.count, 200, "it spends a good while dark")
        XCTAssertTrue(glade.flies.contains { simdLength($0.velocity) > 10 }, "they move about")
    }

    func testFirefliesDriftTowardWhereYouMove() {
        var free = FireflyGladeSim(size: size, seed: 3), curious = FireflyGladeSim(size: size, seed: 3)
        let spot = SIMD2<Double>(900, 360)
        func meanDistance(_ g: FireflyGladeSim) -> Double {
            g.flies.map { simdLength($0.position - spot) }.reduce(0, +) / Double(g.flies.count)
        }
        let start = meanDistance(free)
        for _ in 0..<240 {
            free.step(1.0 / 30, interest: nil)
            curious.step(1.0 / 30, interest: FireflyGladeSim.Interest(point: spot, strength: 1))
        }
        XCTAssertLessThan(meanDistance(curious), meanDistance(free) - 80, "they gather round")
        XCTAssertGreaterThan(meanDistance(curious), 60, "but do not pile onto one spot")
        _ = start
        XCTAssertTrue(curious.flies.contains { FireflyGladeSim.glow(of: $0) > 0.3 }, "excited ones glow")
    }

    func testTheMotionWatcherFindsAMovingArmAndIgnoresAStillBody() {
        var watcher = FireflyMotionWatcher()
        let still = MatteGrid.filled([CGRect(x: 500, y: 100, width: 260, height: 460)], outputSize: size)
        XCTAssertNil(watcher.interest(from: still))
        XCTAssertNil(watcher.interest(from: still), "nothing moved")
        let armUp = MatteGrid.filled([CGRect(x: 500, y: 100, width: 260, height: 460), CGRect(x: 800, y: 300, width: 90, height: 260)], outputSize: size)
        let found = watcher.interest(from: armUp)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.point.x ?? 0, 845, accuracy: 40)
        XCTAssertEqual(found?.point.y ?? 0, 430, accuracy: 60)
        _ = watcher.interest(from: armUp)
        for _ in 0..<80 { _ = watcher.interest(from: armUp) }
        XCTAssertNil(watcher.interest(from: armUp), "interest fades once you are still again")
        XCTAssertNil(watcher.interest(from: nil))
    }

    func testFirefliesDarkenTheNightAndGlowBrightly() {
        let lens = FireflyGladeLens()
        let base = h.input()
        let corners = [CGRect(x: 20, y: 480, width: 220, height: 200), CGRect(x: 1040, y: 480, width: 220, height: 200), CGRect(x: 1040, y: 20, width: 220, height: 200)]
        let plain = corners.map { h.average(base.composed, $0) }
        let out = play(lens, base, frames: 120, save: [119: "fireflies.png"])
        for (corner, before) in zip(corners, plain) {
            let night = h.average(out, corner)
            XCTAssertLessThan(night.r + night.g + night.b, (before.r + before.g + before.b) * 0.6, "the night is dark around \(corner)")
        }
        // Find a lit fly out in the open and check there is a bright point there.
        let lit = lens.flies.filter { FireflyGladeSim.glow(of: $0) > 0.8 && ($0.position.x < 380 || $0.position.x > 900) && $0.position.y > 30 && $0.position.y < 690 }
        for fly in lit.prefix(3) {
            let p = h.pixel(out, Int(fly.position.x), Int(fly.position.y))
            XCTAssertGreaterThan(brightness(p), 300, "a glowing firefly at \(fly.position) should be bright, got \(p)")
        }
    }

    // MARK: Fireworks

    func testARocketClimbsThenBurstsIntoSparksThatFadeAway() {
        var show = FireworkSkySim(size: size)
        show.launchesByItself = false
        show.launch(x: 640, topY: 520, hue: 0.6, shell: .peony)
        var seenHigh = 0.0
        for _ in 0..<60 {
            show.step(1.0 / 30)
            seenHigh = max(seenHigh, show.rockets.first?.position.y ?? 0)
        }
        XCTAssertGreaterThan(seenHigh, 400, "the rocket climbs")
        XCTAssertEqual(show.bursts, 1, "and bursts at the top")
        XCTAssertTrue(show.rockets.isEmpty)
        let peak = show.sparks.particles.count
        XCTAssertGreaterThan(peak, 40)
        XCTAssertGreaterThan(show.skyLight.z + show.skyLight.x + show.skyLight.y, 0.1, "the burst lights the sky")
        for _ in 0..<150 { show.step(1.0 / 30) }
        XCTAssertEqual(show.sparks.particles.count, 0, "every spark has burnt out five seconds later")
        XCTAssertEqual(show.flashes.count, 0)
    }

    func testEveryKindOfShellMakesSparksInItsOwnShape() {
        for shell in FireworkSkySim.Shell.allCases {
            var show = FireworkSkySim(size: size, seed: 5)
            show.launchesByItself = false
            show.detonate(at: SIMD2(640, 450), hue: 0.9, shell: shell)
            XCTAssertGreaterThan(show.sparks.particles.count, 40, "\(shell)")
            for _ in 0..<24 { show.step(1.0 / 30) }
            let reach = show.sparks.particles.map { simdLength($0.position - SIMD2(640, 450)) }.max() ?? 0
            XCTAssertGreaterThan(reach, 90, "\(shell) spreads out")
            XCTAssertLessThan(reach, 700, "\(shell) stays on screen")
        }
        var heart = FireworkSkySim(size: size, seed: 5)
        heart.launchesByItself = false
        heart.detonate(at: SIMD2(640, 450), hue: 0.9, shell: .heart)
        for _ in 0..<20 { heart.step(1.0 / 30) }
        let xs = heart.sparks.particles.map(\.position.x), ys = heart.sparks.particles.map(\.position.y)
        XCTAssertGreaterThan((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0) * 0.85 - 20, "a heart is about as wide as it is tall")
    }

    func testTheShowKeepsLaunchingAndNeverRunsAway() {
        var show = FireworkSkySim(size: size)
        for i in 0..<1200 { show.step(i == 300 ? 3.0 : 1.0 / 30) }
        XCTAssertGreaterThan(show.bursts, 12, "a burst every second or two")
        XCTAssertLessThanOrEqual(show.sparks.particles.count, 560)
        XCTAssertLessThanOrEqual(show.rockets.count, 4)
        XCTAssertTrue(show.sparks.particles.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })
    }

    func testFireworksBurstBehindYouAndDarkenTheRoom() {
        let lens = FireworkSkyLens()
        lens.launchesByItself = false
        let base = h.input()
        let corner = CGRect(x: 20, y: 20, width: 200, height: 160)
        let plain = h.average(base.composed, corner)
        lens.burst(at: CGPoint(x: 330, y: 470), hue: 0.02)
        let out = play(lens, base, frames: 14, save: [13: "fireworks-burst.png"])
        let sky = h.average(out, corner)
        XCTAssertLessThan(sky.r + sky.g + sky.b, (plain.r + plain.g + plain.b) * 0.7, "the room goes dark")
        // Around the burst it is bright and red; elsewhere in the sky it is dark.
        let burst = h.average(out, CGRect(x: 170, y: 340, width: 320, height: 260)), quiet = h.average(out, CGRect(x: 900, y: 20, width: 320, height: 200))
        XCTAssertGreaterThan(burst.r + burst.g + burst.b, (quiet.r + quiet.g + quiet.b) * 1.4)
        XCTAssertGreaterThan(burst.r, burst.b, "a red burst")
        XCTAssertGreaterThan(lens.sparkCount, 40)
    }

    func testFireworksSparksNeverLandOnThePerson() {
        let lens = FireworkSkyLens()
        lens.launchesByItself = false
        let base = h.input()
        lens.burst(at: CGPoint(x: 640, y: 330), hue: 0.15, shell: .peony)
        let skin = h.pixel(base.composed, 640, 380)
        var worst = 0
        var out = base.composed
        for i in 0..<18 {
            out = lens.render(h.at(base, time: Double(i) / 30))
            // Inside the head: skin colour, which is the least blue of the three. Sparks over it would turn it white.
            if i % 3 == 0 { worst = max(worst, h.pixel(out, 640, 380).b - skin.b) }
        }
        Output.save(out, as: "fireworks-behind-you.png")
        XCTAssertLessThan(worst, 30, "your skin stays skin-coloured however many sparks fly behind it")
    }

    func testTheShowAndEveryShellLookRightInPictures() {
        let base = h.input()
        let show = FireworkSkyLens()
        for i in 0..<130 {
            let out = show.render(h.at(base, time: Double(i) / 30))
            if i == 60 || i == 100 || i == 129 { Output.save(out, as: "fireworks-show-\(i).png") }
        }
        XCTAssertGreaterThan(show.burstCount, 2)
        for (shell, name) in [(FireworkSkySim.Shell.ring, "ring"), (.chrysanthemum, "chrysanthemum"), (.willow, "willow"), (.heart, "heart")] {
            let lens = FireworkSkyLens()
            lens.launchesByItself = false
            lens.burst(at: CGPoint(x: 330, y: 470), hue: 0.9, shell: shell)
            var out = base.composed
            for i in 0..<(shell == .willow ? 50 : 22) { out = lens.render(h.at(base, time: Double(i) / 30)) }
            Output.save(out, as: "fireworks-\(name).png")
            XCTAssertGreaterThan(lens.sparkCount, 40, name)
        }
    }

    // MARK: Blossoms

    func testPetalsStartAlreadyFlutteringAndFallThroughTheFrame() {
        var drift = PetalDriftSim(style: .sakura, size: size)
        XCTAssertGreaterThan(drift.petals.count, 80, "there are petals in the air from the first frame")
        let heights = drift.petals.map(\.position.y)
        XCTAssertGreaterThan(heights.max() ?? 0, 600)
        XCTAssertLessThan(heights.min() ?? 999, 200)
        for _ in 0..<30 { drift.step(1.0 / 30, matte: nil) }
        let falling = drift.petals.filter { $0.velocity.y < -10 }.count
        XCTAssertGreaterThan(falling, drift.petals.count * 9 / 10, "nearly all of them are coming down")
    }

    func testTheWindSwingsBothWaysSoPetalsTravelInDrifts() {
        let winds = stride(from: 0.0, to: 60, by: 0.5).map { PetalDriftSim.wind(at: $0) }
        XCTAssertGreaterThan(winds.max() ?? 0, 60)
        XCTAssertLessThan(winds.min() ?? 0, -60)
        var drift = PetalDriftSim(style: .sakura, size: size)
        let before = drift.petals.count
        drift.flurry()
        XCTAssertGreaterThanOrEqual(drift.petals.count, min(drift.capacity, before + 20), "a flurry throws in a cluster")
        let sideways = drift.petals.suffix(20).filter { abs($0.velocity.x) > 150 }.count
        XCTAssertGreaterThan(sideways, 15, "moving fast across the picture")
    }

    func testPetalsSettleOnYourHeadAndShouldersAndFallAgain() {
        var drift = PetalDriftSim(style: .sakura, size: size)
        let rect = CGRect(x: 540, y: 300, width: 200, height: 260)
        let you = MatteGrid.filled([rect], outputSize: size)
        for _ in 0..<450 { drift.step(1.0 / 30, matte: you) }
        XCTAssertGreaterThan(drift.restingCount, 2, "a few petals rest on you")
        for p in drift.petals where p.resting {
            XCTAssertFalse(p.isBehind, "only petals in front of you can land on you")
            XCTAssertFalse(p.isBlur)
        }
        for _ in 0..<12 { drift.step(1.0 / 30, matte: MatteGrid(outputSize: size)) }
        XCTAssertEqual(drift.restingCount, 0, "and they let go when you move away")
    }

    func testBothStylesDrawAndLookDifferent() {
        let base = h.input()
        var outs: [CIImage] = []
        for (style, name) in [(PetalDriftSim.Style.sakura, "blossoms.png"), (.autumn, "blossoms-autumn.png")] {
            let lens = PetalDriftLens(style: style)
            let out = play(lens, base, frames: 90, save: [89: name])
            outs.append(out)
            XCTAssertEqual(out.extent, base.rect)
            XCTAssertGreaterThan(lens.petalCount, 80)
        }
        let corner = CGRect(x: 20, y: 400, width: 300, height: 300)
        let a = h.average(outs[0], corner), b = h.average(outs[1], corner)
        XCTAssertGreaterThan(abs(a.b - b.b) + abs(a.r - b.r), 0.015, "pink spring against amber autumn")
    }

    // MARK: Every filter

    func testEveryWorldFilterRendersWithAndWithoutAPersonAndAfterARestart() {
        let base = h.input()
        let lonely = LensInput(time: 0, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: nil, background: nil, composed: base.camera,
                               matteGrid: nil, face: nil, services: base.services)
        for info in WorldFilters.all {
            let lens = info.make()
            let out = play(lens, base, frames: 6)
            XCTAssertEqual(out.extent, base.rect, info.name)
            XCTAssertGreaterThan(h.bitmap(out).change(from: h.bitmap(base.composed), in: base.rect), 60, "\(info.name) changes the picture")
            for _ in 0..<4 { XCTAssertEqual(lens.render(lonely).extent, base.rect, "\(info.name) with nobody in view") }
            lens.restart()
            XCTAssertEqual(lens.render(h.at(base, time: 0)).extent, base.rect, "\(info.name) after a restart")
            // A frame that took far too long must not throw everything off the screen.
            let stalled = LensInput(time: 9, dt: 4, rect: base.rect, camera: base.camera, matte: base.matte, background: base.background, composed: base.composed,
                                    matteGrid: base.matteGrid, face: nil, services: base.services)
            XCTAssertEqual(lens.render(stalled).extent, base.rect, "\(info.name) after a stall")
        }
    }

    func testEveryWorldFilterIsCheap() {
        let base = h.input()
        let buffer = h.compositor.makeOutputBuffer()!
        /// The median milliseconds to make and render a frame: the middle value ignores the odd slow frame when the machine is busy.
        func median(_ lens: Lens) -> Double {
            var times: [Double] = []
            for i in 0..<110 {
                let started = CFAbsoluteTimeGetCurrent()
                h.compositor.render(lens.render(h.at(base, time: Double(i) / 30)), into: buffer)
                if i >= 20 { times.append((CFAbsoluteTimeGetCurrent() - started) * 1000) }    // sprites are drawn once, on the first frames
            }
            return times.sorted()[times.count / 2]
        }
        final class Nothing: Lens {
            let needs: LensNeeds = []
            func render(_ input: LensInput) -> CIImage { input.composed }
        }
        let baseline = median(Nothing())
        for info in WorldFilters.all {
            let added = median(info.make()) - baseline
            XCTAssertLessThan(added, 9, "\(info.name) adds \(added) ms a frame to the \(baseline) ms of doing nothing")
        }
    }

    private func simdLength(_ v: SIMD2<Double>) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }
}
