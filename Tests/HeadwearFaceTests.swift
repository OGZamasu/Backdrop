import simd
import CoreImage
import XCTest

/// Shared helpers for the dress-up tests.
private enum HeadwearTestKit {
    /// A frame like `base` but with another face (or none) at another moment.
    static func frame(_ base: LensInput, face: FaceState?, time: Double, dt: Double = 1.0 / 30, matte: Bool = true) -> LensInput {
        LensInput(time: time, dt: dt, rect: base.rect, camera: base.camera, matte: matte ? base.matte : nil, background: base.background,
                  composed: base.composed, matteGrid: base.matteGrid, face: face, services: base.services)
    }

    /// Plays `scene` for `frames` frames, carrying on from frame number `start`, and returns the last picture.
    @discardableResult
    static func play(_ lens: Lens, _ base: LensInput, _ scene: SyntheticScene?, frames: Int, start: Int = 0, matte: Bool = true) -> CIImage {
        var out = base.composed
        for i in 0..<frames { out = lens.render(frame(base, face: scene?.face(), time: Double(start + i) / 30, matte: matte)) }
        return out
    }

    /// Face units to output pixels for a face, so a test can say "above the head" in the same terms the costumes are drawn in.
    struct Spot {
        let face: FaceState
        func point(_ x: Double, _ y: Double) -> CGPoint {
            let c = cos(face.roll), s = sin(face.roll), io = face.interocular
            return CGPoint(x: face.eyeCenter.x + (x * c - y * s) * io, y: face.eyeCenter.y + (x * s + y * c) * io)
        }
        /// The box round a rectangle of face units (exact when the head is upright).
        func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> CGRect {
            let corners = [point(x0, y0), point(x1, y0), point(x0, y1), point(x1, y1)]
            let xs = corners.map(\.x), ys = corners.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
    }

    /// A rectangle of face units.
    struct Zone {
        let x0: Double, y0: Double, x1: Double, y1: Double
        init(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) { self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1 }
        func rect(_ face: FaceState) -> CGRect { Spot(face: face).box(x0, y0, x1, y1) }
    }

    /// Where each costume has something to show once it has settled. The first zone is the first thing to arrive.
    static let zones: [HeadwearKind: [Zone]] = [
        .dog: [Zone(1.05, 0.0, 1.45, 0.8), Zone(-1.45, 0.0, -1.05, 0.8), Zone(-0.15, -0.7, 0.15, -0.45)],
        .bunny: [Zone(0.3, 1.3, 0.6, 2.0), Zone(-0.6, 1.3, -0.3, 2.0), Zone(-0.15, -0.7, 0.15, -0.45)],
        .devil: [Zone(0.45, 1.0, 0.85, 1.7), Zone(-0.85, 1.0, -0.45, 1.7)],
        .angel: [Zone(-0.7, 1.7, 0.7, 2.1)],
        .pirate: [Zone(-0.6, 1.3, 0.6, 1.9), Zone(-0.7, -0.2, -0.3, 0.2), Zone(1.0, -0.75, 1.35, -0.4)],
        .wizard: [Zone(-0.3, 1.4, 0.3, 2.0), Zone(-0.4, -2.9, 0.4, -2.0), Zone(-0.5, -0.9, 0.5, -0.7)],
        .santa: [Zone(-0.9, 0.98, 0.9, 1.3), Zone(-0.5, -2.2, 0.5, -1.75)],
        .gentleman: [Zone(-0.5, 1.5, 0.5, 2.3), Zone(-0.5, -0.95, 0.5, -0.65), Zone(0.15, -0.4, 0.85, 0.4)],
        .clown: [Zone(-1.0, 1.2, 1.0, 1.6), Zone(-0.2, -0.75, 0.2, -0.4)],
        .flowers: [Zone(-0.6, 1.1, 0.6, 1.5)],
        .catEars: [Zone(0.45, 1.3, 0.9, 1.8), Zone(-0.2, 1.25, 0.2, 1.45)],
        .shades: [Zone(-0.9, -0.15, -0.2, 0.15), Zone(0.2, -0.15, 0.9, 0.15)],
        .crown: [Zone(-0.6, 1.3, 0.6, 1.9)],
        .partyHat: [Zone(-0.1, 1.3, 0.5, 2.0)],
        .headphones: [Zone(1.05, -0.5, 1.4, 0.1), Zone(-1.4, -0.5, -1.05, 0.1)],
        .cowboy: [Zone(-0.6, 1.2, 0.6, 1.8), Zone(-0.4, -2.3, 0.4, -1.95)],
        .viking: [Zone(-0.6, 1.3, 0.6, 1.8), Zone(0.9, -1.2, 1.15, -0.4)],
        .propeller: [Zone(-0.6, 1.0, 0.6, 1.5)],
        .astronaut: [Zone(1.85, -0.3, 2.1, 0.3), Zone(-0.5, -2.4, 0.5, -2.0)],
        .chef: [Zone(-0.6, 1.2, 0.6, 1.9), Zone(-0.5, -0.9, 0.5, -0.65)],
        .fox: [Zone(0.55, 1.4, 0.95, 1.9), Zone(-0.12, -0.65, 0.12, -0.5)],
        .panda: [Zone(0.75, 1.0, 1.4, 1.55), Zone(0.25, -0.35, 0.75, -0.18)],
        .tabby: [Zone(0.5, 1.35, 0.9, 1.8), Zone(-0.2, -0.8, 0.2, -0.65)],
        .unicorn: [Zone(-0.12, 1.6, 0.12, 2.2)],
        .mermaid: [Zone(-0.3, 1.2, 0.3, 1.7)],
        .robot: [Zone(1.0, -0.4, 1.3, 0.0), Zone(-0.6, 1.0, 0.6, 1.5)],
        .reindeer: [Zone(0.4, 1.5, 1.0, 2.2), Zone(-0.1, -0.65, 0.1, -0.45)],
        .witch: [Zone(-0.4, 1.3, 0.4, 2.0)],
    ]

    /// A spot near where each costume is fixed to the head, in face units, that must follow a tilt.
    static let anchors: [HeadwearKind: (Double, Double)] = [
        .dog: (1.05, 0.7), .bunny: (0.42, 1.3), .devil: (0.6, 1.2), .angel: (0.0, 1.88), .pirate: (0.0, 1.5),
        .wizard: (0.0, 1.1), .santa: (0.0, 1.15), .gentleman: (0.0, 1.25), .clown: (0.0, 1.35), .flowers: (0.0, 1.25),
        .catEars: (0.0, 1.36), .shades: (-0.5, 0.18), .crown: (0.0, 1.3), .partyHat: (0.2, 1.4), .headphones: (1.2, -0.22), .cowboy: (0.0, 1.5),
        .viking: (0.0, 1.4), .propeller: (0.0, 1.2), .astronaut: (0.0, -2.15), .chef: (0.0, 1.0), .fox: (0.75, 1.5), .panda: (1.0, 1.2),
        .tabby: (0.75, 1.4), .unicorn: (0.0, 1.7), .mermaid: (0.0, 1.4), .robot: (1.14, -0.2), .reindeer: (0.53, 1.42), .witch: (0.0, 1.6),
    ]

