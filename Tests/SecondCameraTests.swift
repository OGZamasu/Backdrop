import AppKit
import AVFoundation
import CoreImage
import XCTest

/// A second camera: which cameras are offered, how one is saved, how the source behaves with and without a camera, and the cards
/// viewers see. None of it needs a real second camera; the capture itself is only checked for what it refuses to do.
final class ExtraCamerasTests: XCTestCase {
    private func cam(_ id: String, _ name: String, _ kind: CameraChoice.Kind = .external) -> CameraChoice {
        CameraChoice(id: id, name: name, kind: kind)
    }

    func testTheMainCameraAndBackdropsOwnAreLeftOut() {
        let found = [cam("a", "FaceTime HD Camera", .builtIn), cam("b", "Desk Cam"), cam("c", CameraCapture.virtualCameraName)]
        XCTAssertEqual(ExtraCameras.choices(from: found, excluding: "a").map(\.id), ["b"], "the main camera is left out, and so is our own")
        XCTAssertEqual(ExtraCameras.choices(from: found, excluding: nil).map(\.id), ["a", "b"], "with no main camera, only ours is left out")
    }

    func testOrderIsBuiltInThenPhoneThenDeskViewThenTheRestByName() {
        let found = [cam("1", "Zeta Cam"), cam("2", "Desk View Camera", .deskView), cam("3", "Alpha Cam"),
                     cam("4", "Chris’s iPhone", .iPhone), cam("5", "FaceTime HD Camera", .builtIn)]
        XCTAssertEqual(ExtraCameras.choices(from: found, excluding: nil).map(\.id), ["5", "4", "2", "3", "1"])
    }

    func testTwoCamerasWithTheSameNameCanBothBePicked() {
        let found = [cam("x2", "USB Camera"), cam("x1", "USB Camera"), cam("y", "Other")]
        let names = ExtraCameras.choices(from: found, excluding: nil).map(\.name)
        XCTAssertEqual(names.filter { $0.hasPrefix("USB Camera") }.sorted(), ["USB Camera (1)", "USB Camera (2)"])
        XCTAssertTrue(names.contains("Other"), "a name that is not repeated stays as it is")
    }

    func testTheSameCameraListedTwiceAppearsOnce() {
        let found = [cam("a", "Desk Cam"), cam("a", "Desk Cam")]
        XCTAssertEqual(ExtraCameras.choices(from: found, excluding: nil).count, 1)
    }

    func testKindsComeFromTheDeviceType() {
        XCTAssertEqual(ExtraCameras.kind(of: .builtInWideAngleCamera), .builtIn)
        XCTAssertEqual(ExtraCameras.kind(of: .continuityCamera), .iPhone)
        XCTAssertEqual(ExtraCameras.kind(of: .deskViewCamera), .deskView)
        XCTAssertEqual(ExtraCameras.kind(of: .external), .external)
        for kind in [CameraChoice.Kind.builtIn, .iPhone, .deskView, .external] {
            XCTAssertFalse(kind.label.isEmpty)
            XCTAssertNotNil(NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil), "\(kind) needs a real symbol")
        }
    }

    func testNoCamerasMeansNoMainCamera() {
        XCTAssertNil(ExtraCameras.mainCameraID(selected: "gone", available: []))
        XCTAssertNil(ExtraCameras.mainCameraID(selected: nil, available: []))
    }

    func testACameraThatIsNotPluggedInIsNotPresent() {
        XCTAssertFalse(ExtraCameras.isPresent("no-such-camera-\(UUID().uuidString)"))
    }
}

final class SecondCameraBackgroundTests: XCTestCase {
    func testItIsSavedAndLoadedLikeAnyOtherBackground() throws {
        let kind = BackgroundKind.camera(deviceID: "0x1420000046d0825")
        let data = try JSONEncoder().encode(Background(id: UUID(), name: "Desk Cam", kind: kind, origin: .imported))
        XCTAssertEqual(try JSONDecoder().decode(Background.self, from: data).kind, kind)
    }

