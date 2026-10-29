import Foundation

/// Small, fast, seedable generator, so pipe growth can be tested deterministically.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// How the classic Windows "3D Pipes" screensaver grows its pipes, with no graphics attached.
///
/// Pipes start at a free cell in a box and extend one cell at a time. They mostly carry straight on, sometimes turn
/// (which is where a ball joint goes), and end when they get boxed in or old. Several grow at once. When the box is
/// full enough, new pipes stop starting; once the last one finishes, everything clears and it begins again.
struct PipeGrowth {
    typealias Cell = SIMD3<Int>

    enum Event: Equatable {
        case clear
        case start(Cell, color: Int, pipe: Int)
        /// `turned` means the pipe changed direction at `from`, so a joint belongs there.
        case extend(from: Cell, to: Cell, color: Int, turned: Bool, pipe: Int)
        case end(Cell, color: Int, pipe: Int)
    }

    /// Shaped like a 16:9 frame seen from the front, and shallow, so it fills a widescreen picture
    /// instead of huddling in the middle of it, and pipes still pass in front of and behind each other.
    static let wideDimensions = Cell(24, 13, 6)

    static let directions: [Cell] = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]

    let dimensions: Cell
    let colorCount: Int
    let maxSegments: Int
    let concurrentPipes: Int
    /// How likely a pipe is to keep going straight at each step.
    let straightness: Double

    private struct Pipe {
        let id: Int
        var head: Cell
        var heading: Cell
        let color: Int
        var remaining: Int
    }

    private var rng: SplitMix64
    private var occupied = Set<Cell>()
    private var pipes: [Pipe] = []
    private var nextID = 0
    private var totalSegments = 0

    private var volume: Int { dimensions.x * dimensions.y * dimensions.z }

    init(dimensions: Cell = PipeGrowth.wideDimensions, colorCount: Int = 8, maxSegments: Int? = nil,
         concurrentPipes: Int = 3, straightness: Double = 0.62, seed: UInt64 = .random(in: .min ... .max)) {
        self.dimensions = dimensions
        self.colorCount = colorCount
        self.maxSegments = maxSegments ?? Int(Double(dimensions.x * dimensions.y * dimensions.z) * 0.4)
        self.concurrentPipes = concurrentPipes
        self.straightness = straightness
        rng = SplitMix64(seed: seed)
    }

    /// A cube, for tests.
    init(size: Int, colorCount: Int = 8, maxSegments: Int? = nil, concurrentPipes: Int = 3, straightness: Double = 0.62, seed: UInt64) {
        self.init(dimensions: Cell(repeating: size), colorCount: colorCount, maxSegments: maxSegments,
                  concurrentPipes: concurrentPipes, straightness: straightness, seed: seed)
    }

    /// Advances every growing pipe by one cell, and may start a new one. Returns what changed, in order.
    mutating func step() -> [Event] {
        var events: [Event] = []

        var survivors: [Pipe] = []
        for var pipe in pipes {
            guard pipe.remaining > 0, let direction = nextDirection(for: pipe) else {
                events.append(.end(pipe.head, color: pipe.color, pipe: pipe.id))
                continue
            }
            let target = pipe.head &+ direction
            events.append(.extend(from: pipe.head, to: target, color: pipe.color, turned: direction != pipe.heading, pipe: pipe.id))
            occupied.insert(target)
            pipe.head = target
            pipe.heading = direction
            pipe.remaining -= 1
            totalSegments += 1
            survivors.append(pipe)
        }
        pipes = survivors

        let windingDown = totalSegments >= maxSegments || Double(occupied.count) > Double(volume) * 0.5
        if windingDown {
            // Let the pipes still growing finish. Only wipe the box once nothing is in it mid-growth.
            guard pipes.isEmpty else { return events }
            occupied.removeAll()
            totalSegments = 0
            events.append(.clear)
        }

        if pipes.count < concurrentPipes { events.append(contentsOf: startPipe()) }
        return events
    }

    // MARK: Internals

    private func isFree(_ cell: Cell) -> Bool {
        cell.x >= 0 && cell.x < dimensions.x && cell.y >= 0 && cell.y < dimensions.y
            && cell.z >= 0 && cell.z < dimensions.z && !occupied.contains(cell)
    }

    private mutating func nextDirection(for pipe: Pipe) -> Cell? {
        let canContinue = isFree(pipe.head &+ pipe.heading)
        if canContinue && Double.random(in: 0..<1, using: &rng) < straightness { return pipe.heading }

        let behind = Cell(repeating: 0) &- pipe.heading
        let turns = Self.directions.filter { $0 != pipe.heading && $0 != behind && isFree(pipe.head &+ $0) }
        if let turn = turns.randomElement(using: &rng) { return turn }
        return canContinue ? pipe.heading : nil
    }

    private mutating func startPipe() -> [Event] {
        var start: Cell?
        for _ in 0..<60 {
            let candidate = Cell(Int.random(in: 0..<dimensions.x, using: &rng),
                                 Int.random(in: 0..<dimensions.y, using: &rng),
                                 Int.random(in: 0..<dimensions.z, using: &rng))
            if isFree(candidate) { start = candidate; break }
        }
        guard let start else {
            // Effectively full. With nothing growing, clear and let the next step begin afresh.
            guard pipes.isEmpty else { return [] }
            occupied.removeAll()
            totalSegments = 0
            return [.clear]
        }

        let pipe = Pipe(id: nextID,
                        head: start,
                        heading: Self.directions.randomElement(using: &rng) ?? [1, 0, 0],
                        color: Int.random(in: 0..<colorCount, using: &rng),
                        remaining: Int.random(in: 24...70, using: &rng))
        nextID += 1
        occupied.insert(start)
        pipes.append(pipe)
        return [.start(start, color: pipe.color, pipe: pipe.id)]
    }
}