    static func isGold(_ p: RGB) -> Bool { p.r > 200 && p.g > 140 && p.b < 130 }
    static func isPink(_ p: RGB) -> Bool { p.r > 200 && p.g < 170 && p.b > 100 && p.b < 200 && p.r - p.g > 60 }
    static func isRed(_ p: RGB) -> Bool { p.r > 190 && p.g < 90 && p.b < 100 }
    static func isWhite(_ p: RGB) -> Bool { p.r > 215 && p.g > 215 && p.b > 215 }
}

final class HeadwearPlacementTests: XCTestCase {
    private let h = LensHarness()
    private typealias Kit = HeadwearTestKit

    private func lonely(_ base: LensInput) -> LensInput { Kit.frame(base, face: nil, time: 0) }

    func testEveryCostumeShowsWhereItBelongsAndNowhereElse() {
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let base = h.input(scene)
        let plain = h.bitmap(base.composed)
        let face = scene.face()
        let corner = CGRect(x: 20, y: 20, width: 200, height: 100)
        let topCorner = CGRect(x: 20, y: 600, width: 200, height: 100)
        for kind in HeadwearKind.allCases {
            guard let zones = Kit.zones[kind] else { continue }
            let lens = DressUpLens(kind: kind)
            let out = Kit.play(lens, base, scene, frames: 45)           // long enough to land and unfold
            Output.save(out, as: "headwear-\(kind.rawValue)-neutral.png")
            let bits = h.bitmap(out)
            for (i, zone) in zones.enumerated() {
                XCTAssertGreaterThan(bits.change(from: plain, in: zone.rect(face)), 100, "\(kind): zone \(i) should have something in it")
            }
            XCTAssertEqual(bits.change(from: plain, in: corner), 0, "\(kind) shouldn't touch the far corner")
            XCTAssertEqual(bits.change(from: plain, in: topCorner), 0, "\(kind) shouldn't touch the far top corner")
            XCTAssertEqual(out.extent, base.rect, "\(kind)")
        }
    }

    func testWithNoFaceThereIsNothingToDress() {
        let base = h.input(SyntheticScene(center: CGPoint(x: 640, y: 380)))
        let plain = h.bitmap(base.composed)
        for kind in HeadwearKind.allCases {
            let lens = DressUpLens(kind: kind)
            XCTAssertEqual(h.bitmap(lens.render(lonely(base))).change(from: plain, in: base.rect), 0, "\(kind): with no face the picture is untouched")
            XCTAssertEqual(lens.status?.title, "Looking for your face…", "\(kind)")
            // When a face is lost after it had been dressed, the costume fades away over a moment rather than vanishing.
            Kit.play(lens, base, SyntheticScene(center: CGPoint(x: 640, y: 380)), frames: 40)
            let fading = h.bitmap(lens.render(Kit.frame(base, face: nil, time: 2)))
            XCTAssertGreaterThan(fading.change(from: plain, in: base.rect), 30, "\(kind): still there, fading, just after the face is lost")
            Kit.play(lens, base, nil, frames: 10, start: 61)
            XCTAssertEqual(h.bitmap(lens.render(Kit.frame(base, face: nil, time: 3))).change(from: plain, in: base.rect), 0, "\(kind): and gone a moment later")
        }
    }

    func testCostumesFollowAMovedHead() {
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let base = h.input(scene)
        let plain = h.bitmap(base.composed)
        let moved = SyntheticScene(center: CGPoint(x: 300, y: 380))
        for kind in HeadwearKind.allCases {
            guard let zone = Kit.zones[kind]?.first else { continue }
            let lens = DressUpLens(kind: kind)
            let bits = h.bitmap(Kit.play(lens, base, moved, frames: 45))
            XCTAssertGreaterThan(bits.change(from: plain, in: zone.rect(moved.face())), 100, "\(kind): over the head where it is now")
            XCTAssertLessThan(bits.change(from: plain, in: zone.rect(scene.face())), 25, "\(kind): and not where the head used to be")
        }
    }

    func testCostumesFollowATiltedHead() {
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let base = h.input(scene)
        let plain = h.bitmap(base.composed)
        var tilted = scene; tilted.roll = 0.5
        let upright = scene.face(), leaning = tilted.face()
        for kind in HeadwearKind.allCases {
            guard let (ax, ay) = Kit.anchors[kind] else { continue }
            let lens = DressUpLens(kind: kind)
            let out = Kit.play(lens, base, tilted, frames: 45)
            Output.save(out, as: "headwear-\(kind.rawValue)-tilted.png")
            let bits = h.bitmap(out)
            let there = Kit.Spot(face: leaning).point(ax, ay)
            let window = CGRect(x: there.x - 12, y: there.y - 12, width: 24, height: 24)
            XCTAssertGreaterThan(bits.change(from: plain, in: window), 60, "\(kind): fixed to the tilted head at \(there)")
            // And the picture is not the upright one turned a little: it really is another picture.
            let straight = h.bitmap(Kit.play(DressUpLens(kind: kind), base, scene, frames: 45))
            XCTAssertGreaterThan(bits.change(from: straight, in: Kit.Spot(face: upright).box(-2.2, -2.4, 2.2, 3.0)), 100, "\(kind): tilting moves it")
        }
    }

    func testTheFirstFrameIsEmptyAndThenItArrives() {
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let base = h.input(scene)
        let plain = h.bitmap(base.composed)
        for kind in HeadwearKind.allCases {
            guard let zone = Kit.zones[kind]?.first else { continue }
            let lens = DressUpLens(kind: kind)
            let early = h.bitmap(lens.render(Kit.frame(base, face: scene.face(), time: 0)))
            XCTAssertLessThan(early.change(from: plain, in: zone.rect(scene.face())), 15, "\(kind): at first it hasn't landed")
            Kit.play(lens, base, scene, frames: 40, start: 1)
            let late = h.bitmap(lens.render(Kit.frame(base, face: scene.face(), time: 2)))
            XCTAssertGreaterThan(late.change(from: plain, in: zone.rect(scene.face())), 100, "\(kind): and then it is there")
        }
    }

