import CoreImage
import simd
import XCTest

// Tests for the seventeen expression and funhouse lenses added in round two. Each one: it reacts to its own signal and not
// to the others, it needs more to start than to keep going, it stays inside the picture, and it leaves when the face does.

/// Shared poses for the new lenses.
class ExprNewLensTestCase: ExpressionLensTestCase {
    /// The usual "other signals" a lens must ignore, each as a face edit.
    func others(except keep: String) -> [(String, (inout FaceState) -> Void)] {
        let all: [(String, (inout FaceState) -> Void)] = [("smile", { $0.smile = 1 }), ("mouth", { $0.mouthOpen = 1 }), ("brows", { $0.browRaise = 1 }), ("blink", { $0.blink = 1 })]
        return all.filter { $0.0 != keep }
    }

    /// How much the picture changed inside a rect around a face-space point, `r` eye-spacings each way.
    func changeNear(_ out: Bitmap, _ f: FaceState, _ x: Double, _ y: Double, r: Double = 0.3, from still: Bitmap? = nil) -> Int {
        let p = f.exprPoint(x, y), io = f.interocular
        return out.change(from: still ?? plain, in: CGRect(x: p.x - r * io, y: p.y - r * io, width: 2 * r * io, height: 2 * r * io))
    }

    /// The 5% border all round the picture.
    func assertBorderUntouched(_ out: Bitmap, still: Bitmap, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let w = 1280.0, h = 720.0, mx = w * 0.04, my = h * 0.04
        for strip in [CGRect(x: 0, y: h - my, width: w, height: my), CGRect(x: 0, y: 0, width: mx, height: h), CGRect(x: w - mx, y: 0, width: mx, height: h)] {
            XCTAssertLessThanOrEqual(out.change(from: still, in: strip), 4, "\(message): nothing in the border", file: file, line: line)
        }
    }
}

// MARK: - Anime Eyes

final class ExprAnimeEyesTests: ExprNewLensTestCase {
    func testBigEyesCoverYoursAndASmileMakesThemHappy() {
        let lens = ExprAnimeEyesLens()
        let p = Player(lens, base: base)
        let f = face()
        let idle = bits(p.play(f, seconds: 1))
        Output.save(p.last, as: "expr-anime-eyes-idle.png")
        for x in [-0.5, 0.5] { XCTAssertGreaterThan(changeNear(idle, f, x, 0, r: 0.25), 150, "an anime eye over each eye") }
        XCTAssertFalse(lens.isHappy)
        p.play(face { $0.smile = 1 }, seconds: 1)
        XCTAssertTrue(lens.isHappy)
        XCTAssertGreaterThan(lens.happiness, 0.8)
        XCTAssertGreaterThan(lens.sparkleCount, 3, "sparkles pop around the head")
        Output.save(p.last, as: "expr-anime-eyes-happy.png")
        assertCornersUntouched(bits(p.last), "anime eyes")
    }

    func testOnlyASmileAndItNeedsMoreToStartThanToStay() {
        for (name, edit) in others(except: "smile") {
            let lens = ExprAnimeEyesLens()
            Player(lens, base: base).play(face(edit), seconds: 1)
            XCTAssertFalse(lens.isHappy, name)
        }
        let lens = ExprAnimeEyesLens()
        let p = Player(lens, base: base)
        p.play(face { $0.smile = 0.42 }, seconds: 0.5)
        XCTAssertFalse(lens.isHappy)
        p.play(face { $0.smile = 0.8 }, seconds: 0.2)
        XCTAssertTrue(lens.isHappy)
        p.play(face { $0.smile = 0.35 }, seconds: 0.5)
        XCTAssertTrue(lens.isHappy, "a slacker smile keeps it")
        p.play(face(), seconds: 0.3)
        XCTAssertFalse(lens.isHappy)
    }

    func testABlinkClosesThem() {
        let open = bits(Player(ExprAnimeEyesLens(), base: base).play(face(), seconds: 1))
        var shut = scene; shut.blink = 1
        let closed = bits(Player(ExprAnimeEyesLens(), base: h.input(shut)).play(shut.face(), seconds: 1))
        let f = face()
        func white(_ b: Bitmap) -> Int { count(b, in: CGRect(x: f.leftEye.x - 30, y: f.leftEye.y - 30, width: 60, height: 60)) { $0.r > 225 && $0.g > 225 && $0.b > 225 } }
        XCTAssertGreaterThan(white(open), white(closed) * 3 + 10)
    }
}

// MARK: - Sweat Drop

