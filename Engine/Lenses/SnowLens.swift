import CoreImage
import CoreImage.CIFilterBuiltins

/// Snowflakes falling, which settle on whoever is in front of them and melt.
struct SnowField {
    var particles = ParticleSystem(capacity: 900)
    let size: CGSize
    private var rng: SplitMix64
    private var owed = 0.0

    static let restingKind = 1

    init(size: CGSize, seed: UInt64 = 0x5110) {
        self.size = size
        rng = SplitMix64(seed: seed)
        particles.gravity = .zero
    }

    var landedCount: Int { particles.particles.filter { $0.kind == Self.restingKind }.count }

    mutating func step(_ dt: Double, matte: MatteQuery?, rate: Double = 150) {
        owed += rate * dt
        while owed >= 1 {
            owed -= 1
            let flake = Double.random(in: 1.4...4.6, using: &rng)
            particles.emit(Particle(position: SIMD2(Double.random(in: -150...(size.width + 50), using: &rng), size.height + 8),
                                    velocity: SIMD2(-30, -(45 + flake * 26)), age: 0, life: 40, size: flake,
                                    hue: Double.random(in: 0..<1, using: &rng), kind: 0))
        }

        let floor = -6.0
        particles.step(dt) { p in
            if p.kind == 0 {
                // Sway as it falls, then catch on anyone it meets.
                p.velocity.x = -30 + sin(p.age * 1.7 + p.hue * 6.28) * 24
                if p.position.y < floor { p.age = p.life; return }
                if let matte, matte.coverage(x: p.position.x, y: p.position.y) > 0.5 {
                    p.kind = Self.restingKind
                    p.velocity = .zero
                    p.life = p.age + 1.4 + p.hue * 1.8     // melts after a moment
                }
            } else if let matte, matte.coverage(x: p.position.x, y: p.position.y) < 0.3 {
                // Whatever it was resting on has moved away: it falls again.
                p.kind = 0
                p.velocity = SIMD2(-30, -(45 + p.size * 26))
            }
        }
    }

    mutating func removeAll() { particles.removeAll() }
}

final class SnowLens: Lens {
    let needs: LensNeeds = [.matte]
    var wantsMatteGrid: Bool { true }

    private var snow: SnowField

    init(size: CGSize = CGSize(width: 1280, height: 720)) { snow = SnowField(size: size) }

    func restart() { snow.removeAll() }

    var landedCount: Int { snow.landedCount }
    var flakeCount: Int { snow.particles.particles.count }

    func render(_ input: LensInput) -> CIImage {
        snow.step(input.dt, matte: input.matteGrid)
        // A cold cast over the whole scene.
        let cold = input.composed.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.92, y: 0, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 1.08, w: 0),
        ]).applyingFilter("CIColorClamp")
        guard let dot = Sprites.dot(red: 1, green: 1, blue: 1),
              let layer = input.services.overlay({ ctx in
                  for p in snow.particles.particles {
                      let resting = p.kind == SnowField.restingKind
                      let alpha = resting ? 1 - pow(p.progress, 3) : 0.92
                      ctx.stampDot(dot, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * (resting ? 2.3 : 1.9), alpha: alpha)
                  }
              }) else { return cold }
        return layer.composited(over: cold).cropped(to: input.rect)
    }
}
