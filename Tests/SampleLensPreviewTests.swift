import CoreImage
import CoreImage.CIFilterBuiltins
import XCTest

/// Pictures of every sample lens in the states that matter (at rest, each expression, the moment it switches on, a tilted head,
/// far away, close up, nobody there, and over a light room), for looking at rather than measuring. Runs only when
/// BACKDROP_TEST_OUTPUT is set. BACKDROP_SAMPLE_ONLY (names, comma separated) narrows it down; BACKDROP_SAMPLE_DRAFTS points it
/// at a folder of lens folders instead of the built-in samples, so a lens can be reworked without rebuilding.
final class SampleLensPreviewTests: XCTestCase {
    private let h = LensHarness()

    private static func scene(_ signals: Set<PackSignal>, center: CGPoint = CGPoint(x: 640, y: 390), scale: Double = 1, roll: Double = 0) -> SyntheticScene {
        SyntheticScene(center: center, scale: scale, roll: roll, mouthOpen: signals.contains(.mouthOpen) ? 1 : 0,
                       browRaise: signals.contains(.browRaise) ? 1 : 0, blink: signals.contains(.blink) ? 1 : 0, smile: signals.contains(.smile) ? 1 : 0)
    }

    /// A pale, warm room, to check that a lens still reads on a light backdrop.
    private static func lightRoom() -> CIImage {
        let g = CIFilter.linearGradient()
        g.point0 = CGPoint(x: 0, y: 720); g.point1 = CGPoint(x: 0, y: 0)
        g.color0 = CIColor(red: 0.96, green: 0.94, blue: 0.90); g.color1 = CIColor(red: 0.80, green: 0.78, blue: 0.74)
        return g.outputImage!.cropped(to: CGRect(origin: .zero, size: SyntheticScene.size))
    }

    private func frames(_ lens: PackLens, _ input: LensInput, count: Int, from start: Int = 0) -> CIImage {
        var out = input.composed
        for i in start..<(start + count) { out = lens.render(h.at(input, time: Double(i) / 30)) }
        return out
    }

    private func faceless(_ input: LensInput) -> LensInput {
        LensInput(time: 0, dt: 1.0 / 30, rect: input.rect, camera: input.camera, matte: input.matte, background: input.background,
                  composed: input.composed, matteGrid: input.matteGrid, face: nil, services: input.services)
    }

    /// Milliseconds a frame for each sample with every expression showing at once. Opt in with BACKDROP_PERF (a timing test).
    func testCostOfEverySampleWithEverythingShowing() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["BACKDROP_PERF"] != nil, "a timing test; set TEST_RUNNER_BACKDROP_PERF=1")
        var folder = FileManager.default.temporaryDirectory.appendingPathComponent("backdrop-sample-cost-\(UUID().uuidString)", isDirectory: true)
        var scratch = true
        if let drafts = env["BACKDROP_SAMPLE_DRAFTS"] { folder = URL(fileURLWithPath: drafts, isDirectory: true); scratch = false } else { try SampleLenses.install(into: folder) }
        defer { if scratch { try? FileManager.default.removeItem(at: folder) } }
        let only = Set((env["BACKDROP_SAMPLE_ONLY"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let busy = h.input(Self.scene([.smile, .mouthOpen, .browRaise]))
        for pack in LensPackFolder.scan(folder).packs where only.isEmpty || only.contains(pack.name.lowercased()) {
            let lens = PackLens(pack)
            let first = CFAbsoluteTimeGetCurrent()
            _ = h.bitmap(lens.render(h.at(busy, time: 0)))
            let firstFrame = (CFAbsoluteTimeGetCurrent() - first) * 1000
            // The median, so a hiccup from something else on a busy machine doesn't count against the lens.
            guard let buffer = h.compositor.makeOutputBuffer() else { return XCTFail("no output buffer") }
            var times: [Double] = []
            for i in 0..<60 {
                let started = CFAbsoluteTimeGetCurrent()
                h.compositor.render(lens.render(h.at(busy, time: Double(i + 1) / 30)), into: buffer)
                times.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
            }
            times.sort()
            let median = times[times.count / 2]
            print(String(format: "SAMPLE-COST %@ first %.1f ms, median %.1f ms, worst %.1f ms", pack.name as NSString, firstFrame, median, times.last ?? 0))
            XCTAssertLessThan(median, 9, "\(pack.name) takes \(Int(median)) ms a frame")
        }
    }

    func testPicturesOfEverySampleInEveryState() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipIf(env["BACKDROP_TEST_OUTPUT"] == nil, "pictures only; set TEST_RUNNER_BACKDROP_TEST_OUTPUT")
        var folder = FileManager.default.temporaryDirectory.appendingPathComponent("backdrop-sample-preview-\(UUID().uuidString)", isDirectory: true)
        var scratch = true
        if let drafts = env["BACKDROP_SAMPLE_DRAFTS"] { folder = URL(fileURLWithPath: drafts, isDirectory: true); scratch = false } else { try SampleLenses.install(into: folder) }
        defer { if scratch { try? FileManager.default.removeItem(at: folder) } }
        let (packs, problems) = LensPackFolder.scan(folder)
        XCTAssertEqual(problems, [])
        let only = Set((env["BACKDROP_SAMPLE_ONLY"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        for pack in packs where only.isEmpty || only.contains(pack.name.lowercased()) {
            XCTAssertEqual(pack.warnings, [], pack.name)
            let slug = pack.name.lowercased().replacingOccurrences(of: " ", with: "-")
            func save(_ image: CIImage, _ state: String) { Output.save(image, as: "preview-\(slug)-\(state).png") }
            let triggers = pack.layers.map(\.show) + pack.warps.map(\.show) + pack.emitters.map(\.show)
            let own = Set(triggers.map(\.signal)).intersection([.smile, .browRaise, .mouthOpen, .blink])
            let rest = h.input(Self.scene([]))
            save(frames(PackLens(pack), rest, count: 45), "1-rest")
            for signal in own.sorted(by: { $0.rawValue < $1.rawValue }) {
                save(frames(PackLens(pack), h.input(Self.scene([signal])), count: 45), "2-\(signal.rawValue)")
            }
            let active = own.subtracting([.blink])
            let all = h.input(Self.scene(active))
            // The moment it switches on: a second at rest, then a fifth of a second of the expression.
            let entering = PackLens(pack)
            _ = frames(entering, rest, count: 30)
            save(frames(entering, h.input(Self.scene(own)), count: 6, from: 30), "3-enter")
            if own.count > 1 { save(frames(PackLens(pack), all, count: 45), "4-all") }
            save(frames(PackLens(pack), h.input(Self.scene(active, center: CGPoint(x: 520, y: 360), scale: 0.85, roll: 0.4)), count: 45), "5-tilted")
            save(frames(PackLens(pack), h.input(Self.scene(active, center: CGPoint(x: 900, y: 300), scale: 0.45)), count: 45), "6-far")
            save(frames(PackLens(pack), h.input(Self.scene(active, center: CGPoint(x: 640, y: 330), scale: 1.7)), count: 45), "7-close")
            save(frames(PackLens(pack), faceless(rest), count: 45), "8-nobody")
            let light = Self.scene(active).input(services: h.services, compositor: h.compositor, grid: h.grid, background: Self.lightRoom())
            save(frames(PackLens(pack), light, count: 45), "9-light")
        }
    }
}
