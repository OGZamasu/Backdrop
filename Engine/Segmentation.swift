import CoreGraphics
import CoreVideo
import Vision

/// Finds the person in a camera frame and returns a single-channel matte (255 = person).
final class PersonSegmenter {
    enum Quality: String, CaseIterable, Identifiable {
        case fast, balanced, accurate
        var id: String { rawValue }
    }

    var quality: Quality {
        didSet { request.qualityLevel = Self.level(for: quality) }
    }

    private let request = VNGeneratePersonSegmentationRequest()
    // Kept across frames so Vision can use temporal information.
    private let handler = VNSequenceRequestHandler()

    init(quality: Quality = .balanced) {
        self.quality = quality
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        request.qualityLevel = Self.level(for: quality)
    }

    func mask(for pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        do { try handler.perform([request], on: pixelBuffer) } catch { return nil }
        return (request.results?.first as? VNPixelBufferObservation)?.pixelBuffer
    }

    private static func level(for quality: Quality) -> VNGeneratePersonSegmentationRequest.QualityLevel {
        switch quality {
        case .fast: return .fast
        case .balanced: return .balanced
        case .accurate: return .accurate
        }
    }
}

/// Blends each new matte with the previous one so edges don't shimmer, and tracks where the subject is.
final class MaskSmoother {
    /// Weight given to the newest matte, 0...1. Lower is steadier but lags fast movement.
    var responsiveness: Float = 0.65

    /// Centre of the subject, normalised to 0...1 with the origin at the top left.
    private(set) var centroid = CGPoint(x: 0.5, y: 0.5)

    private var previous: CVPixelBuffer?
    private var pool: CVPixelBufferPool?

    /// The most recent smoothed matte, for reuse when a frame fails to segment.
    var latest: CVPixelBuffer? { previous }
    private var poolSize = (width: 0, height: 0)

    func reset() {
        previous = nil
        centroid = CGPoint(x: 0.5, y: 0.5)
    }

    func smooth(_ mask: CVPixelBuffer) -> CVPixelBuffer {
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        guard let output = makeBuffer(width: width, height: height) else { return mask }

        var reference = previous
        if let p = reference, CVPixelBufferGetWidth(p) != width || CVPixelBufferGetHeight(p) != height { reference = nil }

        CVPixelBufferLockBaseAddress(mask, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        if let reference { CVPixelBufferLockBaseAddress(reference, .readOnly) }
        defer {
            CVPixelBufferUnlockBaseAddress(mask, .readOnly)
            CVPixelBufferUnlockBaseAddress(output, [])
            if let reference { CVPixelBufferUnlockBaseAddress(reference, .readOnly) }
        }

        guard let src = CVPixelBufferGetBaseAddress(mask)?.assumingMemoryBound(to: UInt8.self),
              let dst = CVPixelBufferGetBaseAddress(output)?.assumingMemoryBound(to: UInt8.self) else { return mask }
        let srcStride = CVPixelBufferGetBytesPerRow(mask)
        let dstStride = CVPixelBufferGetBytesPerRow(output)
        let prev = reference.flatMap { CVPixelBufferGetBaseAddress($0)?.assumingMemoryBound(to: UInt8.self) }
        let prevStride = reference.map { CVPixelBufferGetBytesPerRow($0) } ?? 0

        let weight = Int(max(0, min(1, responsiveness)) * 256)
        var sumX = 0, sumY = 0, count = 0

        for y in 0..<height {
            let s = src + y * srcStride
            let d = dst + y * dstStride
            if let prev {
                let p = prev + y * prevStride
                for x in 0..<width {
                    d[x] = UInt8((Int(p[x]) * (256 - weight) + Int(s[x]) * weight) >> 8)
                }
            } else {
                d.update(from: s, count: width)
            }
            if y % 2 == 0 {
                var x = 0
                while x < width {
                    if d[x] > 128 { sumX += x; sumY += y; count += 1 }
                    x += 2
                }
            }
        }

        if count > 64 {
            let target = CGPoint(x: CGFloat(sumX) / CGFloat(count) / CGFloat(width),
                                 y: CGFloat(sumY) / CGFloat(count) / CGFloat(height))
            // Low-pass so a parallax background glides rather than twitches.
            centroid = CGPoint(x: centroid.x + (target.x - centroid.x) * 0.2,
                               y: centroid.y + (target.y - centroid.y) * 0.2)
        }

        previous = output
        return output
    }

    private func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        if pool == nil || poolSize.width != width || poolSize.height != height {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_OneComponent8,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
            ]
            var newPool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &newPool)
            pool = newPool
            poolSize = (width, height)
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }
}
