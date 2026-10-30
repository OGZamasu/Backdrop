import Foundation
import simd

struct Particle {
    var position: SIMD2<Double>
    var velocity: SIMD2<Double>
    var age = 0.0
    var life: Double
    var size: Double
    /// A colour index or hue, whatever the lens wants.
    var hue = 0.0
    var kind = 0

    /// 0 when new, 1 when it dies.
    var progress: Double { min(1, age / max(life, 1e-9)) }
}

/// A plain particle simulation with no drawing in it. Lenses own the look.
struct ParticleSystem {
    var particles: [Particle] = []
    var gravity = SIMD2<Double>(0, -900)
    /// Fraction of speed lost per second.
    var drag = 0.0
    let capacity: Int

    init(capacity: Int = 800) { self.capacity = capacity }

    mutating func emit(_ particle: Particle) {
        if particles.count >= capacity { particles.removeFirst(particles.count - capacity + 1) }
        particles.append(particle)
    }

    /// Advances everything, then lets `adjust` change a particle (to bounce it, stick it) before the dead are swept away.
    mutating func step(_ dt: Double, adjust: ((inout Particle) -> Void)? = nil) {
        for i in particles.indices {
            particles[i].velocity += gravity * dt
            if drag > 0 { particles[i].velocity *= max(0, 1 - drag * dt) }
            particles[i].position += particles[i].velocity * dt
            particles[i].age += dt
            adjust?(&particles[i])
        }
        particles.removeAll { $0.age >= $0.life }
    }

    mutating func removeAll() { particles.removeAll() }
}