    func testOnlyScreensAndWindowsCountAsSharingYourScreen() {
        func background(_ kind: BackgroundKind) -> Background { Background(id: UUID(), name: "x", kind: kind, origin: .imported) }
        let camera = background(.camera(deviceID: "cam"))
        XCTAssertTrue(camera.isStageContent, "Present arranges a second camera")
        XCTAssertFalse(camera.isScreenShare, "but it is not your screen going out")
        XCTAssertTrue(camera.isLive)
        for shared in [BackgroundKind.window(bundleID: "a.b", title: nil), .display, .screen(displayID: 2)] {
            XCTAssertTrue(background(shared).isStageContent)
            XCTAssertTrue(background(shared).isScreenShare)
        }
        for plain in [BackgroundKind.passthrough, .blur(radius: 14), .pipes, .solid(hex: "336699", lit: true)] {
            XCTAssertFalse(background(plain).isStageContent, "\(plain)")
        }
    }

    @MainActor
    func testChoosingTheSameCameraAgainDoesNotPileUpCopiesAndKeepsTheNewestName() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("backdrop-camera-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BackgroundLibrary(directory: directory)
        let first = library.addCamera(deviceID: "cam-1", name: "Desk Cam")
        let again = library.addCamera(deviceID: "cam-1", name: "Desk Cam (renamed by its maker)")
        let other = library.addCamera(deviceID: "cam-2", name: "Room Cam")
        XCTAssertEqual(first.id, again.id)
        XCTAssertNotEqual(first.id, other.id)
        XCTAssertEqual(library.background(withID: first.id)?.name, "Desk Cam (renamed by its maker)")
        XCTAssertEqual(library.userItems.filter { if case .camera = $0.kind { return true } else { return false } }.count, 2)

        let reloaded = BackgroundLibrary(directory: directory)
        XCTAssertEqual(reloaded.background(withID: first.id)?.kind, .camera(deviceID: "cam-1"), "it is still there after a relaunch")
    }

    func testTheFactoryMakesASecondCameraSourceThatWaitsForTheCamera() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("backdrop-camera-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let background = Background(id: UUID(), name: "Desk Cam", kind: .camera(deviceID: "cam-1"), origin: .imported)
        let source = await MainActor.run { BackgroundSourceFactory.make(for: background, library: BackgroundLibrary(directory: directory)) }
        let camera = try XCTUnwrap(source as? ExtraCameraSource)
        XCTAssertEqual(camera.deviceID, "cam-1")
        XCTAssertTrue(camera.needsLiveCamera)
        XCTAssertTrue(camera.fitsContent, "a tall phone picture is shown whole")
    }
}

final class ExtraCameraSourceTests: XCTestCase {
    func testItStartsWaitingThenIsLiveWhenFramesComeAndLostWhenTheyStop() {
        let source = ExtraCameraSource(deviceID: "desk-cam")
        XCTAssertEqual(source.status, .starting)
        XCTAssertNil(source.frame(at: 0, camera: CIImage.empty()))

        source.receive(StageFixtures.buffer(.slide))
        XCTAssertEqual(source.status, .live)

        source.setLost(true)
        XCTAssertEqual(source.status, .lost, "unplugged")
        XCTAssertNotNil(source.frame(at: 0, camera: CIImage.empty()), "the last picture is kept, for the card to blur")

        source.receive(StageFixtures.buffer(.slide))
        XCTAssertEqual(source.status, .live, "a frame arriving means it is back")
    }

    func testPausingClosesItButKeepsTheLastPicture() {
        let source = ExtraCameraSource(deviceID: "desk-cam")
        source.receive(StageFixtures.buffer(.slide))
        source.setPaused(true)
        XCTAssertEqual(source.status, .paused)
        XCTAssertNotNil(source.frame(at: 0, camera: CIImage.empty()))
        source.setLost(true)
        XCTAssertEqual(source.status, .paused, "paused is what viewers are told, whatever the camera is doing")
        source.setPaused(false)
        XCTAssertEqual(source.status, .lost)
        source.receive(StageFixtures.buffer(.slide))
        XCTAssertEqual(source.status, .live)
    }