    func testAFaceThatFlickersAwayForAMomentKeepsItsCostumeAndALongAbsenceStartsOver() {
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let base = h.input(scene)
        let plain = h.bitmap(base.composed)
        for kind in HeadwearKind.allCases {
            guard let zone = Kit.zones[kind]?.first else { continue }
            let lens = DressUpLens(kind: kind)
            Kit.play(lens, base, scene, frames: 40)
            // Gone for a fifth of a second: when it comes back it is still there (fading back in within a few frames).
            Kit.play(lens, base, nil, frames: 6, start: 40)
            Kit.play(lens, base, scene, frames: 5, start: 46)
            let quick = h.bitmap(lens.render(Kit.frame(base, face: scene.face(), time: 2)))
            XCTAssertGreaterThan(quick.change(from: plain, in: zone.rect(scene.face())), 100, "\(kind): a flicker doesn't undress you")
            // Gone for two seconds: it arrives afresh.
            Kit.play(lens, base, nil, frames: 60, start: 50)
            let after = h.bitmap(lens.render(Kit.frame(base, face: scene.face(), time: 4)))
            XCTAssertLessThan(after.change(from: plain, in: zone.rect(scene.face())), 15, "\(kind): back after a while, it drops in again")
        }
    }

    func testRestartingStartsTheEntranceAgain() {
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let base = h.input(scene)
        let plain = h.bitmap(base.composed)
        let lens = DressUpLens(kind: .wizard)
        Kit.play(lens, base, scene, frames: 40)
        lens.restart()
        let zone = Kit.zones[.wizard]![0].rect(scene.face())
        XCTAssertLessThan(h.bitmap(lens.render(Kit.frame(base, face: scene.face(), time: 0))).change(from: plain, in: zone), 15)
    }

    func testTheCostumesAreRepeatable() {
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let base = h.input(scene)
        var shaken = scene; shaken.mouthOpen = 0.7
        for kind in HeadwearKind.allCases {
            let a = DressUpLens(kind: kind), b = DressUpLens(kind: kind)
            Kit.play(a, base, scene, frames: 70)
            Kit.play(b, base, scene, frames: 70)
            let x = h.bitmap(Kit.play(a, base, shaken, frames: 20, start: 70)), y = h.bitmap(Kit.play(b, base, shaken, frames: 20, start: 70))
            XCTAssertTrue(x.bytes == y.bytes, "\(kind): the same faces give the same picture")
        }
    }

    func testOddInputsDoNotUpsetAnything() {
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let base = h.input(scene)
        var squeezed = scene.face()
        squeezed.rightEye = squeezed.leftEye            // the eyes on top of each other
        var huge = SyntheticScene(center: CGPoint(x: 640, y: 380)); huge.scale = 6
        var tiny = SyntheticScene(center: CGPoint(x: 100, y: 60)); tiny.scale = 0.05
        for kind in HeadwearKind.allCases {
            let lens = DressUpLens(kind: kind)
            for (i, dt) in [0.0, 1.0 / 30, 5.0, 1000.0, 1.0 / 240].enumerated() {
                XCTAssertEqual(lens.render(Kit.frame(base, face: scene.face(), time: Double(i), dt: dt)).extent, base.rect, "\(kind) dt \(dt)")
            }
            XCTAssertEqual(lens.render(Kit.frame(base, face: squeezed, time: 6)).extent, base.rect, "\(kind) with the eyes together")
            XCTAssertEqual(lens.render(Kit.frame(base, face: huge.face(), time: 7)).extent, base.rect, "\(kind) enormous")
            XCTAssertEqual(lens.render(Kit.frame(base, face: tiny.face(), time: 8)).extent, base.rect, "\(kind) tiny")
            XCTAssertEqual(lens.render(Kit.frame(base, face: scene.face(), time: 9, matte: false)).extent, base.rect, "\(kind) with no cutout")
        }
    }

    func testNoMatteStillGivesAPictureWithTheWingsInFront() {
        let scene = SyntheticScene(center: CGPoint(x: 640, y: 380))
        let base = h.input(scene)
        let plain = h.bitmap(base.composed)
        let out = Kit.play(DressUpLens(kind: .angel), base, scene, frames: 45, matte: false)
        let bits = h.bitmap(out)
        XCTAssertGreaterThan(bits.change(from: plain, in: Kit.zones[.angel]![0].rect(scene.face())), 100, "the halo")
        XCTAssertGreaterThan(bits.change(from: plain, in: Kit.Zone(1.6, -1.2, 3.0, 0.0).rect(scene.face())), 100, "wings, drawn over the picture")
    }

    func testBigAndSmallFacesGetBigAndSmallCostumes() {
        for kind in HeadwearKind.allCases {
            var extents: [Double] = []
            for scale in [0.5, 1.0] {
                var scene = SyntheticScene(center: CGPoint(x: 640, y: 330)); scene.scale = scale
                let base = h.input(scene)
                let plain = h.bitmap(base.composed)
                let bits = h.bitmap(Kit.play(DressUpLens(kind: kind), base, scene, frames: 60))
                Output.save(Kit.play(DressUpLens(kind: kind), base, scene, frames: 60), as: "headwear-\(kind.rawValue)-scale\(Int(scale * 100)).png")
                // How wide the changed pixels run across the top of the head, in eye-spacings.
                let face = scene.face()
                var lo = Double.infinity, hi = -Double.infinity
                for y in stride(from: Int(face.eyeCenter.y + 1.2 * face.interocular), to: Int(face.eyeCenter.y + 1.5 * face.interocular), by: 2) {
                    for x in 0..<1280 where abs(bits.pixel(x, y).r - plain.pixel(x, y).r) + abs(bits.pixel(x, y).g - plain.pixel(x, y).g) > 40 {
                        lo = min(lo, Double(x)); hi = max(hi, Double(x))
                    }
                }
                extents.append(hi > lo ? (hi - lo) / face.interocular : 0)
            }
            // Whatever it is that crosses the top of the head is as wide, in eye-spacings, however far away you are.
            if extents[1] > 0 {
                XCTAssertEqual(extents[0], extents[1], accuracy: 0.35, "\(kind): the same shape near and far (\(extents))")
            }
        }
    }

    func testCatalogHasTheCostumes() {
        let ids = HeadwearFaces.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertGreaterThanOrEqual(ids.count, 10)
        XCTAssertEqual(ids.count, 28)
        for id in ["dress-dog", "dress-bunny", "dress-devil", "dress-angel", "dress-pirate", "dress-wizard", "dress-santa", "dress-gentleman",
                   "dress-clown", "dress-flower-crown", "dress-cat", "dress-shades", "dress-crown", "dress-party-hat", "dress-headphones",
                   "dress-cowboy", "dress-viking", "dress-propeller", "dress-astronaut", "dress-chef", "dress-fox", "dress-panda", "dress-tabby",
                   "dress-unicorn", "dress-mermaid", "dress-robot", "dress-reindeer", "dress-witch"] {
            XCTAssertNotNil(LensCatalog.info(for: id), id)
        }
        for info in HeadwearFaces.all {
            XCTAssertEqual(info.category, .faces)
            XCTAssertTrue(info.needsFace)
            XCTAssertFalse(info.needsHands)
            let lens = info.make()
            XCTAssertTrue(lens.needs.contains(.face), info.name)
            XCTAssertFalse(lens.needs.contains(.hands), info.name)
            XCTAssertTrue(lens is DressUpLens)
            XCTAssertFalse(info.blurb.isEmpty)
        }
        for kind in HeadwearKind.allCases {
            XCTAssertEqual(DressUpLens(kind: kind).needs.contains(.matte), kind == .angel, "only wings go behind you, so only the angel asks for the cutout")
        }
    }

