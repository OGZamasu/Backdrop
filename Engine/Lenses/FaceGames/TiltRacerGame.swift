import AppKit
import CoreGraphics
import simd

/// A road race steered by tipping your head. The road runs into the distance below you (you stay in the picture above the
/// horizon); tip your head left or right and the car follows. Overtake traffic, grab coins, and don't rear-end anyone.
struct TiltRacerGame: FaceGame {
    static let title = "Tilt Racer"
    static let hint = "Tip your head left and right to steer. Dodge the cars, grab the coins."
    static let presenceHint = "Look into the camera to play"
    static let move = FaceGameMove.tiltHead
    static let accent = FaceGamePalette.coral
    static let scoreLabel = "POINTS"

    struct Car: Equatable {
        /// Across the road: -1 is the left edge, 1 the right; the lanes are at -2/3, 0 and 2/3.
        var x: Double
        /// How far ahead, in metres.
        var z: Double
        var speed: Double
        var paint: Int
        var passed = false
        /// Set when bumped, so it spins off the road.
        var spin = 0.0
    }

    struct Coin: Equatable {
        var x: Double
        var z: Double
    }

    static let lives = 3
    static let lanes = [-2.0 / 3, 0, 2.0 / 3]
    /// How far the head has to tip, in radians, to reach the edge of the road.
    static let fullTilt = 0.3
    static let farZ = 85.0
    /// Within this much across, a car is hit.
    static let carWidth = 0.36

    // The view: the horizon, the road's half width under the player, and the camera's distance.
    static let horizonY = 292.0
    static let roadHalf = 470.0
    static let cameraDistance = 3.0
    static let playerY = 70.0

    let size: CGSize
    private(set) var playerX = 0.0
    private(set) var cars: [Car] = []
    private(set) var coins: [Coin] = []
    private(set) var score = 0
    private(set) var hearts = TiltRacerGame.lives
    private(set) var passed = 0
    private(set) var distance = 0.0
    private(set) var elapsed = 0.0
    private(set) var invulnerable = 0.0
    private(set) var steerTarget = 0.0
    private var lean = 0.0
    private var spawnTimer = 1.2
    private var coinTimer = 2.5
    private var spawning = true
    private var shake = 0.0
    private var rng: SplitMix64
    private var sparks = ParticleSystem(capacity: 160)
    private var floaters: [FaceGameFloater] = []

    var isOver: Bool { hearts <= 0 }
    var summary: String { "Lives \(hearts)" }
    /// Metres a second: quicker the longer you last.
    var speed: Double { 22 + min(12, elapsed * 0.15) }

    var chips: [FaceGameChip] { [.hearts(hearts, of: Self.lives)] }
    var ending: FaceGameEnding { .lost("WIPED OUT!") }
    var endLine: String { passed == 1 ? "You overtook 1 car" : "You overtook \(passed) cars" }
    var tip: String? { elapsed < 4 ? "Tip your head to steer" : nil }

    init(size: CGSize, seed: UInt64) {
        self.size = size
        rng = SplitMix64(seed: seed)
        sparks.gravity = SIMD2(0, -700)
        sparks.drag = 1.0
    }

    // MARK: Rules

    mutating func step(_ dt: Double, world: GameWorld) {
        let dt = min(max(dt, 0), 0.1)
        sparks.step(dt)
        FaceGamePaint.advance(&floaters, by: dt)
        shake = max(0, shake - dt * 3)
        guard !isOver else { return }
        // The road waits for a driver.
        guard let face = world.face else { return }
        elapsed += dt
        invulnerable = max(0, invulnerable - dt)

        // Tipping the top of your head to the left of the picture steers left.
        steerTarget = max(-0.92, min(0.92, -face.roll / Self.fullTilt))
        let before = playerX
        playerX = FaceGameEase.approach(playerX, steerTarget, rate: 4.5, dt: dt)
        lean = FaceGameEase.approach(lean, (playerX - before) / max(dt, 1e-3), rate: 10, dt: dt)

        distance += speed * dt
        if spawning {
            spawnTimer -= dt
            if spawnTimer <= 0 {
                spawnCar()
                spawnTimer = FaceGamePaint.lerp(1.7, 0.85, elapsed / 80) * Double.random(in: 0.8...1.2, using: &rng)
            }
            coinTimer -= dt
            if coinTimer <= 0 {
                let lane = Self.lanes[Int.random(in: 0..<3, using: &rng)]
                if !cars.contains(where: { abs($0.x - lane) < 0.3 && abs($0.z - Self.farZ) < 12 }) {
                    for k in 0..<3 { coins.append(Coin(x: lane, z: Self.farZ + Double(k) * 4)) }
                }
                coinTimer = Double.random(in: 2.5...4.5, using: &rng)
            }
        }
        for i in cars.indices {
            cars[i].z -= (speed - cars[i].speed) * dt
            if cars[i].spin != 0 {
                cars[i].x += cars[i].spin * 1.6 * dt
            }
            if !cars[i].passed, cars[i].z < -1.2 {
                cars[i].passed = true
                if cars[i].spin == 0 {
                    passed += 1
                    score += 10
                    floaters.append(FaceGameFloater(text: "+10", position: SIMD2(screenX(cars[i].x, z: 0), Self.playerY + 150), tone: FaceGamePalette.cream, size: 40, life: 0.7))
                }
            }
        }
        cars.removeAll { $0.z < -4 || abs($0.x) > 2.5 }
        for i in coins.indices { coins[i].z -= speed * dt }
        coins.removeAll { $0.z < -2 }

        collectCoins()
        if invulnerable == 0 { checkCrash() }
    }

