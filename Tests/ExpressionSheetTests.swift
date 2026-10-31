import CoreImage
import CoreImage.CIFilterBuiltins
import XCTest

/// Contact sheets of every expression and funhouse lens, in the states that matter: at rest, reacting, tilted, far, near,
/// over a light backdrop and with the face gone. Only useful to look at, so they are written only when BACKDROP_TEST_OUTPUT is set.
final class ExprContactSheetTests: ExpressionLensTestCase {
    /// One lens to photograph: how to make it, and what to do with the face to set it off.
    struct Subject {
        var id: String
        var make: () -> Lens
        var act: (inout SyntheticScene) -> Void
        var seconds = 1.2
        /// For signals the synthetic scene can't pose, such as a pucker.
        var faceEdit: ((inout FaceState) -> Void)? = nil
    }

    static func subjects() -> [Subject] {
        var all: [Subject] = [
            Subject(id: "big-eyes", make: { FunhouseLens(kind: .bigEyes) }, act: { $0.browRaise = 1 }),
            Subject(id: "chipmunk", make: { FunhouseLens(kind: .chipmunk) }, act: { $0.smile = 1 }),
            Subject(id: "big-mouth", make: { FunhouseLens(kind: .bigMouth) }, act: { $0.mouthOpen = 0.8 }),
            Subject(id: "rainbow-barf", make: { BreathLens(kind: .rainbow) }, act: { $0.mouthOpen = 1 }),
            Subject(id: "fire-breath", make: { BreathLens(kind: .fire) }, act: { $0.mouthOpen = 1 }),
            Subject(id: "laser-eyes", make: { LaserEyesLens() }, act: { $0.browRaise = 1 }),
        ]
        let acts: [String: (inout SyntheticScene) -> Void] = [
            "heart-eyes": { $0.smile = 1 }, "star-eyes": { $0.browRaise = 1 }, "happy-tears": { $0.smile = 1; $0.mouthOpen = 0.5 },
            "storm-cloud": { $0.browRaise = 1 }, "emoji-mask": { $0.smile = 1; $0.mouthOpen = 0.9 }, "pinocchio": { $0.mouthOpen = 0.8 },
            "mood-aura": { $0.smile = 1 }, "alien-face": { $0.browRaise = 1 }, "swirl-face": { $0.mouthOpen = 1 },
            "squeeze-face": { _ in }, "googly-eyes": { $0.blink = 0.3 },
        ]
        let seconds: [String: Double] = ["pinocchio": 3.2, "happy-tears": 1.6, "storm-cloud": 1.4]
        for info in ExpressionFaces.all {
            all.append(Subject(id: info.id, make: info.make, act: acts[info.id] ?? ExprContactSheetTests.defaultAct(info.id),
                               seconds: seconds[info.id] ?? ExprContactSheetTests.defaultSeconds(info.id),
                               faceEdit: info.id == "kiss-marks" ? { $0.mouthWidth = 0.5 * $0.interocular } : nil))
        }
        return all
    }

    /// What sets off each of the newer lenses, for the sheets.
    static func defaultAct(_ id: String) -> (inout SyntheticScene) -> Void {
        switch id {
        case "anime-eyes", "balloon-head", "comic-pow": return { $0.smile = 1 }
        case "sweat-drop", "tiny-head", "cyber-visor": return { $0.browRaise = 1 }
        case "fuming", "long-face", "melting-face": return { $0.mouthOpen = 1 }
        case "mind-blown": return { $0.mouthOpen = 1; $0.browRaise = 1 }
        case "sleepy-zzz": return { $0.blink = 1 }
        case "kiss-marks": return { $0.smile = 0 }
        case "dizzy-stars": return { $0.roll = 0.4 }
        case "mirror-face": return { $0.roll = 0.3 }
        case "glitch-face": return { $0.mouthOpen = 1 }
        default: return { $0.smile = 1 }
        }
    }

    static func defaultSeconds(_ id: String) -> Double {
        switch id {
        case "mind-blown": return 0.9
        case "sleepy-zzz", "melting-face": return 2.5
        case "dizzy-stars": return 3
        case "kiss-marks", "fuming": return 1.6
        default: return 1.2
        }
    }

    /// A pale, warm backdrop, to check that nothing gets lost on white.
    static func lightBackdrop() -> CIImage {
        let g = CIFilter.linearGradient()
        g.point0 = CGPoint(x: 0, y: 720); g.point1 = CGPoint(x: 1280, y: 0)
        g.color0 = CIColor(red: 0.96, green: 0.95, blue: 0.92); g.color1 = CIColor(red: 0.84, green: 0.88, blue: 0.93)
        return g.outputImage!.cropped(to: CGRect(origin: .zero, size: SyntheticScene.size))
    }