    /// A lens that does nothing, to show what a frame costs without a costume.
    private final class BareLens: Lens {
        let needs: LensNeeds = [.face]
        func render(_ input: LensInput) -> CIImage { input.composed }
    }

    func testEveryCostumeFitsInTheFrameBudget() {
        var surprised = SyntheticScene(center: CGPoint(x: 640, y: 380))
        surprised.mouthOpen = 0.9; surprised.browRaise = 1; surprised.smile = 1
        let base = h.input(surprised)
        // Best of three, so another process hogging the machine for a moment doesn't count against a costume. The tests run
        // unoptimised, which overstates the cost of the drawing code, so this is a loose check; the real number is smaller.
        func cost(_ lens: Lens) -> Double {
            Kit.play(lens, base, surprised, frames: 40)
            return (0..<3).map { _ in h.cost(of: lens, base: base, frames: 30).mean }.min() ?? 0
        }
        let bare = cost(BareLens())
        for kind in HeadwearKind.allCases {
            let extra = cost(DressUpLens(kind: kind)) - bare
            XCTAssertLessThan(extra, 9, "\(kind) adds \(extra) ms a frame")
        }
    }
}

// MARK: - Reactions

final class HeadwearReactionTests: XCTestCase {
    private let h = LensHarness()
    private typealias Kit = HeadwearTestKit

    private let still = SyntheticScene(center: CGPoint(x: 640, y: 380))
    private lazy var base = h.input(still)
    private lazy var plain = h.bitmap(base.composed)

    private func scene(open: Double = 0, brows: Double = 0, smile: Double = 0, blink: Double = 0, roll: Double = 0) -> SyntheticScene {
        var s = still
        s.mouthOpen = open; s.browRaise = brows; s.smile = smile; s.blink = blink; s.roll = roll
        return s
    }

    /// The highest row, in a band of columns, where the picture differs from the plain one.
    private func topRow(_ bits: Bitmap, x: ClosedRange<Int>, y: ClosedRange<Int>) -> Int? {
        for row in y.reversed() {
            for col in x where abs(bits.pixel(col, row).r - plain.pixel(col, row).r) + abs(bits.pixel(col, row).g - plain.pixel(col, row).g) + abs(bits.pixel(col, row).b - plain.pixel(col, row).b) > 40 { return row }
        }
        return nil
    }

    private func bottomRow(_ bits: Bitmap, x: ClosedRange<Int>, y: ClosedRange<Int>) -> Int? {
        for row in y {
            for col in x where abs(bits.pixel(col, row).r - plain.pixel(col, row).r) + abs(bits.pixel(col, row).g - plain.pixel(col, row).g) + abs(bits.pixel(col, row).b - plain.pixel(col, row).b) > 40 { return row }
        }
        return nil
    }

    // MARK: Dog

    func testTheDogsTongueRollsOutWhenYouOpenWideAndStaysOutThroughAWobble() throws {
        let lens = DressUpLens(kind: .dog)
        let dog = try XCTUnwrap(lens.costume as? HeadwearDog)
        Kit.play(lens, base, scene(), frames: 30)
        XCTAssertEqual(dog.tongueOut, 0, accuracy: 0.02)

        let open = scene(open: 0.9)
        let out = Kit.play(lens, base, open, frames: 12, start: 30)
        Output.save(out, as: "headwear-dog-mouth.png")
        XCTAssertGreaterThan(dog.tongueOut, 0.3, "it is on its way")
        Kit.play(lens, base, open, frames: 14, start: 42)
        XCTAssertEqual(dog.tongueOut, 1, accuracy: 0.2, "and settles hanging out")
        // Below the lower lip, a little to one side of the groove down the middle of the tongue.
        let below = Kit.Spot(face: open.face()).point(0.08, -1.5)
        let bits = h.bitmap(lens.render(Kit.frame(base, face: open.face(), time: 3)))
        XCTAssertTrue(Kit.isPink(bits.pixel(Int(below.x), Int(below.y))), "pink tongue under the mouth, got \(bits.pixel(Int(below.x), Int(below.y)))")

        // Wobbling to a 30% mouth doesn't pull it in; shutting it does.
        Kit.play(lens, base, scene(open: 0.3), frames: 20, start: 60)
        XCTAssertGreaterThan(dog.tongueOut, 0.8)
        Kit.play(lens, base, scene(open: 0.1), frames: 25, start: 80)
        XCTAssertLessThan(dog.tongueOut, 0.1)

        // From a shut mouth, 30% is not enough to start.
        let calm = DressUpLens(kind: .dog)
        let calmDog = try XCTUnwrap(calm.costume as? HeadwearDog)
        Kit.play(calm, base, scene(open: 0.3), frames: 30)
        XCTAssertEqual(calmDog.tongueOut, 0, accuracy: 0.02)
    }

    func testTheDogsEarsPrickUpOnABrowRaiseAndNeedAFirmRaiseToStart() throws {
        let lens = DressUpLens(kind: .dog)
        let dog = try XCTUnwrap(lens.costume as? HeadwearDog)
        let face = scene().face()
        let aloft = Kit.Zone(1.3, 1.1, 2.0, 1.6).rect(face)
        let flat = h.bitmap(Kit.play(lens, base, scene(), frames: 30))
        XCTAssertLessThan(dog.perk, 0.02)
        XCTAssertLessThan(flat.change(from: plain, in: aloft), 15, "floppy ears hang, nothing up there")

        Kit.play(lens, base, scene(brows: 0.4), frames: 20, start: 30)
        XCTAssertLessThan(dog.perk, 0.02, "a slight raise is not enough")
        let up = Kit.play(lens, base, scene(brows: 1), frames: 25, start: 50)
        Output.save(up, as: "headwear-dog-brows.png")
        XCTAssertGreaterThan(dog.perk, 0.9)
        XCTAssertGreaterThan(h.bitmap(up).change(from: plain, in: aloft), 100, "ears up")
        Kit.play(lens, base, scene(brows: 0.4), frames: 25, start: 75)
        XCTAssertGreaterThan(dog.perk, 0.9, "once up, a half raise keeps them there")
        Kit.play(lens, base, scene(brows: 0.1), frames: 30, start: 100)
        XCTAssertLessThan(dog.perk, 0.05, "and relaxing lets them drop")
    }

    // MARK: Bunny

