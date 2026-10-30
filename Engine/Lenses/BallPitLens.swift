import CoreGraphics
import CoreImage
import simd

/// Balls rain down, pile up on the floor and bounce off you. Walk through them and they scatter.
struct BallPit {
    struct Ball {
        var position: SIMD2<Double>
        var velocity: SIMD2<Double>
        var radius: Double
        var colour: Int
    }

    static let colours = 8

    let size: CGSize
    private(set) var balls: [Ball] = []
    private var rng: SplitMix64
    private var owed = 0.0
    var capacity = 70

    init(size: CGSize, seed: UInt64 = 0xBA11) {
        self.size = size
        rng = SplitMix64(seed: seed)
    }

    mutating func removeAll() { balls.removeAll() }

    mutating func step(_ dt: Double, matte: MatteQuery?) {
        owed += dt * 7
        while owed >= 1 {
            owed -= 1
            if balls.count >= capacity { balls.removeFirst() }
            let radius = Double.random(in: 15...28, using: &rng)
            balls.append(Ball(position: SIMD2(Double.random(in: 40...(size.width - 40), using: &rng), size.height + radius),
                              velocity: SIMD2(Double.random(in: -50...50, using: &rng), Double.random(in: -80...0, using: &rng)),
                              radius: radius, colour: Int.random(in: 0..<Self.colours, using: &rng)))
        }

        // Substeps keep fast balls from tunnelling through an arm.
        let steps = 3
        let h = dt / Double(steps)
        for _ in 0..<steps {
            for i in balls.indices {
                balls[i].velocity.y -= 1150 * h
                balls[i].position += balls[i].velocity * h
                var p = balls[i].position, v = balls[i].velocity
                let r = balls[i].radius
                if p.y < r { p.y = r; v.y = abs(v.y) * 0.5; v.x *= 0.94 }
                if p.x < r { p.x = r; v.x = abs(v.x) * 0.6 }
                if p.x > size.width - r { p.x = size.width - r; v.x = -abs(v.x) * 0.6 }
                if let matte { Silhouette.resolve(position: &p, velocity: &v, radius: r, in: matte, restitution: 0.55) }
                balls[i].position = p
                balls[i].velocity = v
            }
            separateOverlappingBalls()
            keepInsideRoom()
        }
    }

    /// Neighbours can shove a ball into the floor or a wall; put it back.
    private mutating func keepInsideRoom() {
        for i in balls.indices {
            let r = balls[i].radius
            balls[i].position.y = max(r, balls[i].position.y)
            balls[i].position.x = min(max(r, balls[i].position.x), size.width - r)
        }
    }

    private mutating func separateOverlappingBalls() {
        for i in balls.indices {
            for j in balls.indices where j > i {
                let delta = balls[j].position - balls[i].position
                let distance = simd_length(delta), minimum = balls[i].radius + balls[j].radius
                guard distance < minimum, distance > 1e-6 else { continue }
                let normal = delta / distance
                let push = (minimum - distance) / 2
                balls[i].position -= normal * push
                balls[j].position += normal * push
                // Swap the speed along the line between them, losing a little.
                let relative = simd_dot(balls[j].velocity - balls[i].velocity, normal)
                if relative < 0 {
                    balls[i].velocity += normal * relative * 0.8
                    balls[j].velocity -= normal * relative * 0.8
                }
            }
        }
    }
}

final class BallPitLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    private var pit: BallPit

    init(size: CGSize = CGSize(width: 1280, height: 720)) { pit = BallPit(size: size) }

    func restart() { pit.removeAll() }

    var ballCount: Int { pit.balls.count }

    func render(_ input: LensInput) -> CIImage {
        pit.step(input.dt, matte: input.matteGrid)
        let layer = input.services.overlay { ctx in
            for ball in pit.balls {
                guard let sprite = BallPitLens.sprite(colour: ball.colour) else { continue }
                ctx.draw(sprite, in: CGRect(x: ball.position.x - ball.radius, y: ball.position.y - ball.radius,
                                            width: ball.radius * 2, height: ball.radius * 2))
            }
        }
        guard let layer else { return input.composed }
        return layer.composited(over: input.composed).cropped(to: input.rect)
    }

    private static let lock = NSLock()
    private static var sprites: [Int: CGImage] = [:]

    /// A glossy ball, drawn once per colour.
    static func sprite(colour: Int) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        if let hit = sprites[colour] { return hit }
        let side = 96
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let (r, g, b) = Palette.rgb(hue: Double(colour) / Double(BallPit.colours), saturation: 0.85, brightness: 0.95)
        let gradient = CGGradient(colorsSpace: space, colors: [CGColor(red: min(1, r + 0.5), green: min(1, g + 0.5), blue: min(1, b + 0.5), alpha: 1),
                                                               CGColor(red: r, green: g, blue: b, alpha: 1),
                                                               CGColor(red: r * 0.45, green: g * 0.45, blue: b * 0.45, alpha: 1)] as CFArray,
                                  locations: [0, 0.5, 1])!
        let mid = CGPoint(x: side / 2, y: side / 2)
        ctx.addEllipse(in: CGRect(x: 2, y: 2, width: side - 4, height: side - 4))
        ctx.clip()
        ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: mid.x - 16, y: mid.y + 18), startRadius: 0, endCenter: mid, endRadius: CGFloat(side) * 0.62,
                               options: [.drawsAfterEndLocation])
        guard let image = ctx.makeImage() else { return nil }
        sprites[colour] = image
        return image
    }
}
