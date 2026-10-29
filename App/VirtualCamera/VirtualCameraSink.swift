import CoreMedia
import CoreMediaIO
import CoreVideo
import os

/// Writes finished frames into the Backdrop Camera extension, which republishes them to other apps.
final class VirtualCameraSink {
    // Shared with the extension (CameraExtension/Provider.swift). Change both together.
    static let deviceUUID = "5D8B2A40-7C2E-4F8E-9D3A-BA0C4D2E6F11"
    static let deviceName = "Backdrop Camera"

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.zamasu.backdrop", category: "virtual-camera")

    private let lock = NSLock()
    private var deviceID = CMIODeviceID(0)
    private var streamID = CMIOStreamID(0)
    private var queue: CMSimpleQueue?
    private var formatDescription: CMVideoFormatDescription?
    private var lastPresence: Bool?

    var isConnected: Bool { lock.withLock { queue != nil } }

    /// Whether the extension is installed and approved. Cheap enough to poll.
    var isDevicePresent: Bool {
        let present = findDevice() != nil
        if present != lastPresence {
            lastPresence = present
            Self.log.info("Backdrop Camera \(present ? "found" : "not found", privacy: .public). Devices: \(self.describeDevices(), privacy: .public)")
        }
        return present
    }

    // MARK: Connecting

    @discardableResult
    func connect() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if queue != nil { return true }
        guard let device = findDevice() else { Self.log.error("connect: device not found"); return false }
        guard let sink = findSinkStream(of: device) else { Self.log.error("connect: no sink stream on device \(device)"); return false }

        var copied: Unmanaged<CMSimpleQueue>?
        let copyStatus = CMIOStreamCopyBufferQueue(sink, { _, _, _ in }, nil, &copied)
        guard copyStatus == noErr, let copied else { Self.log.error("connect: CopyBufferQueue failed (status \(copyStatus))"); return false }
        let newQueue = copied.takeRetainedValue()
        let startStatus = CMIODeviceStartStream(device, sink)
        guard startStatus == noErr else { Self.log.error("connect: StartStream failed (status \(startStatus))"); return false }

        deviceID = device
        streamID = sink
        queue = newQueue
        Self.log.info("connected to sink stream \(sink) on device \(device)")
        return true
    }

    private func describeDevices() -> String {
        objectIDs(of: CMIOObjectID(kCMIOObjectSystemObject), selector: kCMIOHardwarePropertyDevices).map {
            "\(string(of: $0, selector: kCMIOObjectPropertyName) ?? "?") [\(string(of: $0, selector: kCMIODevicePropertyDeviceUID) ?? "?")]"
        }.joined(separator: ", ")
    }

    func disconnect() {
        lock.lock(); defer { lock.unlock() }
        guard queue != nil else { return }
        CMIODeviceStopStream(deviceID, streamID)
        queue = nil
        formatDescription = nil
    }

    // MARK: Sending

    /// Hands a frame to the extension. Drops it if the extension is behind: a late frame is worse than none.
    func send(_ pixelBuffer: CVPixelBuffer, at time: CMTime = CMClockGetTime(CMClockGetHostTimeClock())) {
        lock.lock(); defer { lock.unlock() }
        guard let queue else { return }
        guard CMSimpleQueueGetCount(queue) < CMSimpleQueueGetCapacity(queue) else { return }

        if formatDescription == nil || !CMVideoFormatDescriptionMatchesImageBuffer(formatDescription!, imageBuffer: pixelBuffer) {
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)
        }
        guard let formatDescription else { return }

        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                                                       formatDescription: formatDescription, sampleTiming: &timing,
                                                       sampleBufferOut: &sample) == noErr, let sample else { return }
        // The queue takes ownership of one retain; the extension releases it when it consumes the frame.
        if CMSimpleQueueEnqueue(queue, element: Unmanaged.passRetained(sample).toOpaque()) != noErr {
            Unmanaged.passUnretained(sample).release()
        }
    }

    // MARK: CoreMediaIO lookups

    private func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selector),
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private func objectIDs(of owner: CMIOObjectID, selector: Int) -> [CMIOObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(owner, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(owner, &address, 0, nil, size, &used, &ids) == noErr else { return [] }
        return ids
    }

    private func string(of object: CMIOObjectID, selector: Int) -> String? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, size, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private func findDevice() -> CMIODeviceID? {
        let devices = objectIDs(of: CMIOObjectID(kCMIOObjectSystemObject), selector: kCMIOHardwarePropertyDevices)
        return devices.first { id in
            string(of: id, selector: kCMIODevicePropertyDeviceUID)?.caseInsensitiveCompare(Self.deviceUUID) == .orderedSame
        } ?? devices.first { id in
            string(of: id, selector: kCMIOObjectPropertyName) == Self.deviceName
        }
    }

    /// In CMIO's terms the sink is an *output* stream (direction 0): the client outputs into the device.
    private func findSinkStream(of device: CMIODeviceID) -> CMIOStreamID? {
        let streams = objectIDs(of: device, selector: kCMIODevicePropertyStreams)
        let outputs = streams.filter { stream in
            var address = address(kCMIOStreamPropertyDirection)
            var direction: UInt32 = 1
            var size = UInt32(MemoryLayout<UInt32>.size)
            return CMIOObjectGetPropertyData(stream, &address, 0, nil, size, &size, &direction) == noErr && direction == 0
        }
        // If the direction can't be read, fall back to the order the extension adds them in: source, then sink.
        return outputs.first ?? (streams.count > 1 ? streams.last : nil)
    }
}