    func testTheBunnysEarsStandTallOnABrowRaiseAndFlopNowAndThen() throws {
        let lens = DressUpLens(kind: .bunny)
        let bunny = try XCTUnwrap(lens.costume as? HeadwearBunny)
        let band = 590...690
        let lazy = h.bitmap(Kit.play(lens, base, scene(), frames: 30))
        let lazyTop = try XCTUnwrap(topRow(lazy, x: band, y: 400...719))
        let upright = h.bitmap(Kit.play(lens, base, scene(brows: 1), frames: 30, start: 30))
        Output.save(Kit.play(lens, base, scene(brows: 1), frames: 1, start: 60), as: "headwear-bunny-brows.png")
        let tallTop = try XCTUnwrap(topRow(upright, x: band, y: 400...719))
        XCTAssertLessThan(bunny.floppiness.max() ?? 1, 0.06, "brows up, ears straight")
        XCTAssertGreaterThan(tallTop, lazyTop + 6, "taller than when slumped")

        // Left alone they droop and, now and then, flop right over.
        let lone = DressUpLens(kind: .bunny)
        let loneBunny = try XCTUnwrap(lone.costume as? HeadwearBunny)
        var worst = 0.0
        for i in 0..<(30 * 16) {
            _ = lone.render(Kit.frame(base, face: still.face(), time: Double(i) / 30))
            worst = max(worst, loneBunny.floppiness.max() ?? 0)
        }
        XCTAssertGreaterThan(worst, 0.6, "an ear flops over at some point in sixteen seconds")
    }

    func testTheBunnysEarsSwingWhenYouShakeYourHead() {
        let lens = DressUpLens(kind: .bunny)
        for i in 0..<30 { _ = lens.render(Kit.frame(base, face: still.face(), time: Double(i) / 30)) }
        let rest = h.bitmap(lens.render(Kit.frame(base, face: still.face(), time: 1)))
        // Shake side to side, then compare a frame mid-shake with how the same head looked still, relative to the moving head.
        var worst = 0
        for i in 0..<40 {
            var s = still; s.center.x = 640 + 90 * sin(Double(i) / 30 * 9)
            let out = h.bitmap(lens.render(Kit.frame(base, face: s.face(), time: 1 + Double(i) / 30)))
            let shift = s.face().eyeCenter.x - still.face().eyeCenter.x
            // Undo the head's own move by comparing just the ear tips' offset from the head centre.
            let a = topRow(out, x: Int(590 + shift)...Int(690 + shift), y: 400...719) ?? 0
            let b = topRow(rest, x: 590...690, y: 400...719) ?? 0
            worst = max(worst, abs(a - b))
        }
        XCTAssertGreaterThan(worst, 5, "the ears wag about as the head moves")
    }

    // MARK: Devil

    func testTheDevilsHornsBlazeWhenYouSmileWithoutFlickering() throws {
        let lens = DressUpLens(kind: .devil)
        let devil = try XCTUnwrap(lens.costume as? HeadwearDevil)
        let zone = Kit.Zone(0.45, 1.0, 0.85, 1.7).rect(still.face())
        let calm = Kit.play(lens, base, scene(), frames: 40)
        let calmLight = h.average(calm, zone)
        XCTAssertEqual(devil.hornGlow, 0.3, accuracy: 0.02)
        Kit.play(lens, base, scene(smile: 0.3), frames: 30, start: 40)
        XCTAssertEqual(devil.hornGlow, 0.3, accuracy: 0.02, "a slight smile is not enough")
        let grin = Kit.play(lens, base, scene(smile: 1), frames: 40, start: 70)
        Output.save(grin, as: "headwear-devil-smile.png")
        XCTAssertGreaterThan(devil.hornGlow, 0.95)
        let grinLight = h.average(grin, zone)
        XCTAssertGreaterThan(grinLight.r + grinLight.g + grinLight.b, calmLight.r + calmLight.g + calmLight.b + 0.12, "the horns are brighter")
        Kit.play(lens, base, scene(smile: 0.3), frames: 40, start: 110)
        XCTAssertGreaterThan(devil.hornGlow, 0.95, "a half smile keeps them lit")
        Kit.play(lens, base, scene(smile: 0), frames: 60, start: 150)
        XCTAssertLessThan(devil.hornGlow, 0.35)
    }

    // MARK: Angel

    func testTheAngelsWingsGoBehindYouAndNeedRoom() {
        let lens = DressUpLens(kind: .angel)
        XCTAssertTrue(lens.needs.contains(.matte))
        let face = still.face()
        let out = h.bitmap(Kit.play(lens, base, still, frames: 50))
        XCTAssertGreaterThan(out.change(from: plain, in: Kit.Zone(1.6, -1.2, 3.0, 0.0).rect(face)), 100, "a wing on the right")
        XCTAssertGreaterThan(out.change(from: plain, in: Kit.Zone(-3.0, -1.2, -1.6, 0.0).rect(face)), 100, "and one on the left")
        XCTAssertLessThan(out.change(from: plain, in: Kit.Zone(-0.5, -1.2, 0.5, 0.3).rect(face)), 8, "but nothing across your face")

        // Squeezed up against the side of the picture there is no room: they shrink away.
        let edge = SyntheticScene(center: CGPoint(x: 60, y: 380))
        let squashed = h.bitmap(Kit.play(DressUpLens(kind: .angel), base, edge, frames: 50))
        func feathers(_ bits: Bitmap, _ rect: CGRect) -> Int {
            var n = 0
            for x in Int(rect.minX)...Int(rect.maxX) { for y in Int(rect.minY)...Int(rect.maxY) where Kit.isWhite(bits.pixel(x, y)) { n += 1 } }
            return n
        }
        XCTAssertGreaterThan(feathers(out, Kit.Zone(1.6, -1.2, 3.0, 0.0).rect(face)), 200, "white feathers when there is room")
        XCTAssertEqual(feathers(squashed, Kit.Zone(1.6, -1.2, 3.0, 0.0).rect(edge.face())), 0, "no wings with no room")
        XCTAssertGreaterThan(squashed.change(from: plain, in: Kit.Zone(-0.7, 1.7, 0.7, 2.1).rect(edge.face())), 100, "though the halo stays")
        XCTAssertEqual(HeadwearAngel.room(HeadwearFrame(face: still.face(), signals: HeadwearSignals(), motion: HeadwearMotion(), clock: 0, seen: 1, dt: 0.03,
                                                         bounds: CGRect(x: 0, y: 0, width: 1280, height: 720))), 1, accuracy: 0.001)
    }

    func testTheAngelsWingsFlutterWhenYouSmile() throws {
        let lens = DressUpLens(kind: .angel)
        let angel = try XCTUnwrap(lens.costume as? HeadwearAngel)
        Kit.play(lens, base, scene(), frames: 30)
        XCTAssertLessThan(angel.flapping, 0.05)
        Kit.play(lens, base, scene(smile: 1), frames: 40, start: 30)
        XCTAssertGreaterThan(angel.flapping, 0.9)
    }

    // MARK: Pirate

