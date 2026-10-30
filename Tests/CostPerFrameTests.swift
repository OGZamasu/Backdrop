import CoreImage
import CoreMedia
import CoreML
import Darwin
import Metal
import QuartzCore
import Vision
import XCTest

/// What this process has used so far, from the kernel's own accounting: the same numbers Activity Monitor shows.
/// Neural Engine time is not billed to the process, so work that moves there shows up as CPU and GPU time going away.
struct ProcessUsage {
    var cpu = 0.0          // seconds, all threads
    var gpu = 0.0          // seconds of GPU time billed to this process
    var energy = 0.0       // joules, CPU only (the kernel's estimate)
    var wakeups = 0.0      // interrupt and package-idle wakeups
    var neuralFootprint = 0.0 // MB of Neural Engine memory this process holds
    /// Millions of instructions retired, all threads. Unlike CPU time it doesn't depend on which core ran the work or how
    /// fast it was clocked, so it stays put on a busy machine.
    var instructions = 0.0
    /// MB of memory the process holds (what Activity Monitor calls Memory).
    var footprint = 0.0

    static func now() -> ProcessUsage {
        var usage = ProcessUsage()
        var ts = timespec()
        clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts)
        usage.cpu = Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9

        var info = rusage_info_v6()
        let ok = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V6, $0) }
        }
        if ok == 0 {
            usage.energy = Double(info.ri_energy_nj) / 1e9
            usage.wakeups = Double(info.ri_interrupt_wkups + info.ri_pkg_idle_wkups)
            usage.neuralFootprint = Double(info.ri_neural_footprint) / 1_048_576
            usage.instructions = Double(info.ri_instructions) / 1e6
            usage.footprint = Double(info.ri_phys_footprint) / 1_048_576
        }

        usage.gpuClients = gpuClients()
        return usage
    }

    /// GPU time per Metal client of this process. Clients come and go (a CIContext, Vision's own), so a difference is only
    /// taken over clients alive at both ends; one that closed in between is left out rather than counted negative.
    var gpuClients: [String: Double] = [:]

    /// GPU time the graphics driver has billed to this process (what Activity Monitor's GPU Time column shows), read from
    /// the driver's per-client counters in the I/O Registry. The kernel's own task counter stays at zero on this hardware.
    static func gpuClients() -> [String: Double] {
        let ioreg = Process()
        ioreg.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        ioreg.arguments = ["-r", "-c", "AGXDeviceUserClient", "-l", "-w", "0"]
        let pipe = Pipe()
        ioreg.standardOutput = pipe
        guard (try? ioreg.run()) != nil else { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ioreg.waitUntilExit()
        let me = "\"pid \(getpid()),"
        // Each client's "AppUsage" line comes before the line naming the process that owns it.
        var client = "", pending = 0.0, clients: [String: Double] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            if let range = line.range(of: ", id 0x") { client = String(line[range.upperBound...].prefix { $0.isHexDigit }); pending = 0; continue }
            if line.contains("accumulatedGPUTime") {
                for part in line.split(separator: "accumulatedGPUTime\"=").dropFirst() { pending += Double(part.prefix { $0.isNumber }) ?? 0 }
            } else if line.contains("\"IOUserClientCreator\""), line.contains(me) {
                clients[client] = pending / 1e9
            }
        }
        return clients
    }

    static func - (a: ProcessUsage, b: ProcessUsage) -> ProcessUsage {
        let gpu = a.gpuClients.reduce(0.0) { sum, client in sum + max(0, client.value - (b.gpuClients[client.key] ?? 0)) }
        return ProcessUsage(cpu: a.cpu - b.cpu, gpu: gpu, energy: a.energy - b.energy, wakeups: a.wakeups - b.wakeups,
                            neuralFootprint: a.neuralFootprint, instructions: a.instructions - b.instructions, footprint: a.footprint)
    }
}

