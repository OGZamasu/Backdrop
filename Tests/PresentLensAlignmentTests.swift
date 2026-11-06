import CoreImage
import CoreMedia
import XCTest

/// A lens on top of Present has to be told where you are in the picture people see, not where the camera had you.
///
/// Your face and hands are read on the camera picture. When Present moves or shrinks you (a presenter cutout, a floating panel with you
/// off to one side, a camera bubble) they have to move with you, the way your cutout does, or hair, hats and effects land beside your
/// head. These run a pretend face through the real pipeline and check that what a lens is handed lines up with what the picture shows:
/// the pupils the face says are there are where the pupils are painted.
final class PresentLensAlignmentTests: XCTestCase {
    private let context = CIContext()

    private func pixel(_ image: CIImage, _ p: CGPoint) -> RGB { TestSupport.pixel(image, x: Int(p.x.rounded()), y: Int(p.y.rounded()), context: context) }
    private func brightness(_ c: RGB) -> Int { c.r + c.g + c.b }

    /// Hears everything a lens is told, and draws nothing.
    private final class Probe: Lens {
        var needs: LensNeeds { [.face, .hands, .matte] }
        private(set) var face: FaceState?
        private(set) var hands: [HandState] = []
        private(set) var camera: CIImage?
        private(set) var matte: CIImage?
        private(set) var background: CIImage?
        func render(_ input: LensInput) -> CIImage {
            face = input.face
            hands = input.hands
            camera = input.camera
            matte = input.matte
            background = input.background
            return input.composed
        }
    }

    private struct Case {
        var name: String
        var layout: StageLayout
        /// Whether you sit in a bubble rather than as a cutout.
        var bubble = false
    }

    private func cases() -> [Case] {
        var panelWithYouAside = StagePreset.sideBySide.apply(to: StageLayout()); panelWithYouAside.tilt = 0; panelWithYouAside.depth = 0
        var small = StageMemory.starting(.presenter, from: StageLayout())
        small.presenter = StageFrame(center: CGPoint(x: 0.2, y: 0.3), size: 0.45)
        var big = StagePreset.cornerBubble.apply(to: StageLayout()); big.presenter = StageFrame(center: CGPoint(x: 0.5, y: 0.45), size: 0.5)
        var square = StagePreset.cornerBubble.apply(to: StageLayout()); square.presenterStyle = .roundedSquare
        return [
            Case(name: "side by side with the panel", layout: panelWithYouAside),
            Case(name: "presenter cutout", layout: StageMemory.starting(.presenter, from: StageLayout())),
            Case(name: "small cutout low on the left", layout: small),
            Case(name: "corner bubble", layout: StagePreset.cornerBubble.apply(to: StageLayout()), bubble: true),
            Case(name: "big round bubble", layout: big, bubble: true),
            Case(name: "rounded square bubble", layout: square, bubble: true),
        ]
    }

    /// A rig with a probe lens on top, you sitting where `scene` says, and a hand beside your chin.
    private func rig(_ layout: StageLayout) -> (rig: StageRig, probe: Probe, face: FaceState, hand: HandState) {
        let rig = StageRig(layout: layout)
        let face = rig.scene.face()
        let hand = HandFixtures.openPalm(at: CGPoint(x: face.mouth.x + 150, y: face.mouth.y - 60))
        rig.pipeline.faceOverride = { face }
        rig.hands = [hand]
        let probe = Probe()
        rig.pipeline.setLens(probe)
        rig.run(10)
        return (rig, probe, face, hand)
    }

    // MARK: The face itself

