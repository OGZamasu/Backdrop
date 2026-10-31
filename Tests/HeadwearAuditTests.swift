import CoreImage
import XCTest

/// Pictures of every dress-up costume in every state, for looking at. Writes nothing unless BACKDROP_TEST_OUTPUT is set;
/// HEADWEAR_ONLY (a comma-separated list of kinds) narrows it down while working on a few.
final class HeadwearAuditTests: XCTestCase {
    private let h = LensHarness()

    private enum Subject {
        case cartoon(SyntheticScene)
        case real(HeadwearRealHead)
    }

    private struct Mood {
        let name: String
        let subject: Subject
    }

    private func moods() -> [Mood] {
        var s = SyntheticScene(center: CGPoint(x: 640, y: 360))
        var out: [Mood] = [Mood(name: "neutral", subject: .cartoon(s))]
        s.smile = 1; out.append(Mood(name: "smile", subject: .cartoon(s))); s.smile = 0
        s.mouthOpen = 0.9; out.append(Mood(name: "mouth", subject: .cartoon(s))); s.mouthOpen = 0
        s.browRaise = 1; out.append(Mood(name: "brows", subject: .cartoon(s))); s.browRaise = 0
        s.blink = 1; out.append(Mood(name: "blink", subject: .cartoon(s))); s.blink = 0
        s.roll = 0.5; out.append(Mood(name: "tilt", subject: .cartoon(s)))
        s.roll = -0.6; s.center = CGPoint(x: 420, y: 380); out.append(Mood(name: "tiltleft", subject: .cartoon(s))); s.roll = 0
        s.scale = 0.5; s.center = CGPoint(x: 900, y: 300); out.append(Mood(name: "far", subject: .cartoon(s)))
        s.scale = 1.7; s.center = CGPoint(x: 640, y: 250); out.append(Mood(name: "near", subject: .cartoon(s)))
        var r = HeadwearRealHead()
        out.append(Mood(name: "real", subject: .real(r)))
        r.skin = CGColor(srgbRed: 0.45, green: 0.3, blue: 0.22, alpha: 1); r.hair = CGColor(srgbRed: 0.08, green: 0.06, blue: 0.06, alpha: 1)
        r.shirt = CGColor(srgbRed: 0.95, green: 0.95, blue: 0.94, alpha: 1); r.roll = -0.35; r.center = CGPoint(x: 700, y: 360)
        out.append(Mood(name: "realdark", subject: .real(r)))
        r = HeadwearRealHead(); r.hair = CGColor(srgbRed: 0.85, green: 0.7, blue: 0.45, alpha: 1); r.io = 100; r.center = CGPoint(x: 600, y: 330)
        r.smile = 1; r.mouthOpen = 0.9; r.browRaise = 1; r.roll = 0.3
        out.append(Mood(name: "realactive", subject: .real(r)))
        return out
    }

    private func frame(_ base: LensInput, face: FaceState?, time: Double) -> LensInput {
        LensInput(time: time, dt: 1.0 / 30, rect: base.rect, camera: base.camera, matte: base.matte, background: base.background,
                  composed: base.composed, matteGrid: base.matteGrid, face: face, services: base.services)
    }

    private func render(_ make: () -> Lens, _ name: String) {
        for mood in moods() {
            let base: LensInput
            let face: FaceState, calm: FaceState
            switch mood.subject {
            case .cartoon(let s):
                base = h.input(s)
                face = s.face()
                var c = s; c.smile = 0; c.mouthOpen = 0; c.browRaise = 0; c.blink = 0
                calm = c.face()
            case .real(let r):
                base = r.input(services: h.services)
                face = r.face()
                var c = r; c.smile = 0; c.mouthOpen = 0; c.browRaise = 0; c.blink = 0
                calm = c.face()
            }
            let lens = make()
            for i in 0..<30 { _ = lens.render(frame(base, face: calm, time: Double(i) / 30)) }
            var out = base.composed
            for i in 0..<(mood.name == "blink" ? 3 : 24) { out = lens.render(frame(base, face: face, time: 1 + Double(i) / 30)) }
            Output.save(out, as: "audit-\(name)-\(mood.name).png")
        }
    }

    func testAuditPictures() throws {
        guard ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"] != nil else { throw XCTSkip("only makes pictures") }
        let only = ProcessInfo.processInfo.environment["HEADWEAR_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        for kind in HeadwearKind.allCases where only?.contains(kind.rawValue) ?? true { render({ DressUpLens(kind: kind) }, kind.rawValue) }
    }
}