    /// Cars that close up within this many metres of each other count as a wall across their lanes.
    static let fairGap = 22.0

    private mutating func spawnCar() {
        // Never block all three lanes near each other. The traffic all moves at nearly the same speed, so cars never catch each
        // other up and a gap that is fair when they appear stays fair.
        let near = cars.filter { $0.z > Self.farZ - Self.fairGap }.map(\.x)
        let open = Self.lanes.filter { lane in !near.contains { abs($0 - lane) < 0.2 } }
        guard open.count >= 2 else { return }
        let lane = open[Int.random(in: 0..<open.count, using: &rng)]
        cars.append(Car(x: lane, z: Self.farZ, speed: Double.random(in: 10.5...11.5, using: &rng), paint: Int.random(in: 0..<TiltRacerArt.trafficTones.count, using: &rng)))
    }

    private mutating func collectCoins() {
        var kept: [Coin] = []
        for coin in coins {
            if abs(coin.z) < 1.4, abs(coin.x - playerX) < 0.3 {
                score += 25
                let p = SIMD2(screenX(coin.x, z: 0), Self.playerY + 90)
                floaters.append(FaceGameFloater(text: "+25", position: p + SIMD2(0, 60), tone: FaceGamePalette.sun, size: 46, life: 0.8))
                for _ in 0..<12 {
                    let a = Double.random(in: 0.3...2.8, using: &rng), v = Double.random(in: 200...480, using: &rng)
                    sparks.emit(Particle(position: p, velocity: SIMD2(cos(a), sin(a)) * v, life: Double.random(in: 0.3...0.7, using: &rng),
                                         size: Double.random(in: 5...11, using: &rng), kind: 0))
                }
            } else {
                kept.append(coin)
            }
        }
        coins = kept
    }

    private mutating func checkCrash() {
        guard let i = cars.firstIndex(where: { $0.spin == 0 && $0.z > -0.8 && $0.z < 1.6 && abs($0.x - playerX) < Self.carWidth }) else { return }
        hearts -= 1
        invulnerable = 1.6
        shake = 1
        cars[i].spin = cars[i].x >= playerX ? 1 : -1
        cars[i].speed = speed * 0.6
        let p = SIMD2(screenX(cars[i].x, z: max(0, cars[i].z)), Self.playerY + 60)
        for _ in 0..<20 {
            let a = Double.random(in: 0.2...2.9, using: &rng), v = Double.random(in: 160...520, using: &rng)
            sparks.emit(Particle(position: p, velocity: SIMD2(cos(a), sin(a)) * v, life: Double.random(in: 0.3...0.8, using: &rng),
                                 size: Double.random(in: 5...12, using: &rng), kind: 1))
        }
    }

    /// After the round only the particles and words carry on; with no face, nothing in the rules moves.
    mutating func settle(_ dt: Double) {
        step(dt, world: GameWorld(size: size, matte: nil, motion: nil, face: nil))
    }

    // MARK: Test hooks

    /// Puts these cars on the road and stops new traffic and coins.
    mutating func place(cars: [Car], coins: [Coin] = []) {
        self.cars = cars
        self.coins = coins
        spawning = false
    }

    // MARK: The view

    /// How much smaller things are at a distance: 1 under the player, falling towards the horizon.
    static func scale(_ z: Double) -> Double { cameraDistance / (max(z, -0.9) + cameraDistance) }