    func testThePiratesPatchCoversOneEyeAndLeavesTheOtherAlone() {
        let lens = DressUpLens(kind: .pirate)
        let face = still.face()
        let out = h.bitmap(Kit.play(lens, base, still, frames: 45))
        let left = out.pixel(Int(face.leftEye.x), Int(face.leftEye.y)), right = out.pixel(Int(face.rightEye.x), Int(face.rightEye.y))
        XCTAssertLessThan(left.r + left.g + left.b, 150, "the patch is dark over the left eye")
        let rightPlain = plain.pixel(Int(face.rightEye.x), Int(face.rightEye.y))
        XCTAssertEqual(right.r, rightPlain.r, accuracy: 4, "the right eye is clear")
        // A gold ring at the ear.
        let ear = Kit.Zone(1.0, -0.75, 1.35, -0.4).rect(face)
        var gold = 0
        for x in Int(ear.minX)...Int(ear.maxX) { for y in Int(ear.minY)...Int(ear.maxY) where Kit.isGold(out.pixel(x, y)) { gold += 1 } }
        XCTAssertGreaterThan(gold, 8, "a gold hoop")
    }

    func testThePiratesEarringSwingsWithYourHead() {
        let lens = DressUpLens(kind: .pirate)
        for i in 0..<40 { _ = lens.render(Kit.frame(base, face: still.face(), time: Double(i) / 30)) }
        let zone = Kit.Zone(0.9, -0.95, 1.6, -0.25).rect(still.face())
        let rest = h.bitmap(lens.render(Kit.frame(base, face: still.face(), time: 2)))
        var worst = 0
        for i in 0..<30 {
            // The head slides about, and the zone slides with it, so what changes inside it is the earring's own swing.
            var s = still; s.center.x = 640 + 70 * sin(Double(i) / 30 * 10)
            let out = h.bitmap(lens.render(Kit.frame(base, face: s.face(), time: 2 + Double(i) / 30)))
            let slide = Int(s.center.x - 640)
            var diff = 0
            for x in 0..<Int(zone.width) { for y in 0..<Int(zone.height) {
                let a = out.pixel(Int(zone.minX) + slide + x, Int(zone.minY) + y), b = rest.pixel(Int(zone.minX) + x, Int(zone.minY) + y)
                diff += abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
            } }
            worst = max(worst, diff)
        }
        XCTAssertGreaterThan(worst, 400, "the hoop swings")
    }

    // MARK: Wizard

    func testTheWizardsBeardGrowsWithYourFaceAndReachesBelowTheChin() throws {
        var lengths: [Double] = []
        for scale in [0.5, 1.0] {
            var s = SyntheticScene(center: CGPoint(x: 640, y: 380)); s.scale = scale
            let frame = h.input(s)
            let plainBits = h.bitmap(frame.composed)
            let bits = h.bitmap(Kit.play(DressUpLens(kind: .wizard), frame, s, frames: 60))
            let face = s.face()
            let cx = Int(face.eyeCenter.x)
            var bottom: Int?
            outer: for row in 0..<Int(face.eyeCenter.y) {
                for col in (cx - 6)...(cx + 6) {
                    let a = bits.pixel(col, row), b = plainBits.pixel(col, row)
                    if abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) > 40 { bottom = row; break outer }
                }
            }
            let end = try XCTUnwrap(bottom, "a beard at scale \(scale)")
            lengths.append((face.eyeCenter.y - Double(end)) / face.interocular)
            XCTAssertGreaterThan(Double(end), -1)
            // It hangs well below where the chin is.
            let chin = face.mouth.y - 0.72 * face.interocular
            XCTAssertLessThan(Double(end), chin - 1.5 * face.interocular, "scale \(scale): it reaches below the chin")
        }
        XCTAssertEqual(lengths[0], lengths[1], accuracy: 0.3, "the same length in eye-spacings, so twice as long in pixels at twice the size")
    }

    func testTheWizardsBeardSwaysWhenYouShakeAndSettlesWhenYouStop() throws {
        let lens = DressUpLens(kind: .wizard)
        let wizard = try XCTUnwrap(lens.costume as? HeadwearWizard)
        Kit.play(lens, base, still, frames: 30)
        XCTAssertEqual(wizard.beardSway, 0, accuracy: 0.01)
        var biggest = 0.0
        for i in 0..<45 {
            var s = still; s.center.x = 640 + 110 * sin(Double(i) / 30 * 7)
            _ = lens.render(Kit.frame(base, face: s.face(), time: 1 + Double(i) / 30))
            biggest = max(biggest, abs(wizard.beardSway))
        }
        XCTAssertGreaterThan(biggest, 0.08, "the beard swings")
        XCTAssertLessThan(biggest, 0.8, "but not past its limit")
        Kit.play(lens, base, still, frames: 240, start: 80)
        XCTAssertEqual(wizard.beardSway, 0, accuracy: 0.02, "and hangs straight again")
    }

    func testTheWizardsBeardHangsDownThePictureWhenYouTiltYourHead() throws {
        let lens = DressUpLens(kind: .wizard)
        let wizard = try XCTUnwrap(lens.costume as? HeadwearWizard)
        Kit.play(lens, base, scene(roll: 0.5), frames: 90)
        XCTAssertLessThan(wizard.beardSway, -0.3, "tilted counter-clockwise, the tip hangs toward the left of the face, i.e. straight down the picture")
    }

    // MARK: Santa

    func testSantasBobbleSwingsAndTheBeardIsWhite() throws {
        let lens = DressUpLens(kind: .santa)
        let santa = try XCTUnwrap(lens.costume as? HeadwearSanta)
        let out = h.bitmap(Kit.play(lens, base, still, frames: 50))
        let face = still.face()
        let chin = Kit.Spot(face: face).point(0, -1.9)
        XCTAssertTrue(Kit.isWhite(out.pixel(Int(chin.x), Int(chin.y))) || out.pixel(Int(chin.x), Int(chin.y)).b > 225, "a white beard under the chin")
        XCTAssertEqual(santa.bobbleSwing, 0, accuracy: 0.02)
        var biggest = 0.0
        for i in 0..<40 {
            var s = still; s.center.x = 640 + 110 * sin(Double(i) / 30 * 6)
            _ = lens.render(Kit.frame(base, face: s.face(), time: 2 + Double(i) / 30))
            biggest = max(biggest, abs(santa.bobbleSwing))
        }
        XCTAssertGreaterThan(biggest, 0.05, "the bobble swings")
    }

    // MARK: Gentleman