    func testRefusedCameraAccessIsReportedAsNotAllowed() {
        let source = ExtraCameraSource(deviceID: "desk-cam")
        source.receive(StageFixtures.buffer(.slide))
        source.setDenied()
        XCTAssertEqual(source.status, .denied)
    }

    func testFramesAreTheCamerasWholePicture() throws {
        let source = ExtraCameraSource(deviceID: "desk-cam")
        let buffer = StageFixtures.buffer(.tallDocument)
        source.receive(buffer)
        let frame = try XCTUnwrap(source.frame(at: 0, camera: CIImage.empty()))
        XCTAssertEqual(frame.extent.width, CGFloat(CVPixelBufferGetWidth(buffer)))
        XCTAssertEqual(frame.extent.height, CGFloat(CVPixelBufferGetHeight(buffer)))
    }

    func testStoppingForgetsThePicture() {
        let source = ExtraCameraSource(deviceID: "desk-cam")
        source.receive(StageFixtures.buffer(.slide))
        source.stop()
        XCTAssertNil(source.frame(at: 0, camera: CIImage.empty()))
        XCTAssertEqual(source.status, .starting)
    }

    func testASecondCameraNeverQuietlyTurnsIntoAnotherCamera() {
        let capture = CameraCapture(queue: DispatchQueue(label: "test.second-camera"), strict: true)
        let done = expectation(description: "start reports")
        capture.start(deviceID: "no-such-camera-\(UUID().uuidString)") { error in
            if case .noCamera? = error as? CameraCapture.CameraError {} else { XCTFail("expected 'no camera', got \(String(describing: error))") }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        capture.stop()
        XCTAssertFalse(capture.isRunning)
    }
}

/// The pipeline opens a second camera only while Backdrop's own camera is on.
final class SecondCameraPipelineTests: XCTestCase {
    private final class Probe: BackgroundSource {
        let needsLiveCamera: Bool
        private(set) var starts = 0
        private(set) var stops = 0
        init(needsLiveCamera: Bool) { self.needsLiveCamera = needsLiveCamera }
        func start() { starts += 1 }
        func stop() { stops += 1 }
        func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? { nil }
    }

    private func background(_ kind: BackgroundKind) -> Background { Background(id: UUID(), name: "x", kind: kind, origin: .imported) }

    func testItStaysClosedUntilBackdropsCameraIsOnAndClosesWhenItGoesOff() {
        let pipeline = FramePipeline()
        let second = Probe(needsLiveCamera: true)
        pipeline.setBackground(background(.camera(deviceID: "cam")), source: second)
        pipeline.queue.sync {}
        XCTAssertEqual(second.starts, 0, "Backdrop's camera is off, so the second one must not light up")

        pipeline.markStarted()
        pipeline.queue.sync {}
        XCTAssertEqual(second.starts, 1, "it opens when the camera comes on")

        let next = Probe(needsLiveCamera: true)
        pipeline.setBackground(background(.camera(deviceID: "cam-2")), source: next)
        pipeline.queue.sync {}
        XCTAssertEqual(next.starts, 1, "switching to another second camera while running opens it at once")

        pipeline.stop()
        pipeline.queue.sync {}
        XCTAssertGreaterThanOrEqual(next.stops, 1, "turning the camera off closes it")

        let later = Probe(needsLiveCamera: true)
        pipeline.setBackground(background(.camera(deviceID: "cam-3")), source: later)
        pipeline.queue.sync {}
        XCTAssertEqual(later.starts, 0, "and a camera picked while it is off waits again")
    }

    func testEverythingElseStillStartsAtOnce() {
        let pipeline = FramePipeline()
        let window = Probe(needsLiveCamera: false)
        pipeline.setBackground(background(.display), source: window)
        pipeline.queue.sync {}
        XCTAssertEqual(window.starts, 1)
    }