    func screenY(_ z: Double) -> Double {
        Self.horizonY - (Self.horizonY - Self.playerY) * Self.scale(z)
    }

    /// The road bends gently as it goes, so it doesn't look like a treadmill.
    private var bend: Double { 0.9 * sin(distance * 0.0045) * sin(distance * 0.0013 + 1) }

    func screenX(_ x: Double, z: Double) -> Double {
        let zz = max(0, z)
        return Double(size.width) / 2 + (x * Self.roadHalf + bend * zz * zz * 0.9) * Self.scale(z)
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: Double) {
        ctx.saveGState()
        let wobble = shake * shake * 8
        ctx.translateBy(x: CGFloat(sin(time * 51) * wobble), y: CGFloat(cos(time * 43) * wobble * 0.5))
        drawRoad(ctx)
        drawThings(ctx, time: time)
        drawPlayer(ctx, time: time)
        for p in sparks.particles {
            let tone = p.kind == 0 ? FaceGamePalette.sun : FaceGamePaint.mix(FaceGamePalette.cream, FaceGamePalette.tangerine, p.progress)
            FaceGamePaint.spark(ctx, at: CGPoint(x: p.position.x, y: p.position.y), radius: p.size * (1 - 0.5 * p.progress), tone: tone, alpha: 1 - p.progress)
        }
        ctx.restoreGState()
        FaceGamePaint.draw(floaters, in: ctx)
    }

