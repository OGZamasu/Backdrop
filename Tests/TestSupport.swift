import CoreImage
import CoreVideo
import XCTest

typealias RGB = (r: Int, g: Int, b: Int)

enum TestSupport {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    static func solid(_ r: Double, _ g: Double, _ b: Double, size: CGSize = CGSize(width: 1280, height: 720)) -> CIImage {
        CIImage(color: CIColor(red: r, green: g, blue: b, colorSpace: srgb)!).cropped(to: CGRect(origin: .zero, size: size))
    }

    /// White on the left `fraction` of the frame, black elsewhere. A stand-in for "the person is on the left".
    static func matte(leftFraction fraction: Double, size: CGSize = CGSize(width: 1280, height: 720)) -> CIImage {
        let white = solid(1, 1, 1, size: CGSize(width: size.width * fraction, height: size.height))
        return white.composited(over: solid(0, 0, 0, size: size))
    }

    static func pixel(_ image: CIImage, x: Int, y: Int, context: CIContext) -> RGB {
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &bytes, rowBytes: 4,
                       bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: srgb)
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    static func pixel(_ buffer: CVPixelBuffer, x: Int, y: Int) -> RGB {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let p = base + y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
        return (Int(p[2]), Int(p[1]), Int(p[0])) // BGRA
    }

    static func cameraBuffer(r: UInt8, g: UInt8, b: UInt8, width: Int = 1280, height: Int = 720) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]] as CFDictionary, &buffer)
        let pb = buffer!
        CVPixelBufferLockBaseAddress(pb, [])
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pb)
        for y in 0..<height {
            for x in 0..<width {
                let p = base + y * stride + x * 4
                p[0] = b; p[1] = g; p[2] = r; p[3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        return pb
    }

    static func matteBuffer(width: Int, height: Int, leftFraction: Double) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_OneComponent8, nil, &buffer)
        let pb = buffer!
        CVPixelBufferLockBaseAddress(pb, [])
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pb)
        for y in 0..<height {
            for x in 0..<width { base[y * stride + x] = Double(x) < Double(width) * leftFraction ? 255 : 0 }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        return pb
    }

    static func matteValue(_ buffer: CVPixelBuffer, x: Int, y: Int) -> Int {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        return Int(base[y * CVPixelBufferGetBytesPerRow(buffer) + x])
    }
}

func assertColor(_ actual: RGB, _ expected: RGB, tolerance: Int = 12, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(abs(actual.r - expected.r) <= tolerance && abs(actual.g - expected.g) <= tolerance && abs(actual.b - expected.b) <= tolerance,
                  "expected \(expected) ±\(tolerance), got \(actual). \(message)", file: file, line: line)
}