final class ExprSweatDropTests: ExprNewLensTestCase {
    func testRaisedBrowsBringADropThatSlidesAndDripsOff() {
        let lens = ExprSweatDropLens()
        let p = Player(lens, base: base)
        p.play(face(), seconds: 0.5)
        XCTAssertFalse(lens.hasDrop)
        let raised = face { $0.browRaise = 1 }
        let out = bits(p.play(raised, seconds: 0.8))
        XCTAssertTrue(lens.isNervous)
        XCTAssertTrue(lens.hasDrop)
        XCTAssertGreaterThan(changeNear(out, raised, 1.12, 0.8, r: 0.35), 120, "a drop on the temple")
        Output.save(p.last, as: "expr-sweat-drop.png")
        p.play(raised, seconds: 2.4)
        XCTAssertGreaterThanOrEqual(lens.dropsShed, 1, "held long enough, it drips off")
        p.play(face(), seconds: 0.2)
        XCTAssertFalse(lens.isNervous)
        p.play(face(), seconds: 2)
        XCTAssertFalse(lens.hasDrop)
        XCTAssertEqual(lens.fallingCount, 0, "the shed drops have fallen away")
        assertCornersUntouched(bits(p.last), "sweat drop at rest")
    }

    func testOnlyTheBrowsBringIt() {
        for (name, edit) in others(except: "brows") {
            let lens = ExprSweatDropLens()
            Player(lens, base: base).play(face(edit), seconds: 1.5)
            XCTAssertFalse(lens.isNervous, name)
            XCTAssertFalse(lens.hasDrop, name)
        }
    }
}

// MARK: - Fuming

final class ExprFumingTests: ExprNewLensTestCase {
    func testShoutingBuildsAngerSteamAndARedFace() {
        let lens = ExprFumingLens()
        let p = Player(lens, base: base)
        let calm = bits(p.play(face(), seconds: 1))
        XCTAssertEqual(lens.anger, 0, accuracy: 0.001)
        XCTAssertEqual(calm.change(from: plain, in: base.rect), 0, "nothing at rest")
        let shout = face { $0.mouthOpen = 1 }
        let out = bits(p.play(shout, seconds: 1.4))
        Output.save(p.last, as: "expr-fuming.png")
        XCTAssertTrue(lens.isShouting)
        XCTAssertGreaterThan(lens.anger, 0.9)
        XCTAssertGreaterThan(lens.steamCount, 10)
        XCTAssertGreaterThan(changeNear(out, shout, -1.7, -0.1, r: 0.5), 100, "steam off the left of the head")
        XCTAssertGreaterThan(changeNear(out, shout, 1.7, -0.1, r: 0.5), 100, "and the right")
        let cheek = shout.exprPoint(-0.6, -0.8)
        let before = plain.pixel(Int(cheek.x), Int(cheek.y)), after = out.pixel(Int(cheek.x), Int(cheek.y))
        XCTAssertGreaterThan(before.g - after.g, 20, "the face flushes red: \(before) to \(after)")
        assertCornersUntouched(out, "fuming")
    }

    func testItTakesAShoutAndCoolsOffAfter() {
        for (name, edit) in others(except: "mouth") {
            let lens = ExprFumingLens()
            Player(lens, base: base).play(face(edit), seconds: 1.5)
            XCTAssertEqual(lens.anger, 0, accuracy: 0.001, name)
            XCTAssertEqual(lens.steamCount, 0, name)
        }
        let lens = ExprFumingLens()
        let p = Player(lens, base: base)
        p.play(face { $0.mouthOpen = 0.4 }, seconds: 1)
        XCTAssertFalse(lens.isShouting, "talking isn't shouting")
        p.play(face { $0.mouthOpen = 0.9 }, seconds: 1)
        p.play(face { $0.mouthOpen = 0.3 }, seconds: 0.3)
        XCTAssertTrue(lens.isShouting, "a dip doesn't stop it")
        let hot = lens.anger
        p.play(face(), seconds: 1)
        XCTAssertLessThan(lens.anger, hot, "and it cools off")
    }
}

// MARK: - Dizzy

