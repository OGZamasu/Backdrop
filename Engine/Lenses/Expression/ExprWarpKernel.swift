import CoreImage
import Foundation
import os

/// One smooth local warp, centred on a point of the face: it can swell (or shrink) what is under it, twirl it, and push it
/// along. Its reach is an ellipse lined up with the face, and its strength falls off smoothly to exactly nothing at the edge,
/// so there is no ring, seam or kink where it ends.
struct ExprWarpTerm {
    var center: CGPoint
    /// Half-widths of the ellipse in pixels: `across` along the eyes, `along` up the face.
    var across: Double
    var along: Double
    /// The face's roll, so the ellipse turns with the head.
    var angle: Double = 0
    /// Above 0 swells what is under the centre (0.5 shows it twice as big); below 0 shrinks it. Kept within -1.4...0.9 so the
    /// picture never folds over itself.
    var magnify: Double = 0
    /// Radians the middle is turned, fading to none at the edge.
    var twirl: Double = 0
    /// Pixels the middle is carried, fading to none at the edge.
    var push: CGVector = .zero

    var reach: Double { max(across, along) }

    /// A term laid out in face units: centre `(x, y)` and radii in eye-spacings, turned with the face.
    static func face(_ f: FaceState, _ x: Double, _ y: Double, across: Double, along: Double) -> ExprWarpTerm {
        ExprWarpTerm(center: f.exprPoint(x, y), across: across * f.interocular, along: along * f.interocular, angle: f.roll)
    }
}

/// The GPU side of `ExprWarpTerm`: a Core Image warp kernel compiled from Metal source once per run of the app.
///
/// Compiling takes a few hundred milliseconds, so `warmUp()` starts it in the background as soon as the lens catalog is built;
/// by the time anyone picks a funhouse lens it is long done. If something renders before that, it simply waits for it once.
enum ExprWarpKernel {
    private static let source = """
    #include <CoreImage/CoreImage.h>
    using namespace metal;

    // How far to look back from p for one term. a = (centre x, centre y, magnify, twirl); b = the matrix taking an offset
    // from the centre to unit-ellipse coordinates; c = (push x, push y, -, -).
    static float2 exprTerm(float2 p, float4 a, float4 b, float4 c) {
        float2 d = p - a.xy;
        float2 q = float2(b.x * d.x + b.y * d.y, b.z * d.x + b.w * d.y);
        float r2 = dot(q, q);
        if (r2 >= 1.0) { return float2(0.0); }
        float w = 1.0 - r2;
        w = w * w * w;
        float turn = a.w * w;
        float cs = cos(turn), sn = sin(turn);
        float2 turned = float2(cs * d.x - sn * d.y, sn * d.x + cs * d.y);
        return (turned - d) - d * (a.z * w) - c.xy * w;
    }

    [[stitchable]] float2 exprWarp(float4 a0, float4 b0, float4 c0, float4 a1, float4 b1, float4 c1,
                                   float4 a2, float4 b2, float4 c2, float4 a3, float4 b3, float4 c3,
                                   coreimage::destination dest) {
        float2 p = dest.coord();
        return p + exprTerm(p, a0, b0, c0) + exprTerm(p, a1, b1, c1) + exprTerm(p, a2, b2, c2) + exprTerm(p, a3, b3, c3);
    }
    """

    /// The compiled kernel, or nil if this Mac can't build it (then the warps fall back to Core Image's stock distortions).
    static let kernel: CIWarpKernel? = {
        do {
            return try CIKernel.kernels(withMetalString: source).compactMap { $0 as? CIWarpKernel }.first
        } catch {
            Log.lens.error("Expression warp kernel didn't compile: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    private static let started = NSLock()
    private static var warming = false

    /// Starts building the kernel off to the side, so the first funhouse frame doesn't wait for it.
    static func warmUp() {
        started.lock(); defer { started.unlock() }
        guard !warming else { return }
        warming = true
        DispatchQueue.global(qos: .utility).async { _ = kernel }
    }
}

extension ExprWarp {
    /// Applies smooth warp terms around the face, four at a time. Only the pixels the terms can reach are worked out, unless
    /// `wholeFrame` is set: then each pass runs over the whole picture (still cheap: it leaves at once where no term reaches),
    /// which keeps every untouched pixel bit-for-bit the same as it came in.
    static func warp(_ image: CIImage, terms: [ExprWarpTerm], bounds: CGRect, wholeFrame: Bool = false) -> CIImage {
        let live = terms.filter { ($0.magnify != 0 || $0.twirl != 0 || $0.push != .zero) && $0.reach > 1 }
        guard !live.isEmpty else { return image }
        var out = image
        var start = 0
        while start < live.count {
            let chunk = Array(live[start..<min(start + 4, live.count)])
            start += 4
            let region = wholeFrame ? bounds : union(of: chunk.map { ($0.center, $0.reach + 2) })
            let pass: (CIImage) -> CIImage = { source in
                guard let kernel = ExprWarpKernel.kernel else { return fallback(source, chunk) }
                var arguments: [Any] = []
                for i in 0..<4 { arguments += i < chunk.count ? vectors(for: chunk[i]) : [CIVector(x: -1e6, y: -1e6, z: 0, w: 0), CIVector(x: 0, y: 0, z: 0, w: 0), CIVector(x: 0, y: 0, z: 0, w: 0)] }
                let margin = chunk.map { $0.reach * (abs($0.magnify) + abs($0.twirl)) + hypot($0.push.dx, $0.push.dy) }.max() ?? 0
                return kernel.apply(extent: region.integral, roiCallback: { _, rect in rect.insetBy(dx: -margin - 2, dy: -margin - 2) },
                                    image: source, arguments: arguments) ?? source
            }
            out = wholeFrame ? pass(out.clampedToExtent()).cropped(to: bounds) : apply(to: out, in: region, bounds: bounds, pass)
        }
        return out
    }

    /// The three vectors the kernel reads for one term.
    private static func vectors(for t: ExprWarpTerm) -> [CIVector] {
        let c = cos(t.angle), s = sin(t.angle)
        let ia = 1 / max(t.across, 1), ib = 1 / max(t.along, 1)
        // q = diag(1/across, 1/along) · R(-angle) · d
        let m = (c * ia, s * ia, -s * ib, c * ib)
        return [CIVector(x: t.center.x, y: t.center.y, z: CGFloat(min(0.9, max(-1.4, t.magnify))), w: CGFloat(t.twirl)),
                CIVector(x: CGFloat(m.0), y: CGFloat(m.1), z: CGFloat(m.2), w: CGFloat(m.3)),
                CIVector(x: t.push.dx, y: t.push.dy, z: 0, w: 0)]
    }

    /// Stock distortions standing in for the kernel: rounder and harder-edged, but the same idea.
    private static func fallback(_ source: CIImage, _ terms: [ExprWarpTerm]) -> CIImage {
        var out = source
        for t in terms {
            if t.magnify != 0 { out = bump(out, center: t.center, radius: t.reach, scale: t.magnify) }
            if t.twirl != 0 { out = twirl(out, center: t.center, radius: t.reach, angle: t.twirl) }
        }
        return out
    }
}
