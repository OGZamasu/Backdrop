import CoreImage
import XCTest

/// A workbench for judging looks by eye: renders the looks named in `LOOK_IDS` (comma separated, or `all`) in every fixture
/// state and saves one sheet per look. Does nothing unless both `LOOK_IDS` and `BACKDROP_TEST_OUTPUT` are set, so it costs
/// nothing in an ordinary run.
final class LookFilterStudioTests: XCTestCase {
    private let h = LensHarness()
    private let startOfUptime = 5000.0

    /// Every look this area owns: the ten from round one, the ten new ones and the six older filters.
    static let ownedIds: [String] = LookFilters.all.map(\.id) + ["comic", "pixel-art", "mirror", "kaleidoscope", "glitch", "matrix"]

    func testRenderTheNamedLooksForJudging() throws {
        let env = ProcessInfo.processInfo.environment
        guard let names = env["LOOK_IDS"], env["BACKDROP_TEST_OUTPUT"] != nil else { throw XCTSkip("set LOOK_IDS and BACKDROP_TEST_OUTPUT") }
        let ids = names == "all" ? Self.ownedIds : names.split(separator: ",").map(String.init)
        let offset = Double(env["LOOK_TIME"] ?? "") ?? 3.1
        for id in ids {
            let found = id == "original" ? LensInfo(id: id, name: id, glyph: "📷", blurb: ".", category: .filters, scored: false, needsFace: false) { LookStudioPassThrough() }
                : LensCatalog.info(for: id)
            guard let info = found else { XCTFail("no lens \(id)"); continue }
            var pictures: [CIImage] = []
            for state in LookFixture.State.allCases {
                let lens = info.make()
                let base = LookFixture.input(h, state)
                for i in 0..<8 { _ = lens.render(h.at(base, time: startOfUptime + Double(i) / 30)) }
                let image = lens.render(h.at(base, time: startOfUptime + offset)).cropped(to: LookFixture.rect)
                Output.save(image, as: "studio-\(id)-\(state.rawValue).png")
                if let cg = h.ciContext.createCGImage(image, from: LookFixture.rect) { pictures.append(CIImage(cgImage: cg)) }
            }
            let cartoon = info.make().render(h.at(h.input(), time: startOfUptime + offset)).cropped(to: LookFixture.rect)
            if let cg = h.ciContext.createCGImage(cartoon, from: LookFixture.rect) { pictures.append(CIImage(cgImage: cg)) }
            Output.save(LookFixture.sheet(pictures, columns: 3, scale: 0.5), as: "studio-\(id).png")
        }
    }

    /// The same look at several moments, to judge its motion: `LOOK_IDS` names them, `LOOK_FRAMES` says how many moments (one
    /// every `LOOK_STEP` seconds).
    func testRenderTheNamedLooksOverTime() throws {
        let env = ProcessInfo.processInfo.environment
        guard let names = env["LOOK_IDS"], env["BACKDROP_TEST_OUTPUT"] != nil, let frames = Int(env["LOOK_FRAMES"] ?? "") else {
            throw XCTSkip("set LOOK_IDS, LOOK_FRAMES and BACKDROP_TEST_OUTPUT")
        }
        let step = Double(env["LOOK_STEP"] ?? "") ?? 0.5
        let ids = names == "all" ? Self.ownedIds : names.split(separator: ",").map(String.init)
        for id in ids {
            guard let info = LensCatalog.info(for: id) else { continue }
            let lens = info.make()
            let base = LookFixture.input(h, .backdrop)
            var pictures: [CIImage] = []
            var t = 0.0
            for i in 0..<frames {
                let target = Double(i) * step
                while t < target { _ = lens.render(h.at(base, time: startOfUptime + t)); t += 1.0 / 15 }
                let image = lens.render(h.at(base, time: startOfUptime + target)).cropped(to: LookFixture.rect)
                if let cg = h.ciContext.createCGImage(image, from: LookFixture.rect) { pictures.append(CIImage(cgImage: cg)) }
            }
            Output.save(LookFixture.sheet(pictures, columns: 3, scale: 0.5), as: "motion-\(id).png")
        }
    }
}

/// The fixture as it is, to compare the looks with.
private final class LookStudioPassThrough: Lens {
    let needs: LensNeeds = []
    func render(_ input: LensInput) -> CIImage { input.composed }
}