    func testTheGentlemansMoustacheTwitchesWhenASmileStartsAndOnlyThen() throws {
        let lens = DressUpLens(kind: .gentleman)
        let gentleman = try XCTUnwrap(lens.costume as? HeadwearGentleman)
        Kit.play(lens, base, scene(), frames: 40)
        XCTAssertEqual(gentleman.twitch, 0, accuracy: 0.01)
        var biggest = 0.0
        for i in 0..<14 {
            _ = lens.render(Kit.frame(base, face: scene(smile: 1).face(), time: 2 + Double(i) / 30))
            biggest = max(biggest, abs(gentleman.twitch))
        }
        XCTAssertGreaterThan(biggest, 0.15, "it twitches as the smile starts")
        Kit.play(lens, base, scene(smile: 1), frames: 90, start: 80)
        XCTAssertEqual(gentleman.twitch, 0, accuracy: 0.02, "and settles")
        var later = 0.0
        for i in 0..<30 {
            _ = lens.render(Kit.frame(base, face: scene(smile: 1).face(), time: 6 + Double(i) / 30))
            later = max(later, abs(gentleman.twitch))
        }
        XCTAssertLessThan(later, 0.02, "a held smile doesn't keep twitching")
        // A smile that hovers around the threshold twitches once, not on every flicker.
        Kit.play(lens, base, scene(smile: 0.3), frames: 30, start: 200)
        var flicker = 0.0
        for i in 0..<30 {
            _ = lens.render(Kit.frame(base, face: scene(smile: i % 2 == 0 ? 0.5 : 0.3).face(), time: 8 + Double(i) / 30))
            flicker = max(flicker, abs(gentleman.twitch))
        }
        XCTAssertLessThan(flicker, 0.2, "wobbling between 30% and 50% is not a new smile every time")
    }

    func testTheMonocleGlintsNowAndThenAndSitsOverOneEye() {
        var seen = 0, total = 0
        for i in 0..<(30 * 20) {
            total += 1
            if HeadwearGentleman.glint(at: Double(i) / 30) != nil { seen += 1 }
        }
        XCTAssertGreaterThan(seen, 0)
        XCTAssertLessThan(Double(seen) / Double(total), 0.3, "a glint, not a constant shine")
        let out = h.bitmap(Kit.play(DressUpLens(kind: .gentleman), base, still, frames: 50))
        let ring = Kit.Zone(0.15, -0.4, 0.85, 0.4).rect(still.face())
        var gold = 0
        for x in Int(ring.minX)...Int(ring.maxX) { for y in Int(ring.minY)...Int(ring.maxY) where Kit.isGold(out.pixel(x, y)) { gold += 1 } }
        XCTAssertGreaterThan(gold, 60, "a gold rim round the right eye")
        let leftRing = Kit.Zone(-0.85, -0.4, -0.15, 0.4).rect(still.face())
        var leftGold = 0
        for x in Int(leftRing.minX)...Int(leftRing.maxX) { for y in Int(leftRing.minY)...Int(leftRing.maxY) where Kit.isGold(out.pixel(x, y)) { leftGold += 1 } }
        XCTAssertEqual(leftGold, 0, "and not the left")
    }

    // MARK: Clown

    func testTheClownsNoseSqueaksOncePerBlink() throws {
        let lens = DressUpLens(kind: .clown)
        let clown = try XCTUnwrap(lens.costume as? HeadwearClown)
        Kit.play(lens, base, scene(), frames: 40)
        XCTAssertEqual(clown.squeaks, 0)
        let nose = still.face().nose
        let restOut = h.bitmap(lens.render(Kit.frame(base, face: scene().face(), time: 2)))
        XCTAssertTrue(Kit.isRed(restOut.pixel(Int(nose.x), Int(nose.y))), "a red nose, got \(restOut.pixel(Int(nose.x), Int(nose.y)))")
        func redWidth(_ bits: Bitmap) -> Int {
            var n = 0
            for x in Int(nose.x) - 60...Int(nose.x) + 60 where Kit.isRed(bits.pixel(x, Int(nose.y))) { n += 1 }
            return n
        }
        let restWidth = redWidth(restOut)

        Kit.play(lens, base, scene(blink: 0.4), frames: 10, start: 40)
        XCTAssertEqual(clown.squeaks, 0, "a half-closed eye is not a blink")

        let squeak = lens.render(Kit.frame(base, face: scene(blink: 1).face(), time: 3))
        Output.save(squeak, as: "headwear-clown-blink.png")
        XCTAssertEqual(clown.squeaks, 1)
        XCTAssertGreaterThan(clown.squashed, 0.5)
        XCTAssertGreaterThan(Double(redWidth(h.bitmap(squeak))), Double(restWidth) * 1.1, "the nose squashes wider")
        Kit.play(lens, base, scene(blink: 1), frames: 30, start: 100)
        XCTAssertEqual(clown.squeaks, 1, "holding the eyes shut is still one blink")
        XCTAssertLessThan(clown.squashed, 0.05, "and the nose has sprung back")

        Kit.play(lens, base, scene(blink: 0), frames: 12, start: 140)
        Kit.play(lens, base, scene(blink: 1), frames: 3, start: 160)
        XCTAssertEqual(clown.squeaks, 2, "a second blink, a second squeak")
        // Hovering around the limit doesn't count again.
        Kit.play(lens, base, scene(blink: 0.6), frames: 10, start: 170)
        Kit.play(lens, base, scene(blink: 0.4), frames: 4, start: 180)
        Kit.play(lens, base, scene(blink: 0.6), frames: 10, start: 190)
        XCTAssertEqual(clown.squeaks, 2)
    }

    // MARK: Flowers

    func testPetalsDriftOffTheCrownFromTimeToTime() throws {
        let lens = DressUpLens(kind: .flowers)
        let crown = try XCTUnwrap(lens.costume as? HeadwearFlowerCrown)
        Kit.play(lens, base, still, frames: 30)
        XCTAssertEqual(crown.petalCount, 0, "none while the flowers are still opening")
        var tracked: CGFloat?
        var fell = false
        var most = 0
        for i in 30..<(30 * 15) {
            _ = lens.render(Kit.frame(base, face: still.face(), time: Double(i) / 30))
            most = max(most, crown.petalCount)
            if tracked == nil, let first = crown.petalPositions.first { tracked = first.y }
            else if let before = tracked, let first = crown.petalPositions.first, !fell {
                if i % 8 == 0 { fell = first.y < before - 3 }
            }
        }
        XCTAssertGreaterThan(most, 0, "a petal comes away")
        XCTAssertLessThanOrEqual(most, 14)
        XCTAssertTrue(fell, "and falls")
        Output.save(Kit.play(lens, base, still, frames: 120, start: 450), as: "headwear-flowers-petals.png")
        lens.restart()
        XCTAssertEqual(crown.petalCount, 0)
    }
}

// MARK: - Pieces

final class HeadwearKitTests: XCTestCase {
    func testAGateNeedsMoreToSwitchOnThanToStayOn() {
        var gate = HeadwearGate(on: 0.5, off: 0.3)
        var states: [Bool] = []
        for v in [0.4, 0.6, 0.4, 0.35, 0.2, 0.4, 0.6] { gate.update(v); states.append(gate.isOn) }
        XCTAssertEqual(states, [false, true, true, true, false, false, true])
        gate.update(0.2)
        gate.update(0.9)
        XCTAssertTrue(gate.rose, "the edge is reported once")
        gate.update(0.95)
        XCTAssertFalse(gate.rose)
    }