final class ExprDizzyTests: ExprNewLensTestCase {
    func testStarsCircleAndTippingYourHeadMakesYouDizzy() {
        let lens = ExprDizzyLens()
        let p = Player(lens, base: base)
        let f = face()
        let still = bits(p.play(f, seconds: 2))
        XCTAssertLessThan(lens.dizziness, 0.05, "holding still upright, nothing builds")
        XCTAssertFalse(lens.hasSpiralEyes)
        XCTAssertGreaterThan(changeNear(still, f, 0, 1.32, r: 0.6), 100, "a ring of stars over the head")
        var tipped = scene; tipped.roll = 0.45
        let frame = h.input(tipped)
        let q = Player(lens, base: frame)
        q.play(tipped.face(), seconds: 3)
        XCTAssertTrue(lens.hasSpiralEyes, "a held tip makes you dizzy")
        Output.save(q.last, as: "expr-dizzy.png")
        q.play(f, seconds: 4)
        XCTAssertFalse(lens.hasSpiralEyes, "and it wears off")
    }

    func testWobblingYourHeadSpinsThemUp() {
        let lens = ExprDizzyLens()
        let p = Player(lens, base: base)
        for i in 0..<60 {
            var s = scene; s.roll = 0.12 * sin(Double(i) * 0.6)
            p.play(s.face(), seconds: 1.0 / 30)
        }
        XCTAssertGreaterThan(lens.dizziness, 0.3, "side to side builds it even without a big tip")
    }
}

// MARK: - Kisses

final class ExprKissTests: ExprNewLensTestCase {
    private func pucker(_ f: inout FaceState) { f.mouthWidth = 0.5 * f.interocular }

    func testAPuckerBlowsKissesThatLandAroundYou() {
        let lens = ExprKissLens()
        let p = Player(lens, base: base)
        p.play(face(), seconds: 1)
        XCTAssertEqual(lens.kissCount, 0)
        p.play(face(pucker), seconds: 1.4)
        XCTAssertTrue(lens.isPuckered)
        XCTAssertGreaterThanOrEqual(lens.kissCount, 2, "hold it and they keep coming")
        let f = face()
        let inset = base.rect.insetBy(dx: 64, dy: 36)
        for m in lens.marks {
            XCTAssertTrue(inset.contains(m.to), "a kiss lands inside the picture: \(m.to)")
            XCTAssertGreaterThan(hypot(m.to.x - f.eyeCenter.x, m.to.y - f.exprFaceCenter.y), f.interocular * 1.2, "and never on the face")
        }
        Output.save(p.last, as: "expr-kisses.png")
        p.play(face(), seconds: 4)
        XCTAssertTrue(lens.marks.isEmpty, "they fade away")
    }

    func testOnlyAPuckerCounts() {
        for (name, edit) in others(except: "none") {
            let lens = ExprKissLens()
            Player(lens, base: base).play(face(edit), seconds: 1.5)
            XCTAssertEqual(lens.kissCount, 0, name)
        }
        let lens = ExprKissLens()
        let p = Player(lens, base: base)
        p.play(face { $0.mouthWidth = 0.72 * $0.interocular }, seconds: 1)
        XCTAssertFalse(lens.isPuckered, "a slightly narrower mouth isn't a pucker")
        p.play(face(pucker), seconds: 0.2)
        XCTAssertTrue(lens.isPuckered)
        p.play(face { $0.mouthWidth = 0.7 * $0.interocular }, seconds: 0.3)
        XCTAssertTrue(lens.isPuckered, "loosening a little keeps it")
        p.play(face(), seconds: 0.2)
        XCTAssertFalse(lens.isPuckered)
    }
}

// MARK: - Sleepy

final class ExprSleepyTests: ExprNewLensTestCase {
    func testABlinkIsNotANapButClosedEyesAre() {
        let lens = ExprSleepyLens()
        let p = Player(lens, base: base)
        p.play(face(), seconds: 0.5)
        p.play(face { $0.blink = 1 }, seconds: 0.2)
        XCTAssertFalse(lens.isAsleep, "a blink")
        p.play(face(), seconds: 0.3)
        p.play(face { $0.blink = 1 }, seconds: 2)
        XCTAssertTrue(lens.isAsleep)
        XCTAssertGreaterThan(lens.zCount, 1, "Z's drift up")
        XCTAssertGreaterThan(lens.bubbleSize, 0.2, "a bubble at the nose")
        Output.save(p.last, as: "expr-sleepy.png")
        assertCornersUntouched(bits(p.last), "sleepy")
        p.play(face(), seconds: 1.0 / 30)
        XCTAssertFalse(lens.isAsleep)
        XCTAssertEqual(lens.popCount, 1, "waking pops the bubble")
        XCTAssertEqual(lens.bubbleSize, 0, accuracy: 0.001)
    }

    func testOnlyClosedEyesSendYouToSleep() {
        for (name, edit) in others(except: "blink") {
            let lens = ExprSleepyLens()
            Player(lens, base: base).play(face(edit), seconds: 2)
            XCTAssertFalse(lens.isAsleep, name)
            XCTAssertEqual(lens.zCount, 0, name)
        }
    }
}