    func testAMovedFaceIsMovedAndItsLengthsAreScaled() {
        let face = SyntheticScene(center: CGPoint(x: 900, y: 400), scale: 1, roll: 0.2, mouthOpen: 0.4, browRaise: 0.3, blink: 0.1, smile: 0.5).face()
        let t = CGAffineTransform(translationX: -640, y: -360).concatenating(CGAffineTransform(scaleX: 0.5, y: 0.5)).concatenating(CGAffineTransform(translationX: 300, y: 200))
        let moved = face.transformed(by: t)
        XCTAssertEqual(moved.leftEye.x, face.leftEye.applying(t).x, accuracy: 1e-9)
        XCTAssertEqual(moved.mouth.y, face.mouth.applying(t).y, accuracy: 1e-9)
        XCTAssertEqual(moved.browCenter.x, face.browCenter.applying(t).x, accuracy: 1e-9)
        XCTAssertEqual(moved.interocular, face.interocular * 0.5, accuracy: 1e-9, "half the size")
        XCTAssertEqual(moved.mouthWidth, face.mouthWidth * 0.5, accuracy: 1e-9)
        XCTAssertEqual(moved.rect.width, face.rect.width * 0.5, accuracy: 1e-9)
        XCTAssertEqual(moved.rect.midX, CGPoint(x: face.rect.midX, y: face.rect.midY).applying(t).x, accuracy: 1e-9)
        XCTAssertEqual(moved.roll, face.roll, accuracy: 1e-9, "a head tipped by this much is still tipped by this much")
        // What the face is doing doesn't depend on where it is.
        XCTAssertEqual(moved.mouthOpen, face.mouthOpen)
        XCTAssertEqual(moved.browRaise, face.browRaise)
        XCTAssertEqual(moved.browDistance, face.browDistance)
        XCTAssertEqual(moved.blink, face.blink)
        XCTAssertEqual(moved.smile, face.smile)
    }

    func testMovingAFaceByNothingLeavesItAlone() {
        let face = SyntheticScene(center: CGPoint(x: 900, y: 400), mouthOpen: 0.3).face()
        XCTAssertEqual(face.transformed(by: .identity), face)
    }

    // MARK: Through the pipeline

    func testAPlainBackdropLeavesYourFaceWhereTheCameraSeesIt() {
        let made = rig(StageMemory.starting(.backdrop, from: StageLayout()))
        let face = made.probe.face
        XCTAssertEqual(face?.leftEye.x ?? 0, made.face.leftEye.x, accuracy: 0.01)
        XCTAssertEqual(face?.leftEye.y ?? 0, made.face.leftEye.y, accuracy: 0.01)
    }

    func testALensIsToldWhereYourFaceNowIsInEveryArrangement() throws {
        for c in cases() {
            let made = rig(c.layout)
            let face = try XCTUnwrap(made.probe.face, c.name)
            XCTAssertGreaterThan(hypot(face.leftEye.x - made.face.leftEye.x, face.leftEye.y - made.face.leftEye.y), 60,
                                 "\(c.name): the face moved with you")
            // The pupils it reports are where the pupils are painted in the picture people see.
            for (side, eye) in [("left", face.leftEye), ("right", face.rightEye)] {
                let seen = pixel(made.rig.outputImage, eye)
                XCTAssertLessThan(brightness(seen), 330, "\(c.name): the \(side) pupil is where the face says (\(eye)): \(seen)")
            }
        }
    }

    func testTheFaceIsTheSizeYouNowAre() throws {
        for c in cases() where !c.bubble {
            let made = rig(c.layout)
            let face = try XCTUnwrap(made.probe.face, c.name)
            // The controller may nudge you to keep you in view, so go by the layout the picture was made with.
            let used = made.rig.layouts.last ?? c.layout
            let t = StageGeometry.presenterTransform(used.presenter)
            XCTAssertEqual(face.interocular, made.face.interocular * Double(used.presenter.size), accuracy: 0.01, c.name)
            XCTAssertEqual(face.eyeCenter.x, made.face.eyeCenter.applying(t).x, accuracy: 0.01, c.name)
            XCTAssertEqual(face.eyeCenter.y, made.face.eyeCenter.applying(t).y, accuracy: 0.01, c.name)
        }
    }

    func testTheCameraAndCutoutALensGetsAreWhereTheFaceIs() throws {
        for c in cases() {
            let made = rig(c.layout)
            let face = try XCTUnwrap(made.probe.face, c.name)
            let camera = try XCTUnwrap(made.probe.camera, c.name), matte = try XCTUnwrap(made.probe.matte, c.name)
            let seen = pixel(camera, face.leftEye)
            XCTAssertLessThan(brightness(seen), 330, "\(c.name): the camera a lens reads has your pupil where the face is: \(seen)")
            XCTAssertGreaterThan(pixel(matte, face.eyeCenter).r, 200, "\(c.name): and the cutout covers your face there")
            // Where the camera had you is no longer you.
            XCTAssertLessThan(pixel(matte, made.face.eyeCenter).r, 60, "\(c.name): the cutout is gone from where the camera had you")
        }
    }