/// The cost of each delivered frame at the camera's real pace (30 a second), not flat out: CPU and GPU time, CPU energy,
/// wakeups and latency. Opt-in, like the other timing tests: TEST_RUNNER_BACKDROP_PERF=1.
final class CostPerFrameTests: XCTestCase {
    private var perf: Bool { ProcessInfo.processInfo.environment["BACKDROP_PERF"] != nil }

    /// A person who moves a little from frame to frame, so nothing downstream can coast on an unchanged picture.
    private lazy var cameras: [CVPixelBuffer] = {
        let context = CIContext()
        return (Self.photoFrames(context: context)
            ?? (0..<8).map { k in SyntheticScene(center: CGPoint(x: 600 + 10 * Double(k), y: 420)).cameraBuffer() }).map(Self.tagLikeCamera)
    }()

    /// Frames from AVFoundation carry their colour description on the buffer. Without it, Core Image and Vision go and ask
    /// the IOSurface instead, a kernel call per frame that the app never pays, so the measurements would be too high.
    static func tagLikeCamera(_ buffer: CVPixelBuffer) -> CVPixelBuffer {
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        return buffer
    }

    /// Marks a buffer as rewritten, as a camera does when it reuses one for a new frame, so Core Image can't serve a result it
    /// cached from the last time the buffer came round. (A test that cycles a few fixed frames would otherwise flatter itself.)
    static func freshen(_ buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        CVPixelBufferUnlockBaseAddress(buffer, [])
    }