// MARK: - Mind Blown

final class ExprMindBlownTests: ExprNewLensTestCase {
    func testJawAndBrowsTogetherBlowTheTopOffOnce() {
        for (name, edit) in [("mouth", { (f: inout FaceState) in f.mouthOpen = 1 }), ("brows", { $0.browRaise = 1 }), ("smile", { $0.smile = 1 })] as [(String, (inout FaceState) -> Void)] {
            let lens = ExprMindBlownLens()
            Player(lens, base: base).play(face(edit), seconds: 1.5)
            XCTAssertEqual(lens.blastCount, 0, "\(name) alone does nothing")
        }
        let lens = ExprMindBlownLens()
        let p = Player(lens, base: base)
        let shock = face { $0.mouthOpen = 1; $0.browRaise = 1 }
        p.play(shock, seconds: 0.2)
        XCTAssertEqual(lens.blastCount, 0, "the fuse fizzes first")
        let out = bits(p.play(shock, seconds: 0.5))
        XCTAssertEqual(lens.blastCount, 1)
        XCTAssertGreaterThan(changeNear(out, shock, 0, 2.6, r: 0.8), 150, "a cloud over the head")
        Output.save(p.last, as: "expr-mind-blown.png")
        p.play(shock, seconds: 3)
        XCTAssertEqual(lens.blastCount, 1, "holding the face doesn't go off again")
        p.play(face(), seconds: 0.3)
        p.play(shock, seconds: 0.6)
        XCTAssertEqual(lens.blastCount, 2, "relax and do it again for another")
    }

    func testANearFaceKeepsTheCloudInThePicture() {
        let near = SyntheticScene(center: CGPoint(x: 640, y: 330), scale: 1.7)
        let frame = h.input(near)
        let still = bits(frame.composed)
        let p = Player(ExprMindBlownLens(), base: frame)
        var f = near.face(); f.mouthOpen = 1; f.browRaise = 1
        let out = bits(p.play(f, seconds: 2))
        Output.save(p.last, as: "expr-mind-blown-near.png")
        XCTAssertLessThanOrEqual(out.change(from: still, in: CGRect(x: 0, y: 696, width: 1280, height: 24)), 4, "once the sparks have flown, the cloud sits below the top edge")
    }
}

// MARK: - Thinking

final class ExprThoughtBubbleTests: ExprNewLensTestCase {
    func testTheBubbleShowsWhatYourFaceIsThinking() {
        typealias T = ExprThoughtBubbleLens.Thought
        let cases: [(String, (inout FaceState) -> Void, T)] = [
            ("rest", { _ in }, .pondering), ("smile", { $0.smile = 1 }, .love), ("laugh", { $0.smile = 1; $0.mouthOpen = 0.8 }, .laugh),
            ("brows", { $0.browRaise = 1 }, .idea), ("mouth", { $0.mouthOpen = 1 }, .hungry), ("eyes shut", { $0.blink = 1 }, .sleepy),
        ]
        for (name, edit, want) in cases { XCTAssertEqual(ExprThoughtBubbleLens.thought(for: face(edit), current: .pondering), want, name) }
        XCTAssertEqual(ExprThoughtBubbleLens.thought(for: face { $0.smile = 0.4 }, current: .love), .love, "a fading smile keeps the heart a while")
        XCTAssertEqual(ExprThoughtBubbleLens.thought(for: face { $0.smile = 0.4 }, current: .pondering), .pondering)
        XCTAssertEqual(Set(T.allCases.map(\.emoji)).count, T.allCases.count)
    }

    func testItSettlesBeforeChangingAndSitsBesideTheHead() {
        let lens = ExprThoughtBubbleLens()
        let p = Player(lens, base: base)
        let f = face()
        let out = bits(p.play(f, seconds: 1))
        XCTAssertEqual(lens.shown, .pondering)
        XCTAssertGreaterThan(changeNear(out, f, 1.95, 1.65, r: 0.5), 150, "the bubble is up and to the side")
        XCTAssertEqual(changeNear(out, f, 0, -0.5, r: 0.4), 0, "nothing over the middle of the face")
        p.play(face { $0.browRaise = 1 }, seconds: 1.0 / 30)
        XCTAssertEqual(lens.shown, .pondering, "one frame isn't a thought")
        p.play(face { $0.browRaise = 1 }, seconds: 0.4)
        XCTAssertEqual(lens.shown, .idea)
        Output.save(p.last, as: "expr-thinking-idea.png")
    }

