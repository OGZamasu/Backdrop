import AppKit
import CoreMediaIO
import CoreVideo
import Foundation
import os

/// Written to the system log (subsystem is the extension's own bundle ID) so that "the camera isn't there" can be traced:
/// `log show --predicate 'subsystem CONTAINS "backdrop"' --last 5m`.
let extensionLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.backdrop.camera", category: "extension")

// These identifiers are shared with the app (VirtualCameraSink.swift). Change both together.
private let deviceUUID = UUID(uuidString: "5D8B2A40-7C2E-4F8E-9D3A-BA0C4D2E6F11")!
private let sourceStreamUUID = UUID(uuidString: "5D8B2A40-7C2E-4F8E-9D3A-BA0C4D2E6F12")!
private let sinkStreamUUID = UUID(uuidString: "5D8B2A40-7C2E-4F8E-9D3A-BA0C4D2E6F13")!

private let width: Int32 = 1280
private let height: Int32 = 720
private let framesPerSecond: Int32 = 60
private let frameDuration = CMTime(value: 1, timescale: framesPerSecond)
/// How long to keep showing the last picture when the app goes quiet, before saying the app is off. A brief stall
/// (a busy GPU, a hiccup) should look like a frozen frame, not like Backdrop quit.
private let holdLastFrame: UInt64 = 2_500_000_000

// MARK: - Provider

final class ProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: DeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = DeviceSource(localizedName: "Backdrop Camera")
        do {
            try provider.addDevice(deviceSource.device)
            extensionLog.notice("added the Backdrop Camera device")
        } catch {
            extensionLog.fault("failed to add the device: \(error.localizedDescription, privacy: .public)")
            fatalError("Failed to add device: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {
        extensionLog.notice("client connected: pid \(client.pid, privacy: .public)")
    }

    func disconnect(from client: CMIOExtensionClient) {
        extensionLog.notice("client disconnected: pid \(client.pid, privacy: .public)")
    }

    var availableProperties: Set<CMIOExtensionProperty> { [.providerManufacturer] }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let state = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) { state.manufacturer = "Backdrop" }
        return state
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}

// MARK: - Device