    func testAnArrangedCameraBuildsTheSameStageAsAnArrangedWindow() throws {
        var layout = StageLayout()
        layout = StagePreset.left.apply(to: layout)
        let rig = StageRig(content: .slide, layout: layout, title: "Desk Cam", kind: .camera(deviceID: "cam"))
        rig.run(24)
        let report = try XCTUnwrap(rig.reports.last, "a second camera is reported on like a shared window")
        XCTAssertEqual(report.status, .live)
        XCTAssertGreaterThan(report.aspect, 1)
        XCTAssertNotNil(rig.output)
    }
}

/// Pictures to look at (BACKDROP_TEST_OUTPUT=<folder>), and the words on the cards, which are the only part viewers see when a
/// camera is unplugged.
final class SecondCameraRenderTests: XCTestCase {
    private func pixels(_ image: CIImage) -> [UInt8] {
        let w = Int(image.extent.width), h = Int(image.extent.height)
        var out = [UInt8](repeating: 0, count: w * h * 4)
        Output.context.render(image, toBitmap: &out, rowBytes: w * 4, bounds: image.extent, format: .RGBA8, colorSpace: TestSupport.srgb)
        return out
    }

    func testACameraCardIsNotAWindowCard() {
        let composer = StageComposer(context: Output.context)
        let size = CGSize(width: 640, height: 360)
        for status in [StageContentStatus.lost, .denied] {
            let camera = composer.card(status, kind: .camera, size: size, title: "Desk Cam")
            let window = composer.card(status, kind: .window, size: size, title: "Desk Cam")
            XCTAssertNotEqual(pixels(camera), pixels(window), "\(status) should say camera words and show a camera, not a window")
        }
        let paused = (composer.card(.paused, kind: .camera, size: size, title: "x"), composer.card(.paused, kind: .window, size: size, title: "x"))
        XCTAssertEqual(pixels(paused.0), pixels(paused.1), "paused reads the same for both")
    }

    func testRenderASecondCameraEveryWay() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"] == nil, "set TEST_RUNNER_BACKDROP_TEST_OUTPUT to render")
        var sheet: [(String, CIImage)] = []
        func render(_ name: String, layout: StageLayout, status: StageContentStatus = .live, content: StageFixtures.Content? = .slide) {
            let rig = StageRig(content: content, layout: layout, title: "Desk Cam", kind: .camera(deviceID: "cam"))
            rig.source.status = status
            rig.run(24)
            Output.save(rig.outputImage, as: "second-camera-\(name).png")
            sheet.append((name, rig.outputImage))
        }
        let base = StageLayout()
        render("01-behind-you", layout: base)
        render("02-floating-panel", layout: StagePreset.right.apply(to: base))
        render("03-presenter", layout: StageMemory.starting(.presenter, from: base))
        render("04-lost", layout: StagePreset.right.apply(to: base), status: .lost)
        render("05-denied", layout: StagePreset.right.apply(to: base), status: .denied)
        render("06-lost-behind-you", layout: base, status: .lost)
        render("07-tall-phone-picture", layout: StagePreset.left.apply(to: base), content: .tallDocument)
        render("08-starting", layout: StagePreset.left.apply(to: base), status: .starting, content: nil)

        let cols = 4, cellW = 480, cellH = 300, pad = 16, rows = 2
        let width = cols * cellW + (cols + 1) * pad, height = rows * cellH + (rows + 1) * pad
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: TestSupport.srgb,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (i, item) in sheet.enumerated() {
            let col = i % cols, row = i / cols
            let x = pad + col * (cellW + pad), y = height - (row + 1) * (cellH + pad)
            if let cg = Output.context.createCGImage(item.1, from: CGRect(x: 0, y: 0, width: 1280, height: 720)) {
                ctx.draw(cg, in: CGRect(x: x, y: y + 30, width: cellW, height: 270))
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSAttributedString(string: item.0, attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: NSColor(white: 0.85, alpha: 1)])
                .draw(at: CGPoint(x: x + 2, y: y + 6))
            NSGraphicsContext.restoreGraphicsState()
        }
        if let image = ctx.makeImage() { Output.save(CIImage(cgImage: image), as: "second-camera-contact.png") }
    }
}