    /// The cartoon in SyntheticScene isn't a person to Vision (its cutout comes back empty), so the cost of a real cutout and
    /// any comparison of mattes needs a photo of someone: BACKDROP_PERSON_PHOTO=<path> (not kept in the repository).
    /// Eight frames panning across it a few pixels at a time, so it moves like someone on a call.
    static func photoFrames(context: CIContext) -> [CVPixelBuffer]? {
        guard let path = ProcessInfo.processInfo.environment["BACKDROP_PERSON_PHOTO"],
              let photo = CIImage(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let filled = photo.transformed(by: Compositor.fillTransform(photo.extent, into: rect.insetBy(dx: -40, dy: -24)))
        return (0..<8).map { k in
            var created: CVPixelBuffer?
            CVPixelBufferCreate(nil, 1280, 720, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]] as CFDictionary, &created)
            let shift = CGFloat(k) * 6 - 21
            context.render(filled.transformed(by: CGAffineTransform(translationX: shift, y: 0)).cropped(to: rect), to: created!)
            return created!
        }
    }

    private struct Run {
        var fps = 0.0, cpu = 0.0, gpu = 0.0, energy = 0.0, wakeups = 0.0, latency = 0.0, latency95 = 0.0, instructions = 0.0, footprint = 0.0
    }

    /// Feeds frames at 30 a second for `seconds`, after a warm-up, and divides what the process used by the frames that came out.
    private func paced(seconds: Double = 6, _ configure: (FramePipeline) -> Void) -> Run {
        let pipeline = FramePipeline()
        configure(pipeline)
        let lock = NSLock()
        var submitted: [Int64: CFTimeInterval] = [:]
        var latencies: [Double] = []
        var outputs = 0
        pipeline.onOutput = { _, time in
            let now = CACurrentMediaTime()
            lock.withLock {
                outputs += 1
                if let at = submitted.removeValue(forKey: time.value) { latencies.append(now - at) }
            }
        }
        let feeder = DispatchQueue(label: "feeder", qos: .userInteractive)
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: feeder)
        var k: Int64 = 0
        let cameras = self.cameras
        timer.schedule(deadline: .now(), repeating: .nanoseconds(33_333_333), leeway: .microseconds(500))
        timer.setEventHandler {
            k += 1
            let frame = k
            let camera = cameras[Int(frame) % cameras.count]
            Self.freshen(camera)
            lock.withLock { submitted[frame] = CACurrentMediaTime() }
            pipeline.queue.async { pipeline.submit(camera, at: CMTime(value: frame, timescale: 30)) }
        }
        timer.resume()
        Thread.sleep(forTimeInterval: 2)
        lock.withLock { outputs = 0; latencies = [] }
        let before = ProcessUsage.now(), start = CACurrentMediaTime()
        Thread.sleep(forTimeInterval: seconds)
        let used = ProcessUsage.now() - before, elapsed = CACurrentMediaTime() - start
        let (made, lat) = lock.withLock { (outputs, latencies) }
        timer.cancel()
        feeder.sync {}
        pipeline.queue.sync {}
        Thread.sleep(forTimeInterval: 0.2)
        pipeline.queue.sync {}

        let n = Double(max(made, 1))
        let sorted = lat.sorted()
        return Run(fps: Double(made) / elapsed, cpu: used.cpu / n * 1000, gpu: used.gpu / n * 1000, energy: used.energy / n * 1000,
                   wakeups: used.wakeups / n, latency: sorted.reduce(0, +) / Double(max(sorted.count, 1)) * 1000,
                   latency95: sorted.isEmpty ? 0 : sorted[Int(Double(sorted.count - 1) * 0.95)] * 1000, instructions: used.instructions / n, footprint: used.footprint)
    }

    private func report(_ name: String, _ r: Run) {
        print(String(format: "COST %-34@ %4.1f fps | per frame: CPU %5.2f ms  %5.1f M instr  GPU %5.2f ms  CPU energy %5.2f mJ  wakeups %4.1f | latency %5.1f ms (p95 %5.1f) | memory %.0f MB",
                     name as NSString, r.fps, r.cpu, r.instructions, r.gpu, r.energy, r.wakeups, r.latency, r.latency95, r.footprint))
    }

    private func softBlur(_ pipeline: FramePipeline) {
        pipeline.setBackground(.softBlur, source: BlurSource(radius: 14))
    }

    func testCostPerFrameAtThirtyFramesASecond() throws {
        try XCTSkipUnless(perf, "set TEST_RUNNER_BACKDROP_PERF=1 to measure")
        let matte = SyntheticScene(center: CGPoint(x: 640, y: 420)).matteBuffer()
        let cases: [(String, (FramePipeline) -> Void)] = [
            ("off (camera straight through)", { $0.setBackground(.off, source: nil) }),
            ("soft blur, no Vision (fixed matte)", { p in self.softBlur(p); p.matteOverride = { _ in matte } }),
            ("soft blur, balanced", { p in self.softBlur(p); p.setQuality(.balanced) }),
            ("soft blur, fast", { p in self.softBlur(p); p.setQuality(.fast) }),
            ("gradient, balanced", { p in
                p.setBackground(Background(id: UUID(), name: "g", kind: .gradient(.aurora), origin: .builtIn), source: GradientSource(preset: .aurora))
            }),
            ("3D pipes, balanced", { $0.setBackground(.pipes, source: PipesSource()) }),
            ("3D maze, balanced", { $0.setBackground(.maze, source: MazeSource()) }),
            ("soft blur, balanced, Aura", { p in self.softBlur(p); p.setLens(LensCatalog.info(for: "aura")!.make()) }),
            ("soft blur, balanced, Breakout", { p in self.softBlur(p); p.setLens(LensCatalog.info(for: "breakout")!.make()) }),
            ("soft blur, balanced, Cat Ears", { p in self.softBlur(p); p.setLens(LensCatalog.info(for: "cat")!.make()) }),
        ]
        let only = ProcessInfo.processInfo.environment["BACKDROP_COST_ONLY"]
        for (name, configure) in cases where only == nil || name.contains(only!) {
            let seconds = ProcessInfo.processInfo.environment["BACKDROP_COST_SECONDS"].flatMap(Double.init) ?? 6
            report(name, paced(seconds: seconds, configure))
        }
    }

    // MARK: Vision

    private func describe(_ device: MLComputeDevice) -> String {
        switch device {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .neuralEngine(let ane): return "ANE(\(ane.totalCoreCount) cores)"
        @unknown default: return "?"
        }
    }

    /// Which processor Vision's person segmentation runs on, what it could run on, and what each costs.
    func testWhereTheCutoutRuns() throws {
        try XCTSkipUnless(perf, "set TEST_RUNNER_BACKDROP_PERF=1 to measure")
        let cameras = self.cameras
        for quality in [VNGeneratePersonSegmentationRequest.QualityLevel.fast, .balanced, .accurate] {
            let probe = VNGeneratePersonSegmentationRequest()
            probe.qualityLevel = quality
            probe.outputPixelFormat = kCVPixelFormatType_OneComponent8
            let supported = try probe.supportedComputeStageDevices
            let listing = supported.map { "\($0.key.rawValue): \($0.value.map(describe).joined(separator: ", "))" }.sorted().joined(separator: " | ")
            print("PROBE quality \(quality.rawValue): supported \(listing); default main = \(probe.computeDevice(for: .main).map(describe) ?? "Vision's choice")")

            var choices: [(String, MLComputeDevice?)] = [("default", nil)]
            for device in supported[.main] ?? [] { choices.append((describe(device), device)) }
            for (label, device) in choices {
                let request = VNGeneratePersonSegmentationRequest()
                request.qualityLevel = quality
                request.outputPixelFormat = kCVPixelFormatType_OneComponent8
                request.setComputeDevice(device, for: .main)
                let handler = VNSequenceRequestHandler()
                var size = "-"
                do {
                    for k in 0..<10 { try handler.perform([request], on: cameras[k % cameras.count]) }
                    let frames = 40
                    let before = ProcessUsage.now(), start = CACurrentMediaTime()
                    for k in 0..<frames {
                        try handler.perform([request], on: cameras[k % cameras.count])
                        if let mask = request.results?.first?.pixelBuffer { size = "\(CVPixelBufferGetWidth(mask))x\(CVPixelBufferGetHeight(mask))" }
                    }
                    let used = ProcessUsage.now() - before, wall = CACurrentMediaTime() - start
                    let n = Double(frames)
                    print(String(format: "PROBE   %-8@ on %-14@ %5.1f ms wall  CPU %5.2f ms  %5.1f M instr  GPU %5.2f ms  CPU energy %5.2f mJ  mask %@  ANE memory %.1f MB",
                                 String(describing: quality.rawValue) as NSString, label as NSString, wall / n * 1000, used.cpu / n * 1000, used.instructions / n,
                                 used.gpu / n * 1000, used.energy / n * 1000, size as NSString, used.neuralFootprint))
                } catch {
                    print("PROBE   \(quality.rawValue) on \(label): failed, \(error.localizedDescription)")
                }
            }
        }
    }

    static func copy(_ mask: CVPixelBuffer) -> CVPixelBuffer {
        var created: CVPixelBuffer?
        let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask)
        CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_OneComponent8, nil, &created)
        let out = created!
        CVPixelBufferLockBaseAddress(mask, .readOnly); CVPixelBufferLockBaseAddress(out, [])
        for y in 0..<h {
            memcpy(CVPixelBufferGetBaseAddress(out)! + y * CVPixelBufferGetBytesPerRow(out),
                   CVPixelBufferGetBaseAddress(mask)! + y * CVPixelBufferGetBytesPerRow(mask), w)
        }
        CVPixelBufferUnlockBaseAddress(mask, .readOnly); CVPixelBufferUnlockBaseAddress(out, [])
        return out
    }

    // MARK: Face tracking

    /// What one look for a face costs as the app does it (a fresh landmarks request, which finds the face first), and when the
    /// face found last time is handed in so Vision can skip straight to the landmarks.
    func testFaceTrackingCost() throws {
        try XCTSkipUnless(perf, "set TEST_RUNNER_BACKDROP_PERF=1 to measure")
        let frames = cameras
        let probe = VNDetectFaceRectanglesRequest()
        let devices = try probe.supportedComputeStageDevices.map { "\($0.key.rawValue): \($0.value.map(describe).joined(separator: ", "))" }
        print("PROBE face rectangles supported devices: \(devices.joined(separator: " | "))")
        for round in 0..<2 {
            var before = ProcessUsage.now(), start = CACurrentMediaTime()
            let n = 40
            var found = 0
            for k in 0..<n {
                let request = VNDetectFaceLandmarksRequest()
                try VNImageRequestHandler(cvPixelBuffer: frames[k % frames.count], orientation: .up, options: [:]).perform([request])
                found += request.results?.isEmpty == false ? 1 : 0
            }
            var used = ProcessUsage.now() - before, wall = CACurrentMediaTime() - start
            print(String(format: "PROBE face round %d as today (detect + landmarks): wall %.1f ms  CPU %.2f ms  %.1f M instr  GPU %.2f ms per look (%d/%d found)",
                         round, wall / Double(n) * 1000, used.cpu / Double(n) * 1000, used.instructions / Double(n), used.gpu / Double(n) * 1000, found, n))
            var last: [VNFaceObservation]?
            before = ProcessUsage.now(); start = CACurrentMediaTime(); found = 0
            for k in 0..<n {
                let request = VNDetectFaceLandmarksRequest()
                if let last { request.inputFaceObservations = last }
                try VNImageRequestHandler(cvPixelBuffer: frames[k % frames.count], orientation: .up, options: [:]).perform([request])
                last = request.results
                found += request.results?.isEmpty == false ? 1 : 0
            }
            used = ProcessUsage.now() - before; wall = CACurrentMediaTime() - start
            print(String(format: "PROBE face round %d reusing last face (landmarks only): wall %.1f ms  CPU %.2f ms  %.1f M instr  GPU %.2f ms per look (%d/%d found)",
                         round, wall / Double(n) * 1000, used.cpu / Double(n) * 1000, used.instructions / Double(n), used.gpu / Double(n) * 1000, found, n))
        }
    }

    // MARK: Lens overlays

    /// Stamps the same 360 sparks and a few emoji the way the lenses do, and keeps the result so two builds can be compared
    /// pixel for pixel (BACKDROP_TEST_OUTPUT/sprites.raw).
    func testSpriteStampingCost() throws {
        try XCTSkipUnless(perf, "set TEST_RUNNER_BACKDROP_PERF=1 to measure")
        let canvas = OverlayCanvas(size: CGSize(width: 1280, height: 720), slots: 1)!
        var rng = SplitMix64(seed: 7)
        let sparks = (0..<360).map { _ in
            (CGPoint(x: Double.random(in: 0..<1280, using: &rng), y: Double.random(in: 0..<720, using: &rng)),
             Double.random(in: 3...11, using: &rng), Double.random(in: 0.05...1, using: &rng), Double.random(in: 0..<1, using: &rng))
        }
        func draw(_ ctx: CGContext) {
            ctx.setBlendMode(.plusLighter)
            for (at, radius, alpha, hue) in sparks {
                let (r, g, b) = Palette.rgb(hue: hue)
                if let dot = Sprites.dot(red: (r * 20).rounded() / 20, green: (g * 20).rounded() / 20, blue: (b * 20).rounded() / 20) {
                    ctx.stampDot(dot, at: at, radius: radius, alpha: alpha)
                }
            }
            ctx.setBlendMode(.normal)
            for (k, emoji) in ["💣", "🍰", "🐤", "❤️"].enumerated() {
                if let sprite = Sprites.emoji(emoji, size: 100) { ctx.draw(sprite, center: CGPoint(x: 200 + 250 * k, y: 360), height: 84, rotation: 0.2) }
            }
        }
        for _ in 0..<10 { draw(canvas.begin()); _ = canvas.image() }
        let before = ProcessUsage.now(), start = CACurrentMediaTime()
        let n = 100
        for _ in 0..<n { draw(canvas.begin()); _ = canvas.image() }
        let used = ProcessUsage.now() - before, wall = CACurrentMediaTime() - start
        print(String(format: "PROBE sprites: 360 dots + 4 emoji: wall %.2f ms  CPU %.2f ms  %.1f M instr per frame",
                     wall / Double(n) * 1000, used.cpu / Double(n) * 1000, used.instructions / Double(n)))
        let image = canvas.image()
        Output.save(image, as: "sprites.png")
        if let folder = ProcessInfo.processInfo.environment["BACKDROP_TEST_OUTPUT"] {
            var bytes = [UInt8](repeating: 0, count: 1280 * 720 * 4)
            CIContext().render(image, toBitmap: &bytes, rowBytes: 1280 * 4, bounds: CGRect(x: 0, y: 0, width: 1280, height: 720),
                               format: .RGBA8, colorSpace: TestSupport.srgb)
            try Data(bytes).write(to: URL(fileURLWithPath: folder).appendingPathComponent("sprites.raw"))
        }
    }

    // MARK: Core Image

    /// The compositor's Core Image context as it was (intermediates not cached) and as it is now (Core Image's default):
    /// CPU, wakeups and GPU per render, and whether the pictures differ at all.
    func testContextOptions() throws {
        try XCTSkipUnless(perf, "set TEST_RUNNER_BACKDROP_PERF=1 to measure")
        let compositor = Compositor()
        let segmenter = PersonSegmenter(quality: .balanced)
        let frames = cameras.map { camera in (camera, Self.copy(segmenter.mask(for: camera)!)) }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let device = MTLCreateSystemDefaultDevice()!
        let configs: [(String, CIContext)] = [("cacheIntermediates false (before)", CIContext(mtlDevice: device, options: [.cacheIntermediates: false])),
                                              ("Core Image's default (after)", CIContext(mtlDevice: device))]
        func frame(_ k: Int) -> CIImage {
            let (camera, mask) = frames[k % frames.count]
            let image = CIImage(cvPixelBuffer: camera)
            let bg = compositor.prepareBackground(BlurSource(radius: 14).frame(at: 0, camera: image)!, fits: false, parallax: nil)
            return compositor.composite(camera: image, matte: compositor.refinedMatte(camera: image, mask: Compositor.matte(from: mask)), background: bg)
        }
        for round in 0..<2 {
            for (name, context) in configs {
                for k in 0..<20 { context.render(frame(k), to: compositor.makeOutputBuffer()!, bounds: compositor.rect, colorSpace: space) }
                let before = ProcessUsage.now(), start = CACurrentMediaTime()
                let n = 90
                for k in 0..<n { context.render(frame(k), to: compositor.makeOutputBuffer()!, bounds: compositor.rect, colorSpace: space) }
                let used = ProcessUsage.now() - before, wall = CACurrentMediaTime() - start
                print(String(format: "PROBE context round %d %-36@ wall %.2f ms  CPU %.2f ms  %.2f M instr  GPU %.2f ms  wakeups %.1f per render",
                             round, name as NSString, wall / Double(n) * 1000, used.cpu / Double(n) * 1000, used.instructions / Double(n),
                             used.gpu / Double(n) * 1000, used.wakeups / Double(n)))
            }
        }
        var worst = 0, differing = 0
        for k in 0..<frames.count {
            let a = compositor.makeOutputBuffer()!, b = compositor.makeOutputBuffer()!
            configs[0].1.render(frame(k), to: a, bounds: compositor.rect, colorSpace: space)
            configs[1].1.render(frame(k), to: b, bounds: compositor.rect, colorSpace: space)
            CVPixelBufferLockBaseAddress(a, .readOnly); CVPixelBufferLockBaseAddress(b, .readOnly)
            let pa = CVPixelBufferGetBaseAddress(a)!.assumingMemoryBound(to: UInt8.self), pb = CVPixelBufferGetBaseAddress(b)!.assumingMemoryBound(to: UInt8.self)
            for i in 0..<CVPixelBufferGetDataSize(a) where pa[i] != pb[i] { worst = max(worst, abs(Int(pa[i]) - Int(pb[i]))); differing += 1 }
            CVPixelBufferUnlockBaseAddress(a, .readOnly); CVPixelBufferUnlockBaseAddress(b, .readOnly)
            if k == 0 { Output.save(CIImage(cvPixelBuffer: a), as: "composite-before.png"); Output.save(CIImage(cvPixelBuffer: b), as: "composite-after.png") }
        }
        print("PROBE context: largest difference between the two pictures, 0...255: \(worst), in \(differing) of \(frames.count * 1280 * 720 * 4) bytes")
        XCTAssertLessThanOrEqual(worst, 1, "caching intermediates must not change the picture beyond rounding")
    }

    /// A camera hands out the same few buffers over and over with new pictures in them. With intermediates cached, Core Image
    /// must still notice that a buffer it has seen before holds something new, whether the GPU or the CPU wrote it.
    func testCachedContextSeesNewPicturesInARecycledBuffer() throws {
        let context = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!)
        let writer = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!, options: [.cacheIntermediates: false])
        let camera = TestSupport.cameraBuffer(r: 255, g: 0, b: 0)
        let compositor = Compositor()
        func blurredCentre() -> RGB {
            let out = compositor.makeOutputBuffer()!
            let image = CIImage(cvPixelBuffer: camera)
            context.render(BlurSource(radius: 14).frame(at: 0, camera: image)!, to: out, bounds: compositor.rect, colorSpace: TestSupport.srgb)
            return TestSupport.pixel(out, x: 640, y: 360)
        }
        assertColor(blurredCentre(), (255, 0, 0))
        let seed = IOSurfaceGetSeed(CVPixelBufferGetIOSurface(camera)!.takeUnretainedValue())
        writer.render(TestSupport.solid(0, 0, 1), to: camera, bounds: compositor.rect, colorSpace: TestSupport.srgb)     // the GPU writes it
        print("PROBE IOSurface seed \(seed) -> \(IOSurfaceGetSeed(CVPixelBufferGetIOSurface(camera)!.takeUnretainedValue())) after a GPU write")
        assertColor(blurredCentre(), (0, 0, 255), "a GPU write into a recycled buffer is seen")
        let filled = TestSupport.cameraBuffer(r: 0, g: 255, b: 0)                                                     // the CPU writes it
        CVPixelBufferLockBaseAddress(camera, []); CVPixelBufferLockBaseAddress(filled, .readOnly)
        memcpy(CVPixelBufferGetBaseAddress(camera)!, CVPixelBufferGetBaseAddress(filled)!, CVPixelBufferGetDataSize(camera))
        CVPixelBufferUnlockBaseAddress(filled, .readOnly); CVPixelBufferUnlockBaseAddress(camera, [])
        assertColor(blurredCentre(), (0, 255, 0), "a CPU write into a recycled buffer is seen")
        let surface = CVPixelBufferGetIOSurface(camera)!.takeUnretainedValue(), was = IOSurfaceGetSeed(surface)
        Self.freshen(camera)
        XCTAssertNotEqual(IOSurfaceGetSeed(surface), was, "freshen() marks the buffer as rewritten")
    }

    /// GPU time, passes and pixels for one composited frame, read from Core Image's own render report.
    func testCompositingGraphCost() throws {
        try XCTSkipUnless(perf, "set TEST_RUNNER_BACKDROP_PERF=1 to measure")
        let compositor = Compositor()
        let mask = PersonSegmenter(quality: .balanced).mask(for: cameras[0])!
        let output = compositor.makeOutputBuffer()!
        let destination = CIRenderDestination(pixelBuffer: output)
        destination.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        let camera = CIImage(cvPixelBuffer: cameras[0])
        let blur = BlurSource(radius: 14).frame(at: 0, camera: camera)!

        /// `make` gets the camera and matte afresh each time, as new frames, so nothing is served from Core Image's cache.
        func measure(_ name: String, _ make: (CIImage, CIImage) -> CIImage) {
            func frame() -> CIImage {
                Self.freshen(cameras[0]); Self.freshen(mask)
                return make(CIImage(cvPixelBuffer: cameras[0]), Compositor.matte(from: mask))
            }
            var gpu: [Double] = [], passes = 0, pixels = 0
            for k in 0..<40 {
                guard let task = try? compositor.context.startTask(toRender: frame(), from: compositor.rect, to: destination, at: .zero),
                      let info = try? task.waitUntilCompleted() else { continue }
                if k >= 10 { gpu.append(info.kernelExecutionTime * 1000); passes = info.passCount; pixels = info.pixelsProcessed }
            }
            gpu.sort()
            // The way the pipeline renders: synchronously, into the output buffer. What that costs the CPU and how often it wakes.
            let before = ProcessUsage.now()
            for _ in 0..<60 { compositor.render(frame(), into: output) }
            let used = ProcessUsage.now() - before
            print(String(format: "PROBE CI %-34@ GPU %.2f ms (median, min %.2f)  %2d passes  %5.1f Mpx | render(): CPU %.2f ms  %.1f M instr  wakeups %.1f",
                         name as NSString, gpu[gpu.count / 2], gpu.first ?? 0, passes, Double(pixels) / 1e6, used.cpu / 60 * 1000,
                         used.instructions / 60, used.wakeups / 60))
        }

        let params = CompositeParameters()
        var plain = params; plain.lightWrap = 0; plain.colorMatch = 0
        func look(_ p: CompositeParameters, gradient: Bool = false) -> (CIImage, CIImage) -> CIImage {
            { camera, matte in
                let source = gradient ? GradientSource(preset: .aurora).frame(at: 0, camera: camera)! : BlurSource(radius: 14).frame(at: 0, camera: camera)!
                let bg = compositor.prepareBackground(source, fits: false, parallax: nil)
                return compositor.composite(camera: camera, matte: compositor.refinedMatte(camera: camera, mask: matte, params: p), background: bg, params: p)
            }
        }
        measure("camera only (Off)") { camera, _ in compositor.fitted(camera) }
        measure("soft blur background alone") { camera, _ in
            compositor.prepareBackground(BlurSource(radius: 14).frame(at: 0, camera: camera)!, fits: false, parallax: nil)
        }
        measure("refined matte alone") { camera, matte in compositor.refinedMatte(camera: camera, mask: matte, params: params) }
        measure("soft blur, full look", look(params))
        measure("soft blur, no light wrap or tint", look(plain))
        measure("gradient, full look", look(params, gradient: true))

        // The colour sample: a synchronous read-back that re-renders the background.
        var times: [Double] = []
        for _ in 0..<30 {
            let start = CACurrentMediaTime()
            let average = blur.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: blur.extent)])
            var pixel = [Float](repeating: 0, count: 4)
            compositor.context.render(average, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                      format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            times.append((CACurrentMediaTime() - start) * 1000)
        }
        times.sort()
        print(String(format: "PROBE CI colour sample (CIAreaAverage read-back)          wall %.2f ms median", times[times.count / 2]))

        // The preview: half size, read back into a CGImage.
        times = []
        for _ in 0..<30 {
            let start = CACurrentMediaTime()
            let half = CIImage(cvPixelBuffer: output).transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
            _ = compositor.context.createCGImage(half, from: half.extent)
            times.append((CACurrentMediaTime() - start) * 1000)
        }
        times.sort()
        print(String(format: "PROBE CI preview CGImage (half size read-back)            wall %.2f ms median", times[times.count / 2]))

        // The temporal blend on the CPU, at the matte's own size.
        let smoother = MaskSmoother()
        _ = smoother.smooth(mask)
        let start = CACurrentMediaTime()
        for _ in 0..<200 { _ = smoother.smooth(mask) }
        print(String(format: "PROBE MaskSmoother on the CPU at %dx%d                    %.3f ms per frame",
                     CVPixelBufferGetWidth(mask), CVPixelBufferGetHeight(mask), (CACurrentMediaTime() - start) / 200 * 1000))
    }
}