/// One camera with two streams. The app pushes finished frames into the sink; we pass them on to the source,
/// which is the stream other apps see. When the app isn't running we show a card saying how to turn it on.
final class DeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private var source: StreamSource!
    private var sink: StreamSource!

    private let queue = DispatchQueue(label: "app.backdrop.camera.frames", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var sourceClients = 0
    private var sinkRunning = false
    private var lastAppFrame = DispatchTime(uptimeNanoseconds: 0)
    private var lastSend: UInt64 = 0
    private var lastImage: CVImageBuffer?
    private var lastFormat: CMVideoFormatDescription?

    private let placeholder: CVPixelBuffer
    private let placeholderFormat: CMVideoFormatDescription

    init(localizedName: String) {
        var description: CMVideoFormatDescription!
        CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCVPixelFormatType_32BGRA,
                                       width: width, height: height, extensions: nil, formatDescriptionOut: &description)
        placeholderFormat = description
        placeholder = Self.makePlaceholder()
        super.init()

        device = CMIOExtensionDevice(localizedName: localizedName, deviceID: deviceUUID,
                                     legacyDeviceID: deviceUUID.uuidString, source: self)

        // The format's frame-rate range and the stream's reported frame duration must agree, or the extension
        // fails to start and the camera disappears.
        let format = CMIOExtensionStreamFormat(formatDescription: description,
                                               maxFrameDuration: frameDuration, minFrameDuration: frameDuration,
                                               validFrameDurations: nil)
        source = StreamSource(owner: self, direction: .source, formats: [format])
        sink = StreamSource(owner: self, direction: .sink, formats: [format])
        source.stream = CMIOExtensionStream(localizedName: localizedName, streamID: sourceStreamUUID,
                                            direction: .source, clockType: .hostTime, source: source)
        sink.stream = CMIOExtensionStream(localizedName: "\(localizedName) Input", streamID: sinkStreamUUID,
                                          direction: .sink, clockType: .hostTime, source: sink)
        do {
            try device.addStream(source.stream)
            try device.addStream(sink.stream)
        } catch {
            fatalError("Failed to add streams: \(error.localizedDescription)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> { [.deviceTransportType, .deviceModel] }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let state = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) { state.transportType = 0x7669_7274 } // 'virt'
        if properties.contains(.deviceModel) { state.model = "Backdrop Camera" }
        return state
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    // MARK: Source side (what other apps watch)

    func sourceDidStart() {
        queue.async {
            self.sourceClients += 1
            extensionLog.notice("someone is watching (\(self.sourceClients, privacy: .public))")
            guard self.timer == nil else { return }
            // Keeps the picture alive when the app is off or between frames.
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .nanoseconds(Int(1_000_000_000 / Int(framesPerSecond))), leeway: .milliseconds(2))
            timer.setEventHandler { self.tick() }
            timer.resume()
            self.timer = timer
        }
    }

    func sourceDidStop() {
        queue.async {
            self.sourceClients = max(0, self.sourceClients - 1)
            extensionLog.notice("someone stopped watching (\(self.sourceClients, privacy: .public) left)")
            if self.sourceClients == 0 {
                self.timer?.cancel()
                self.timer = nil
            }
        }
    }

    /// Runs 60 times a second while anyone is watching.
    ///
    /// This camera promises 60 fps: that is what stops macOS offering its own Background and Portrait effects on it.
    /// The app delivers about 30 real frames a second, so each one goes out the moment it arrives and the latest is
    /// repeated to fill the gap before the next. When the app is off, a card says so instead.
    private func tick() {
        let now = DispatchTime.now().uptimeNanoseconds
        let image: CVImageBuffer
        let format: CMVideoFormatDescription

        if now &- lastAppFrame.uptimeNanoseconds > holdLastFrame {
            image = placeholder
            format = placeholderFormat
        } else if let lastImage, let lastFormat, now &- lastSend >= 14_000_000 {
            image = lastImage
            format = lastFormat
        } else {
            return
        }

        var timing = CMSampleTimingInfo(duration: frameDuration, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image,
                                                 formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample)
        if let sample {
            lastSend = now
            source.stream.send(sample, discontinuity: [], hostTimeInNanoseconds: UInt64(timing.presentationTimeStamp.seconds * Double(NSEC_PER_SEC)))
        }
    }

    // MARK: Sink side (what the app writes to)

    func sinkDidStart(client: CMIOExtensionClient) {
        queue.async {
            self.sinkRunning = true
            extensionLog.notice("the app started sending frames (pid \(client.pid, privacy: .public))")
            self.pull(from: client)
        }
    }

    func sinkDidStop() {
        queue.async {
            self.sinkRunning = false
            extensionLog.notice("the app stopped sending frames")
        }
    }

    private func pull(from client: CMIOExtensionClient) {
        guard sinkRunning else { return }
        sink.stream.consumeSampleBuffer(from: client) { [weak self] sample, sequence, _, _, error in
            guard let self else { return }
            self.queue.async {
                guard self.sinkRunning else { return }
                if let sample, error == nil {
                    self.lastAppFrame = DispatchTime.now()
                    self.lastImage = CMSampleBufferGetImageBuffer(sample)
                    self.lastFormat = CMSampleBufferGetFormatDescription(sample)
                    let nanoseconds = UInt64(max(0, sample.presentationTimeStamp.seconds) * Double(NSEC_PER_SEC))
                    if self.sourceClients > 0 {
                        self.lastSend = self.lastAppFrame.uptimeNanoseconds
                        self.source.stream.send(sample, discontinuity: [], hostTimeInNanoseconds: nanoseconds)
                    }
                    self.sink.stream.notifyScheduledOutputChanged(CMIOExtensionScheduledOutput(sequenceNumber: sequence, hostTimeInNanoseconds: nanoseconds))
                    self.pull(from: client)
                } else {
                    // Nothing ready yet. Check again shortly rather than spinning.
                    self.queue.asyncAfter(deadline: .now() + .milliseconds(5)) { self.pull(from: client) }
                }
            }
        }
    }

    // MARK: Placeholder

    private static func makePlaceholder() -> CVPixelBuffer {
        var buffer: CVPixelBuffer!
        CVPixelBufferCreate(kCFAllocatorDefault, Int(width), Int(height), kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]] as CFDictionary, &buffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmap = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(width), height: Int(height), bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space, bitmapInfo: bitmap) else { return buffer }

        context.setFillColor(CGColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: Int(width), height: Int(height)))

        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let title = NSAttributedString(string: "Backdrop is off", attributes: [
            .font: NSFont.systemFont(ofSize: 54, weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
        let detail = NSAttributedString(string: "Turn the camera on from the Backdrop menu bar icon", attributes: [
            .font: NSFont.systemFont(ofSize: 28, weight: .regular), .foregroundColor: NSColor(white: 1, alpha: 0.6), .paragraphStyle: paragraph])
        title.draw(in: CGRect(x: 0, y: 340, width: CGFloat(width), height: 70))
        detail.draw(in: CGRect(x: 0, y: 285, width: CGFloat(width), height: 40))
        NSGraphicsContext.restoreGraphicsState()
        return buffer
    }
}

// MARK: - Streams

final class StreamSource: NSObject, CMIOExtensionStreamSource {
    var stream: CMIOExtensionStream!

    private unowned let owner: DeviceSource
    private let direction: CMIOExtensionStream.Direction
    private let allFormats: [CMIOExtensionStreamFormat]
    private var sinkClient: CMIOExtensionClient?

    init(owner: DeviceSource, direction: CMIOExtensionStream.Direction, formats: [CMIOExtensionStreamFormat]) {
        self.owner = owner
        self.direction = direction
        allFormats = formats
    }

    var formats: [CMIOExtensionStreamFormat] { allFormats }

    var availableProperties: Set<CMIOExtensionProperty> {
        var properties: Set<CMIOExtensionProperty> = [.streamActiveFormatIndex, .streamFrameDuration]
        if direction == .sink {
            properties.formUnion([.streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup,
                                  .streamSinkBufferUnderrunCount, .streamSinkEndOfData])
        }
        return properties
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let state = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) { state.activeFormatIndex = 0 }
        if properties.contains(.streamFrameDuration) { state.frameDuration = frameDuration }
        if direction == .sink {
            if properties.contains(.streamSinkBufferQueueSize) { state.sinkBufferQueueSize = 3 }
            if properties.contains(.streamSinkBuffersRequiredForStartup) { state.sinkBuffersRequiredForStartup = 1 }
        }
        return state
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        if direction == .sink { sinkClient = client }
        return true
    }

    func startStream() throws {
        switch direction {
        case .source: owner.sourceDidStart()
        case .sink: if let sinkClient { owner.sinkDidStart(client: sinkClient) }
        @unknown default: break
        }
    }

    func stopStream() throws {
        switch direction {
        case .source: owner.sourceDidStop()
        case .sink: owner.sinkDidStop()
        @unknown default: break
        }
    }
}