    func testItMovesToTheOtherSideWhenThereIsNoRoom() {
        let edge = SyntheticScene(center: CGPoint(x: 1120, y: 380))
        let lens = ExprThoughtBubbleLens()
        let p = Player(lens, base: h.input(edge))
        p.play(edge.face(), seconds: 1)
        XCTAssertEqual(lens.side, -1, "near the right edge, the bubble goes on the left")
        Output.save(p.last, as: "expr-thinking-edge.png")
    }
}

// MARK: - Face Scan

final class ExprFaceScanTests: ExprNewLensTestCase {
    func testTheScannerReadsYourMood() {
        typealias M = ExprFaceScanLens.Mood
        let cases: [(String, (inout FaceState) -> Void, M)] = [
            ("rest", { _ in }, .calm), ("smile", { $0.smile = 1 }, .happy), ("brows", { $0.browRaise = 1 }, .surprised),
            ("mouth", { $0.mouthOpen = 1 }, .loud), ("eyes shut", { $0.blink = 1 }, .asleep),
        ]
        for (name, edit, want) in cases { XCTAssertEqual(ExprFaceScanLens.mood(for: face(edit), current: .calm), want, name) }
        let lens = ExprFaceScanLens()
        let p = Player(lens, base: base)
        p.play(face(), seconds: 1)
        p.play(face { $0.smile = 1 }, seconds: 1.0 / 30)
        XCTAssertEqual(lens.mood, .calm, "a flicker doesn't change it")
        p.play(face { $0.smile = 1 }, seconds: 0.5)
        XCTAssertEqual(lens.mood, .happy)
        Output.save(p.last, as: "expr-face-scan.png")
    }

    func testTheHUDLocksOnAndItsPanelStaysOffTheFaceAndInFrame() {
        for (name, centre) in [("middle", CGPoint(x: 640, y: 400)), ("right edge", CGPoint(x: 1100, y: 400)), ("left edge", CGPoint(x: 180, y: 400))] {
            let s = SyntheticScene(center: centre)
            let frame = h.input(s)
            let still = bits(frame.composed)
            let lens = ExprFaceScanLens()
            let p = Player(lens, base: frame)
            let out = bits(p.play(s.face(), seconds: 1.5))
            let f = s.face()
            let faceBox = CGRect(x: f.eyeCenter.x - f.interocular * 1.2, y: f.eyeCenter.y - f.interocular * 1.9, width: f.interocular * 2.4, height: f.interocular * 3.3)
            XCTAssertFalse(lens.panelFrame.isNull, name)
            XCTAssertFalse(lens.panelFrame.intersects(faceBox), "\(name): the words sit beside the face, never on it")
            assertBorderUntouched(out, still: still, name)
            Output.save(p.last, as: "expr-face-scan-\(name.replacingOccurrences(of: " ", with: "-")).png")
        }
        XCTAssertTrue(ExpressionFaces.all.first { $0.id == "face-scanner" }?.showsText ?? false, "it puts words on the picture")
    }
}

// MARK: - Cyber Visor

final class ExprCyberVisorTests: ExprNewLensTestCase {
    func testTheVisorCoversTheEyesAndChangesModes() {
        let lens = ExprCyberVisorLens()
        let p = Player(lens, base: base)
        let f = face()
        let out = bits(p.play(f, seconds: 1))
        Output.save(p.last, as: "expr-cyber-visor.png")
        for eye in [f.leftEye, f.rightEye] {
            let c = out.pixel(Int(eye.x), Int(eye.y - 6))
            XCTAssertLessThan(c.r + c.g + c.b, 360, "smoked glass over the eyes: \(c)")
        }
        XCTAssertFalse(lens.isTargeting); XCTAssertFalse(lens.isPartying)
        p.play(face { $0.browRaise = 1 }, seconds: 0.5)
        XCTAssertTrue(lens.isTargeting)
        p.play(face { $0.browRaise = 0.4 }, seconds: 0.3)
        XCTAssertTrue(lens.isTargeting, "a lower raise keeps it")
        p.play(face { $0.smile = 1 }, seconds: 0.5)
        XCTAssertFalse(lens.isTargeting)
        XCTAssertTrue(lens.isPartying)
        Output.save(p.last, as: "expr-cyber-visor-party.png")
        for (name, edit) in [("mouth", { (f: inout FaceState) in f.mouthOpen = 1 }), ("blink", { $0.blink = 1 })] as [(String, (inout FaceState) -> Void)] {
            let other = ExprCyberVisorLens()
            Player(other, base: base).play(face(edit), seconds: 1)
            XCTAssertFalse(other.isTargeting || other.isPartying, name)
        }
    }
}