    func testYourHandsAndYourFaceAreInTheSameSpace() throws {
        for c in cases() {
            let made = rig(c.layout)
            let face = try XCTUnwrap(made.probe.face, c.name)
            let hand = try XCTUnwrap(made.probe.hands.first, c.name)
            // The hand was held a fixed way from the face; both are moved by the same transform, so that is a scaled copy of it.
            let before = CGVector(dx: made.hand.wrist.x - made.face.eyeCenter.x, dy: made.hand.wrist.y - made.face.eyeCenter.y)
            let after = CGVector(dx: hand.wrist.x - face.eyeCenter.x, dy: hand.wrist.y - face.eyeCenter.y)
            let scale = Double(face.interocular / made.face.interocular)
            XCTAssertEqual(after.dx, before.dx * scale, accuracy: 0.5, "\(c.name)")
            XCTAssertEqual(after.dy, before.dy * scale, accuracy: 0.5, "\(c.name)")
        }
    }

    func testABubbleIsWhereAHatWouldSit() throws {
        for c in cases() where c.bubble {
            let made = rig(c.layout)
            let face = try XCTUnwrap(made.probe.face, c.name)
            let bubble = StageGeometry.bubbleRect(c.layout.presenter)
            XCTAssertTrue(bubble.contains(face.eyeCenter), "\(c.name): your face is inside the bubble: \(face.eyeCenter) in \(bubble)")
            XCTAssertTrue(bubble.contains(face.headTop), "\(c.name): and so is the top of your head")
            let hand = try XCTUnwrap(made.probe.hands.first, c.name)
            XCTAssertTrue(bubble.insetBy(dx: -20, dy: -20).contains(hand.wrist), "\(c.name): a hand held beside your chin is beside it in the bubble: \(hand.wrist)")
        }
    }

    func testTheCutoutALensGetsStopsAtTheEdgeOfABubble() throws {
        let c = try XCTUnwrap(cases().first { $0.name == "corner bubble" })
        let made = rig(c.layout)
        let matte = try XCTUnwrap(made.probe.matte), face = try XCTUnwrap(made.probe.face)
        let bubble = StageGeometry.bubbleRect(c.layout.presenter)
        // Your shoulders reach well past the bubble's edge in the camera; the part outside it is not shown, so it is not in the cutout.
        XCTAssertLessThan(pixel(matte, CGPoint(x: bubble.minX - 30, y: bubble.midY)).r, 40)
        XCTAssertLessThan(pixel(matte, CGPoint(x: bubble.midX, y: bubble.maxY + 30)).r, 40)
        XCTAssertGreaterThan(pixel(matte, face.eyeCenter).r, 200, "while you, inside it, are there")
    }

    func testALensThatLaysYouOverTheBackdropKeepsTheBubble() throws {
        let c = try XCTUnwrap(cases().first { $0.name == "corner bubble" })
        let made = rig(c.layout)
        let background = try XCTUnwrap(made.probe.background), face = try XCTUnwrap(made.probe.face)
        // The picture behind you holds the bubble's room and ring, so a lens that puts you back over it keeps the bubble.
        let bubble = StageGeometry.bubbleRect(c.layout.presenter)
        let ring = pixel(background, CGPoint(x: bubble.midX, y: bubble.maxY - 2))
        XCTAssertGreaterThan(brightness(ring), 600, "the ring is there: \(ring)")
        // And you are in the picture, not in what is behind you: your pupil is painted in one and only a soft blur of it is in the other.
        XCTAssertLessThan(brightness(pixel(made.rig.outputImage, face.leftEye)), 330, "you are in the picture")
        XCTAssertGreaterThan(brightness(pixel(background, face.leftEye)), 400, "but not in what is behind you")
    }
}