    func testSignalsEaseInQuicklyAndOutSlowly() {
        var signals = HeadwearSignals()
        var face = SyntheticScene().face()
        face.mouthOpen = 1
        for _ in 0..<3 { signals.update(face, dt: 1.0 / 30) }
        let rising = signals.open
        XCTAssertGreaterThan(rising, 0.5)
        face.mouthOpen = 0
        for _ in 0..<3 { signals.update(face, dt: 1.0 / 30) }
        XCTAssertGreaterThan(signals.open, 0.1, "it lets go more slowly than it took hold")
        for _ in 0..<60 { signals.update(face, dt: 1.0 / 30) }
        XCTAssertLessThan(signals.open, 0.01)
    }

    func testASwingLeansAwayFromAPushAndSettlesBack() {
        var swing = HeadwearSwing(omega: 7, damping: 0.2, gain: 0.04, limit: 1)
        for _ in 0..<30 { swing.step(dt: 1.0 / 30, accel: 10) }
        XCTAssertLessThan(swing.x, -0.2, "pushed right, it lags to the left")
        for _ in 0..<150 { swing.step(dt: 1.0 / 30, accel: 0) }
        XCTAssertEqual(swing.x, 0, accuracy: 0.01)
        swing.step(dt: 1000, accel: 1e6)
        XCTAssertLessThanOrEqual(abs(swing.x), 1.0001, "a silly push can't throw it past its limit")
        XCTAssertFalse(swing.x.isNaN)
        var hanging = HeadwearSwing(omega: 6, damping: 0.3, gain: 0.04, limit: 1)
        for _ in 0..<150 { hanging.step(dt: 1.0 / 30, accel: 0, rest: 0.5) }
        XCTAssertEqual(hanging.x, 0.5, accuracy: 0.01, "it hangs where gravity leaves it")
    }

    func testMotionIgnoresJitterAndSeesRealShoves() {
        var motion = HeadwearMotion()
        let still = SyntheticScene().face()
        for i in 0..<60 {
            var jitter = still
            let wobble = i % 2 == 0 ? 0.5 : -0.5
            jitter.leftEye.x += wobble; jitter.rightEye.x += wobble
            motion.update(jitter, dt: 1.0 / 30)
        }
        XCTAssertLessThan(simd_length(motion.acceleration), 0.001, "half a pixel of wobble is not a shake")
        var peak = 0.0
        for i in 0..<20 {
            var s = SyntheticScene(); s.center.x = 640 + 100 * sin(Double(i) / 30 * 8)
            motion.update(s.face(), dt: 1.0 / 30)
            peak = max(peak, simd_length(motion.acceleration))
        }
        XCTAssertGreaterThan(peak, 5)
        XCTAssertLessThanOrEqual(peak, 70.001, "capped")
        // A face that jumps clean across the picture doesn't send everything flying.
        var jump = SyntheticScene(); jump.center.x = 1200
        motion.update(jump.face(), dt: 1.0 / 30)
        XCTAssertLessThanOrEqual(simd_length(motion.acceleration), 70.001)
        motion.forget()
        XCTAssertEqual(simd_length(motion.acceleration), 0)
    }

    func testRibbonsAndEasingsBehave() {
        let spine = HeadwearShape.spine(from: hwp(0, 0), length: 2, steps: 10) { _ in .pi / 2 }
        XCTAssertEqual(spine.count, 11)
        XCTAssertEqual(spine.last?.y ?? 0, 2, accuracy: 1e-9)
        XCTAssertEqual(spine.last?.x ?? 1, 0, accuracy: 1e-9)
        let box = HeadwearShape.ribbon(spine) { _ in 0.25 }.boundingBoxOfPath
        XCTAssertEqual(box.width, 0.5, accuracy: 0.08)
        XCTAssertEqual(box.height, 2, accuracy: 0.3)

        XCTAssertEqual(HeadwearEase.drop(0, height: 2.8), 2.8, accuracy: 1e-9)
        XCTAssertEqual(HeadwearEase.drop(5, height: 2.8), 0, accuracy: 1e-9)
        for i in 0...60 { XCTAssertGreaterThanOrEqual(HeadwearEase.drop(Double(i) / 60), 0, "it never sinks into your head") }
        XCTAssertEqual(HeadwearEase.pop(-1), 0, accuracy: 1e-9)
        XCTAssertEqual(HeadwearEase.pop(9), 1, accuracy: 1e-9)
        XCTAssertGreaterThan((0...50).map { HeadwearEase.pop(Double($0) / 50 * 0.5) }.max() ?? 0, 1.02, "a little overshoot")

        for i in 0..<200 {
            let a = HeadwearNoise.unit(i, 3)
            XCTAssertTrue(a >= 0 && a < 1)
            XCTAssertEqual(a, HeadwearNoise.unit(i, 3))
        }
        XCTAssertNotEqual(HeadwearNoise.unit(1, 1), HeadwearNoise.unit(2, 1))
    }

    func testTheRigRestartsTheEntranceOnlyAfterALongAbsence() {
        let rig = HeadwearRig()
        let face = SyntheticScene().face()
        for _ in 0..<30 { _ = rig.update(face, dt: 1.0 / 30) }
        XCTAssertGreaterThan(rig.seen, 0.9)
        for _ in 0..<6 { XCTAssertNil(rig.update(nil, dt: 1.0 / 30)) }
        XCTAssertFalse(rig.hasForgotten)
        XCTAssertGreaterThan(rig.update(face, dt: 1.0 / 30)?.seen ?? 0, 0.9, "a blip is forgiven")
        for _ in 0..<30 { _ = rig.update(nil, dt: 1.0 / 30) }
        XCTAssertTrue(rig.hasForgotten)
        XCTAssertLessThan(rig.update(face, dt: 1.0 / 30)?.seen ?? 9, 0.1, "after a long absence it starts again")
        let clock = rig.clock
        _ = rig.update(face, dt: 50)
        XCTAssertEqual(rig.clock - clock, 0.1, accuracy: 1e-9, "a stall is clamped")
        _ = rig.update(face, dt: -3)
        XCTAssertEqual(rig.clock - clock, 0.1, accuracy: 1e-9, "and time never runs backwards")
    }

    func testTheFaceCostumesCoverEveryAssignedKind() {
        let names = Set(HeadwearKind.allCases.map(\.rawValue))
        for expected in ["dog", "bunny", "devil", "angel", "pirate", "wizard", "santa", "gentleman", "clown", "flowers", "catEars", "shades", "crown",
                         "partyHat", "headphones", "cowboy", "viking", "propeller", "astronaut", "chef", "fox", "panda", "tabby", "unicorn",
                         "mermaid", "robot", "reindeer", "witch"] {
            XCTAssertTrue(names.contains(expected), expected)
        }
        for kind in HeadwearKind.allCases {
            let costume = kind.makeCostume()
            XCTAssertFalse(costume.hint.isEmpty, "\(kind)")
            XCTAssertLessThan(costume.hint.count, 70, "\(kind): short and friendly")
        }
    }
}