// MARK: - Comic Pow

final class ExprComicPowTests: ExprNewLensTestCase {
    func testEachExpressionHasItsSoundAndHoldingDoesNotRepeatIt() {
        for (edit, word) in [({ (f: inout FaceState) in f.smile = 1 }, ExprComicPowLens.Word.laugh), ({ $0.mouthOpen = 1 }, .wow), ({ $0.browRaise = 1 }, .what)] as [((inout FaceState) -> Void, ExprComicPowLens.Word)] {
            let lens = ExprComicPowLens()
            let p = Player(lens, base: base)
            p.play(face(), seconds: 0.5)
            XCTAssertEqual(lens.popCount, 0)
            p.play(face(edit), seconds: 1.2)
            XCTAssertEqual(lens.popCount, 1, word.rawValue)
            XCTAssertEqual(lens.pops.last?.word, word)
            Output.save(p.last, as: "expr-comic-\(word).png")
        }
        XCTAssertEqual(ExprComicPowLens().popCount, 0)
        let lens = ExprComicPowLens()
        Player(lens, base: base).play(face { $0.blink = 1 }, seconds: 1)
        XCTAssertEqual(lens.popCount, 0, "a blink says nothing")
    }

    func testWordsStayClearOfTheFaceAndInsideThePicture() {
        for centre in [CGPoint(x: 640, y: 400), CGPoint(x: 1120, y: 400), CGPoint(x: 160, y: 300)] {
            let s = SyntheticScene(center: centre)
            let lens = ExprComicPowLens()
            let p = Player(lens, base: h.input(s))
            let f = s.face()
            p.play(f, seconds: 0.3)
            p.play({ var g = f; g.smile = 1; return g }(), seconds: 0.6)
            p.play(f, seconds: 0.6)
            p.play({ var g = f; g.browRaise = 1; return g }(), seconds: 0.4)
            XCTAssertEqual(lens.pops.count, 2)
            for pop in lens.pops {
                XCTAssertGreaterThan(abs(pop.at.x - f.eyeCenter.x), f.interocular * 1.1, "beside the face, not on it (\(centre))")
                XCTAssertTrue(base.rect.insetBy(dx: 60, dy: 30).contains(pop.at), "inside the picture (\(centre))")
            }
        }
    }
}

// MARK: - Head warps

final class ExprHeadWarpTests: ExprNewLensTestCase {
    /// How many skin-coloured pixels there are around the head: a bigger head shows more.
    private func skin(_ b: Bitmap) -> Int {
        count(b, in: CGRect(x: 440, y: 180, width: 400, height: 460)) { abs($0.r - 238) < 18 && abs($0.g - 189) < 22 && abs($0.b - 158) < 26 }
    }

    func testBalloonHeadInflatesWithASmile() {
        let rest = skin(plain)
        let lens = ExprBalloonHeadLens()
        let p = Player(lens, base: base)
        let calm = bits(p.play(face(), seconds: 1.5))
        XCTAssertGreaterThan(skin(calm), rest, "a bit bigger already")
        XCTAssertFalse(lens.isInflated)
        let big = bits(p.play(face { $0.smile = 1 }, seconds: 2))
        Output.save(p.last, as: "expr-balloon-head.png")
        XCTAssertTrue(lens.isInflated)
        XCTAssertGreaterThan(lens.inflation, 0.6)
        XCTAssertGreaterThan(skin(big), skin(calm) * 11 / 10, "and much bigger smiling")
        assertCornersUntouched(big, "balloon head")
        for (name, edit) in others(except: "smile") {
            let other = ExprBalloonHeadLens()
            Player(other, base: base).play(face(edit), seconds: 1)
            XCTAssertFalse(other.isInflated, name)
        }
    }

    func testTinyHeadShrinksAndShrinksMoreWithRaisedBrows() {
        let rest = skin(plain)
        let lens = ExprTinyHeadLens()
        let p = Player(lens, base: base)
        let small = bits(p.play(face(), seconds: 1.5))
        XCTAssertLessThan(skin(small), rest * 8 / 10)
        let smaller = bits(p.play(face { $0.browRaise = 1 }, seconds: 1.5))
        Output.save(p.last, as: "expr-tiny-head.png")
        XCTAssertTrue(lens.isTinier)
        XCTAssertLessThan(skin(smaller), skin(small))
        assertCornersUntouched(smaller, "tiny head")
    }