    private func snapshot(_ image: CIImage) -> CIImage {
        let b = bits(image)
        return CIImage(bitmapData: Data(b.bytes), bytesPerRow: b.width * 4, size: CGSize(width: b.width, height: b.height), format: .RGBA8, colorSpace: TestSupport.srgb)
    }

    /// Runs one state and returns the last frame.
    private func shoot(_ subject: Subject, scene s: SyntheticScene, react: Bool, seconds: Double, backdrop: CIImage?, kickoff: Bool = false) -> CIImage {
        var posed = s
        if react { subject.act(&posed) }
        let frame = posed.input(services: h.services, compositor: h.compositor, background: backdrop)
        let p = Player(subject.make(), base: frame)
        if kickoff { p.play(s.face(), seconds: 0.4) }        // at rest first, so a lens that reacts to a change sees one
        var f = posed.face()
        if react { subject.faceEdit?(&f) }
        p.play(f, seconds: seconds)
        return snapshot(p.last)
    }

    /// Lays cells out in a grid at half size, labelled by their order (left to right, top to bottom).
    private func sheet(_ cells: [CIImage], columns: Int, scale: Double = 0.5) -> CIImage {
        let w = 1280 * scale, h = 720 * scale, gap = 6.0
        let rows = (cells.count + columns - 1) / columns
        let size = CGSize(width: Double(columns) * (w + gap) - gap, height: Double(rows) * (h + gap) - gap)
        var out = CIImage(color: CIColor(red: 0.06, green: 0.06, blue: 0.07)).cropped(to: CGRect(origin: .zero, size: size))
        for (i, cell) in cells.enumerated() {
            let col = i % columns, row = i / columns
            let x = Double(col) * (w + gap), y = size.height - Double(row + 1) * h - Double(row) * gap
            out = cell.transformed(by: CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: x, y: y))).composited(over: out)
        }
        return out.cropped(to: CGRect(origin: .zero, size: size))
    }

    /// The six states of one lens on one sheet: rest, reacting, tilted, far, near, and over a light backdrop.
    func sheetFor(_ subject: Subject) -> CIImage {
        let dark = SyntheticScene.backdrop(), light = Self.lightBackdrop()
        let middle = SyntheticScene(center: CGPoint(x: 640, y: 400))
        var tilted = SyntheticScene(center: CGPoint(x: 560, y: 380)); tilted.roll = 0.4
        let far = SyntheticScene(center: CGPoint(x: 880, y: 330), scale: 0.45)
        let near = SyntheticScene(center: CGPoint(x: 640, y: 330), scale: 1.7)
        let cells = [
            shoot(subject, scene: middle, react: false, seconds: 1.0, backdrop: dark),
            shoot(subject, scene: middle, react: true, seconds: subject.seconds, backdrop: dark, kickoff: true),
            shoot(subject, scene: tilted, react: true, seconds: subject.seconds, backdrop: dark, kickoff: true),
            shoot(subject, scene: far, react: true, seconds: subject.seconds, backdrop: dark, kickoff: true),
            shoot(subject, scene: near, react: true, seconds: subject.seconds, backdrop: dark, kickoff: true),
            shoot(subject, scene: middle, react: true, seconds: subject.seconds, backdrop: light, kickoff: true),
        ]
        return sheet(cells, columns: 3)
    }

    func testContactSheets() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"] != nil, "set TEST_RUNNER_BACKDROP_TEST_OUTPUT to look at the sheets")
        let only = ProcessInfo.processInfo.environment["EXPR_SHEET"].map { Set($0.split(separator: ",").map(String.init)) }
        for subject in Self.subjects() where only?.contains(subject.id) ?? true {
            Output.save(sheetFor(subject), as: "sheet-\(subject.id).png")
        }
    }

    /// Every lens, reacting, side by side: the family portrait.
    func testFamilyPortrait() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"] != nil, "set TEST_RUNNER_BACKDROP_TEST_OUTPUT to look at the sheets")
        let middle = SyntheticScene(center: CGPoint(x: 640, y: 400))
        let cells = Self.subjects().map { shoot($0, scene: middle, react: true, seconds: $0.seconds, backdrop: SyntheticScene.backdrop(), kickoff: true) }
        Output.save(sheet(cells, columns: 6, scale: 0.3), as: "family-portrait.png")
    }
}