    /// Hills on the horizon, then the road in strips from far to near: grass, kerbs, tarmac and lane lines.
    private func drawRoad(_ ctx: CGContext) {
        let w = Double(size.width)
        // Soft hills along the horizon, sliding with the bend.
        let hills = CGMutablePath()
        hills.move(to: CGPoint(x: 0, y: Self.horizonY - 4))
        var x = 0.0
        while x <= w + 16 {
            let u = x - bend * 160
            hills.addLine(to: CGPoint(x: x, y: Self.horizonY + 22 + 18 * sin(u * 0.009) + 10 * sin(u * 0.023 + 2)))
            x += 16
        }
        hills.addLine(to: CGPoint(x: w + 16, y: Self.horizonY - 4))
        hills.closeSubpath()
        FaceGameArt.fillLit(ctx, hills, tone: FaceGamePaint.mix(FaceGamePalette.leaf, FaceGamePalette.sky, 0.45), contrast: 0.4)

        let grassA = FaceGamePaint.Tone(0.42, 0.74, 0.34), grassB = FaceGamePaint.Tone(0.38, 0.68, 0.3)
        let roadA = FaceGamePaint.Tone(0.42, 0.42, 0.5), roadB = FaceGamePaint.Tone(0.39, 0.39, 0.47)
        let segment = 3.0
        let first = Int((distance / segment).rounded(.down))
        let count = Int(Self.farZ / segment) + 2
        for k in stride(from: first + count, through: first, by: -1) {
            let zNear = max(-0.85, Double(k) * segment - distance)
            let zFar = Double(k + 1) * segment - distance
            guard zFar > -0.85 else { continue }
            let y1 = screenY(zNear), y2 = screenY(zFar)
            let even = k % 2 == 0
            ctx.setFillColor(FaceGamePaint.cg(even ? grassA : grassB))
            ctx.fill(CGRect(x: -20, y: y1, width: w + 40, height: y2 - y1 + 0.6))
            func quad(_ a: Double, _ b: Double, _ tone: FaceGamePaint.Tone) {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: screenX(a, z: zNear), y: y1))
                p.addLine(to: CGPoint(x: screenX(b, z: zNear), y: y1))
                p.addLine(to: CGPoint(x: screenX(b, z: zFar), y: y2 + 0.6))
                p.addLine(to: CGPoint(x: screenX(a, z: zFar), y: y2 + 0.6))
                p.closeSubpath()
                ctx.addPath(p)
                ctx.setFillColor(FaceGamePaint.cg(tone))
                ctx.fillPath()
            }
            quad(-1.12, 1.12, even ? FaceGamePalette.cream : FaceGamePalette.coral)
            quad(-1, 1, even ? roadA : roadB)
            if even {
                for line in [-1.0 / 3, 1.0 / 3] { quad(line - 0.018, line + 0.018, FaceGamePalette.cream) }
            }
        }
        // A haze where the road meets the sky, so it melts into the picture above.
        let colors = [FaceGamePaint.cg(FaceGamePalette.cream, 0), FaceGamePaint.cg(FaceGamePalette.cream, 0.45)] as CFArray
        if let g = CGGradient(colorsSpace: FaceGamePaint.space, colors: colors, locations: [0, 1]) {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: Self.horizonY - 70, width: w, height: 110))
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: Self.horizonY - 70), end: CGPoint(x: 0, y: Self.horizonY + 8), options: [])
            ctx.restoreGState()
        }
    }

    /// Trees, coins and traffic, drawn from the farthest to the nearest.
    private func drawThings(_ ctx: CGContext, time: Double) {
        enum Thing { case tree(Int, Double), coin(Double), car(Car) }
        var things: [(z: Double, x: Double, thing: Thing)] = []
        let spacing = 10.0
        let first = Int((distance / spacing).rounded(.down))
        for k in first...(first + Int(Self.farZ / spacing) + 1) {
            let z = Double(k) * spacing - distance
            guard z > -1, z < Self.farZ else { continue }
            for side in [-1.0, 1.0] {
                let h = FaceGamePaint.hash(k * 2 + (side > 0 ? 1 : 0), 4)
                guard h > 0.25 else { continue }
                things.append((z, side * (1.45 + 0.5 * FaceGamePaint.hash(k, side > 0 ? 6 : 7)), .tree(Int(h * 30), 0.8 + 0.5 * FaceGamePaint.hash(k, 8))))
            }
        }
        for coin in coins where coin.z > -1 && coin.z < Self.farZ { things.append((coin.z, coin.x, .coin(coin.z))) }
        for car in cars where car.z > -1.4 && car.z < Self.farZ { things.append((car.z, car.x, .car(car))) }
        things.sort { $0.z > $1.z }
        for item in things {
            let s = Self.scale(item.z)
            let fade = 1 - FaceGamePaint.smoothstep(Self.farZ - 15, Self.farZ, item.z)
            let base = CGPoint(x: screenX(item.x, z: item.z), y: screenY(item.z))
            switch item.thing {
            case .tree(let kind, let grow):
                guard let image = TiltRacerArt.tree(kind) else { continue }
                let h = 260 * s * grow
                FaceGameArt.stamp(ctx, image, at: CGPoint(x: base.x, y: base.y + h / 2 - 4 * s), height: h, alpha: fade)
            case .coin:
                let h = 64 * s
                let turn = abs(cos(time * 4 + item.z * 0.3))
                ctx.saveGState()
                ctx.translateBy(x: base.x, y: base.y + 70 * s)
                ctx.scaleBy(x: CGFloat(max(0.15, turn)), y: 1)
                FaceGameArt.stamp(ctx, TiltRacerArt.coin, at: .zero, height: h, alpha: fade)
                ctx.restoreGState()
            case .car(let car):
                let h = 180 * s * 0.92
                FaceGameArt.contactShadow(ctx, center: CGPoint(x: base.x, y: base.y + 4 * s), width: 250 * s, height: 30 * s, alpha: 0.4 * fade)
                FaceGameArt.stamp(ctx, TiltRacerArt.car(car.paint, player: false), at: CGPoint(x: base.x, y: base.y + h / 2), height: h,
                                  rotation: car.spin * min(1.2, max(0, -car.z + 2) * 0.3), alpha: fade)
            }
        }
    }

    private func drawPlayer(_ ctx: CGContext, time: Double) {
        let x = screenX(playerX, z: 0)
        let pulse = invulnerable > 0 ? 0.55 + 0.45 * (0.5 + 0.5 * cos(invulnerable * 2 * .pi * 2.5)) : 1
        let tilt = max(-0.12, min(0.12, -lean * 0.06))
        let bounce = sin(time * 18) * 1.5
        FaceGameArt.contactShadow(ctx, center: CGPoint(x: x, y: Self.playerY + 4), width: 300, height: 40, alpha: 0.45)
        // Exhaust puffs.
        for k in 0..<3 {
            let t = FaceGamePaint.wrap(time * 2.2 + Double(k) / 3, 1)
            FaceGamePaint.spark(ctx, at: CGPoint(x: x + (k % 2 == 0 ? -40 : 40) - t * 20, y: Self.playerY + 26 - t * 6),
                                radius: 10 + 26 * t, tone: FaceGamePalette.cream, alpha: 0.35 * (1 - t))
        }
        FaceGameArt.stamp(ctx, TiltRacerArt.car(0, player: true), at: CGPoint(x: x, y: Self.playerY + 90 + bounce), height: 180, rotation: tilt, alpha: pulse)
    }
}