    func testLongFaceStretchesTheChinWhileTheMouthIsOpen() {
        let lens = ExprLongFaceLens()
        let p = Player(lens, base: base)
        p.play(face(), seconds: 1)
        XCTAssertLessThan(lens.stretchAmount, 0.25)
        let out = bits(p.play(face { $0.mouthOpen = 1 }, seconds: 1.5))
        Output.save(p.last, as: "expr-long-face.png")
        XCTAssertTrue(lens.isStretching)
        XCTAssertGreaterThan(lens.stretchAmount, 0.6)
        let f = face()
        XCTAssertGreaterThan(changeNear(out, f, 0, -1.8, r: 0.4), 100, "the chin has moved down")
        p.play(face(), seconds: 2)
        XCTAssertLessThan(lens.stretchAmount, 0.3, "and boings back")
        for (name, edit) in others(except: "mouth") {
            let other = ExprLongFaceLens()
            Player(other, base: base).play(face(edit), seconds: 1)
            XCTAssertFalse(other.isStretching, name)
        }
    }

    func testMeltingDripsWhileTheMouthIsOpenAndFirmsUpAfter() {
        let lens = ExprMeltingLens()
        let p = Player(lens, base: base)
        let calm = bits(p.play(face(), seconds: 1))
        XCTAssertEqual(lens.meltAmount, 0, accuracy: 0.001)
        XCTAssertEqual(calm.change(from: plain, in: base.rect), 0, "no melt at rest")
        let out = bits(p.play(face { $0.mouthOpen = 1 }, seconds: 2.5))
        Output.save(p.last, as: "expr-melting.png")
        XCTAssertTrue(lens.isMelting)
        XCTAssertGreaterThan(lens.meltAmount, 0.8)
        let f = face()
        XCTAssertGreaterThan(changeNear(out, f, -0.22, -1.5, r: 0.3), 80, "a drip below the face")
        assertCornersUntouched(out, "melting")
        p.play(face { $0.mouthOpen = 0.3 }, seconds: 0.3)
        XCTAssertTrue(lens.isMelting, "a half-closed mouth keeps melting")
        p.play(face(), seconds: 2)
        XCTAssertLessThan(lens.meltAmount, 0.1, "and it firms up again")
    }

    func testWarpsLeaveWithTheFaceAndTheFarAwayAlone() {
        let far = SyntheticScene(center: CGPoint(x: 1000, y: 300), scale: 0.4)
        let frame = h.input(far)
        let still = bits(frame.composed)
        for make in [{ ExprBalloonHeadLens() as Lens }, { ExprTinyHeadLens() }, { ExprLongFaceLens() }, { ExprMeltingLens() }] {
            let p = Player(make(), base: frame)
            var f = far.face(); f.smile = 1; f.mouthOpen = 1; f.browRaise = 1
            let out = bits(p.play(f, seconds: 2))
            XCTAssertLessThanOrEqual(out.change(from: still, in: CGRect(x: 0, y: 0, width: 700, height: 720)), 4, "\(type(of: p.lens)): a small face warps only near itself")
            XCTAssertEqual(bits(p.play(nil, seconds: 1.5)).change(from: still, in: frame.rect), 0, "\(type(of: p.lens)) eases out when the face goes")
        }
    }
}

// MARK: - Mirror Face

final class ExprMirrorFaceTests: ExprNewLensTestCase {
    func testOneHalfIsCopiedOntoTheOtherAndTippingSwapsIt() {
        // An asymmetric picture: the backdrop is a diagonal gradient, so the two sides of the head differ.
        let lens = ExprMirrorFaceLens()
        let p = Player(lens, base: base)
        let f = face()
        let out = bits(p.play(f, seconds: 1.5))
        XCTAssertEqual(lens.source, -1, "starts copying the left half")
        // Inside the head oval, a point on the right now matches its mirror on the left.
        for (x, y) in [(0.9, 0.9), (1.1, -0.2), (0.7, 1.3)] {
            let a = f.exprPoint(x, y), b = f.exprPoint(-x, y)
            let pa = out.pixel(Int(a.x.rounded()), Int(a.y.rounded())), pb = out.pixel(Int(b.x.rounded()), Int(b.y.rounded()))
            XCTAssertLessThan(abs(pa.r - pb.r) + abs(pa.g - pb.g) + abs(pa.b - pb.b), 24, "mirrored at (\(x), \(y)): \(pa) vs \(pb)")
        }
        assertCornersUntouched(out, "mirror")
        var tipped = scene; tipped.roll = 0.3
        p.play(tipped.face(), seconds: 0.5)
        XCTAssertEqual(lens.source, 1, "tip the other way and the other half is copied")
        p.play(f, seconds: 0.5)
        XCTAssertEqual(lens.source, 1, "and straightening up keeps the choice")
        Output.save(p.last, as: "expr-mirror-face.png")
    }
}

