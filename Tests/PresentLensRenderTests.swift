import CoreImage
import XCTest

/// Real lenses over real Present layouts, to look at: BACKDROP_TEST_OUTPUT=<folder>. The checks that these line up are in
/// `PresentLensAlignmentTests`; these are the pictures.
final class PresentLensRenderTests: XCTestCase {
    private func layouts() -> [(String, StageLayout)] {
        var aside = StagePreset.sideBySide.apply(to: StageLayout()); aside.tilt = 0; aside.depth = 0
        var small = StageMemory.starting(.presenter, from: StageLayout())
        small.presenter = StageFrame(center: CGPoint(x: 0.2, y: 0.32), size: 0.5)
        return [("1-side-by-side", aside), ("2-small-cutout", small), ("3-corner-bubble", StagePreset.cornerBubble.apply(to: StageLayout())),
                ("4-plain-backdrop", StageMemory.starting(.backdrop, from: StageLayout()))]
    }

    private func fists() -> [HandState] {
        func fist(_ p: CGPoint, mirrored: Bool, id: Int) -> HandState {
            let probe = HandFixtures.hand(.fist, at: .zero, size: 100, angle: 0, mirrored: mirrored, id: id)
            return HandFixtures.moved(probe, by: CGVector(dx: p.x - probe.palm.x, dy: p.y - probe.palm.y))
        }
        return [fist(CGPoint(x: 470, y: 330), mirrored: true, id: 1), fist(CGPoint(x: 810, y: 330), mirrored: false, id: 2)]
    }

    private func render(_ name: String, layout: StageLayout, lens: Lens, frames: Int, hands: [HandState] = []) -> CIImage {
        let rig = StageRig(layout: layout)
        rig.scene = SyntheticScene()
        let face = rig.scene.face()
        rig.pipeline.faceOverride = { face }
        rig.hands = hands
        rig.pipeline.setLens(lens)
        rig.run(frames)
        return rig.outputImage
    }

    func testRealLensesOverPresentLayouts() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"] == nil, "set TEST_RUNNER_BACKDROP_TEST_OUTPUT to render")
        var crowns: [CIImage] = [], balls: [CIImage] = []
        for (name, layout) in layouts() {
            let crown = render(name, layout: layout, lens: DressUpLens(kind: .crown), frames: 24)
            Output.save(crown, as: "present-lens-crown-\(name).png")
            crowns.append(crown)
            let ball = render(name, layout: layout, lens: SaiyanLens(), frames: 75, hands: fists())
            Output.save(ball, as: "present-lens-dragon-ball-\(name).png")
            balls.append(ball)
        }
        Output.save(SaiyanBench.sheet(crowns + balls, columns: 4, scale: 0.5), as: "present-lens-sheet.png")
    }
}