// MARK: - Glitch Face

final class ExprGlitchFaceTests: ExprNewLensTestCase {
    func testABlinkGlitchesBrieflyAndAnOpenMouthMeltsItDown() {
        let lens = ExprGlitchFaceLens()
        let p = Player(lens, base: base)
        p.play(face(), seconds: 1)
        XCTAssertEqual(lens.burstCount, 0)
        p.play(face { $0.blink = 1 }, seconds: 0.1)
        XCTAssertEqual(lens.burstCount, 1)
        p.play(face { $0.blink = 1 }, seconds: 0.6)
        XCTAssertEqual(lens.burstCount, 1, "one blink, one burst")
        let out = bits(p.play(face { $0.mouthOpen = 1 }, seconds: 0.6))
        Output.save(p.last, as: "expr-glitch-face.png")
        XCTAssertTrue(lens.isMeltingDown)
        XCTAssertGreaterThan(lens.level, 0.8)
        XCTAssertGreaterThan(changeNear(out, face(), 0, -0.4, r: 0.8), 100, "the face is broken up")
        assertCornersUntouched(out, "glitch")
        p.play(face(), seconds: 1)
        XCTAssertFalse(lens.isMeltingDown)
    }

    func testTheIdleFlickerIsRareShortAndRepeatable() {
        let samples = stride(from: 0.0, to: 60, by: 1.0 / 30).map { ExprGlitchFaceLens.idleFlicker(at: $0) }
        let on = Double(samples.filter { $0 > 0 }.count) / Double(samples.count)
        XCTAssertGreaterThan(on, 0.01)
        XCTAssertLessThan(on, 0.15, "it flickers now and then, not all the time")
        XCTAssertEqual(ExprGlitchFaceLens.idleFlicker(at: 12.3), ExprGlitchFaceLens.idleFlicker(at: 12.3))
    }
}

// MARK: - Funhouse (round one, rebuilt)

final class ExprFunhouseTests: ExprNewLensTestCase {
    func testEachFunhouseReactsToItsOwnSignal() {
        for (kind, edit) in [(FunhouseLens.Kind.bigEyes, { (f: inout FaceState) in f.browRaise = 1 }), (.chipmunk, { $0.smile = 1 }), (.bigMouth, { $0.mouthOpen = 1 })] as [(FunhouseLens.Kind, (inout FaceState) -> Void)] {
            let lens = FunhouseLens(kind: kind)
            let p = Player(lens, base: base)
            p.play(face(), seconds: 1)
            XCTAssertFalse(lens.isReacting, "\(kind)")
            XCTAssertEqual(lens.strength, 1, accuracy: 0.05, "\(kind) settles at rest")
            p.play(face(edit), seconds: 1.5)
            XCTAssertTrue(lens.isReacting, "\(kind)")
            XCTAssertGreaterThan(lens.strength, 1.2, "\(kind) swells further")
            Output.save(p.last, as: "expr-funhouse-\(kind.rawValue).png")
            XCTAssertEqual(bits(p.play(nil, seconds: 1.5)).change(from: plain, in: base.rect), 0, "\(kind) eases out when the face goes")
        }
    }

    func testTheWarpHasNoHardEdge() {
        // Along a line out from the eye, neighbouring pixels never jump more than the picture itself does there.
        let out = bits(Player(FunhouseLens(kind: .bigEyes), base: base).play(face { $0.browRaise = 1 }, seconds: 1.5))
        let f = face()
        var worst = 0
        for dx in stride(from: 40, to: 110, by: 1) {
            let a = out.pixel(Int(f.leftEye.x) - dx, Int(f.leftEye.y) - 30), b = out.pixel(Int(f.leftEye.x) - dx - 1, Int(f.leftEye.y) - 30)
            worst = max(worst, abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b))
        }
        var natural = 0
        for dx in stride(from: 40, to: 110, by: 1) {
            let a = plain.pixel(Int(f.leftEye.x) - dx, Int(f.leftEye.y) - 30), b = plain.pixel(Int(f.leftEye.x) - dx - 1, Int(f.leftEye.y) - 30)
            natural = max(natural, abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b))
        }
        XCTAssertLessThanOrEqual(worst, natural + 40, "no seam where the warp ends")
    }
}
