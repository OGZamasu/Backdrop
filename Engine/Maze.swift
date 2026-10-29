import Foundation

/// A perfect maze (exactly one route between any two cells), carved with a depth-first search.
struct Maze {
    typealias Cell = SIMD2<Int>

    enum Direction: Int, CaseIterable {
        case north, east, south, west

        /// Row numbers grow southward, so north is -y.
        var vector: Cell {
            switch self {
            case .north: return Cell(0, -1)
            case .east: return Cell(1, 0)
            case .south: return Cell(0, 1)
            case .west: return Cell(-1, 0)
            }
        }
        var opposite: Direction { Direction(rawValue: (rawValue + 2) % 4)! }
        fileprivate var bit: UInt8 { 1 << UInt8(rawValue) }
    }

    let width: Int
    let height: Int
    /// One bit per direction: set when there is no wall that way.
    private var passages: [UInt8]

    init(width: Int, height: Int, seed: UInt64) {
        precondition(width > 0 && height > 0, "a maze needs at least one cell")
        self.width = width
        self.height = height
        passages = Array(repeating: 0, count: width * height)

        var rng = SplitMix64(seed: seed)
        var visited = Array(repeating: false, count: width * height)
        let start = Cell(Int.random(in: 0..<width, using: &rng), Int.random(in: 0..<height, using: &rng))
        var stack = [start]
        visited[start.y * width + start.x] = true

        while let current = stack.last {
            let unvisited = Direction.allCases.filter { direction in
                let next = current &+ direction.vector
                return contains(next) && !visited[next.y * width + next.x]
            }
            guard let direction = unvisited.randomElement(using: &rng) else {
                stack.removeLast()
                continue
            }
            let next = current &+ direction.vector
            passages[current.y * width + current.x] |= direction.bit
            passages[next.y * width + next.x] |= direction.opposite.bit
            visited[next.y * width + next.x] = true
            stack.append(next)
        }
    }

    func contains(_ cell: Cell) -> Bool {
        cell.x >= 0 && cell.x < width && cell.y >= 0 && cell.y < height
    }

    func isOpen(_ cell: Cell, _ direction: Direction) -> Bool {
        contains(cell) && passages[cell.y * width + cell.x] & direction.bit != 0
    }

    func openDirections(from cell: Cell) -> [Direction] {
        Direction.allCases.filter { isOpen(cell, $0) }
    }
}

/// Wanders a maze the way the old Windows "3D Maze" screensaver did: walk down a corridor, pause to turn at
/// a junction, and about-face at a dead end. Pure logic; the scene just places a camera at the pose it returns.
struct MazeWalker {
    /// Where the camera is. `x` and `y` are in cell units (one cell = 1.0, row numbers grow southward);
    /// `yaw` is in radians, unwrapped, with 0 facing north.
    struct Pose: Equatable {
        var x: Double
        var y: Double
        var yaw: Double
    }

    static let cellsPerSecond = 0.9
    private static let turnSeconds = 0.5
    private static let aboutFaceSeconds = 0.9
    /// How likely it is to carry straight on, when straight on is one of the least-walked ways.
    private static let straightness = 0.6
    /// How likely it is to pick one of the least-walked ways at a junction rather than any way at all.
    private static let curiosity = 0.85

    let maze: Maze
    private var rng: SplitMix64
    private var cell: Maze.Cell
    private var heading: Maze.Direction
    private var yaw: Double

    private enum Phase {
        case moving(progress: Double)
        case turning(to: Double, elapsed: Double, duration: Double, then: Maze.Direction)
    }
    private var phase = Phase.moving(progress: 0)
    private var turnFrom = 0.0

    /// Cells fully crossed so far, so the scene knows when to start a fresh maze.
    private(set) var cellsTraveled = 0
    /// How often each cell has been entered. Used to prefer corridors it hasn't walked yet.
    private var visits: [Int]

    init(maze: Maze, seed: UInt64) {
        self.maze = maze
        rng = SplitMix64(seed: seed)
        cell = Maze.Cell(Int.random(in: 0..<maze.width, using: &rng), Int.random(in: 0..<maze.height, using: &rng))
        heading = maze.openDirections(from: cell).randomElement(using: &rng) ?? .north
        yaw = Self.yaw(for: heading)
        visits = Array(repeating: 0, count: maze.width * maze.height)
        visits[cell.y * maze.width + cell.x] = 1
    }

    static func yaw(for direction: Maze.Direction) -> Double {
        // A SceneKit camera looks down -Z, and a row number grows toward +Z.
        let v = direction.vector
        return atan2(-Double(v.x), -Double(v.y))
    }

    var pose: Pose {
        switch phase {
        case .moving(let progress):
            let v = heading.vector
            return Pose(x: Double(cell.x) + Double(v.x) * progress, y: Double(cell.y) + Double(v.y) * progress, yaw: yaw)
        case .turning(let to, let elapsed, let duration, _):
            let t = max(0, min(1, elapsed / duration))
            let eased = t * t * (3 - 2 * t)
            return Pose(x: Double(cell.x), y: Double(cell.y), yaw: turnFrom + (to - turnFrom) * eased)
        }
    }

    /// Moves forward `seconds`, however many corridors and turns that spans.
    @discardableResult
    mutating func advance(by seconds: Double) -> Pose {
        guard !maze.openDirections(from: cell).isEmpty else { return pose }   // a one-cell maze has nowhere to go
        var remaining = max(0, min(seconds, 0.25))

        while remaining > 0 {
            switch phase {
            case .moving(let progress):
                let step = Self.cellsPerSecond * remaining
                if progress + step < 1 {
                    phase = .moving(progress: progress + step)
                    remaining = 0
                } else {
                    remaining -= (1 - progress) / Self.cellsPerSecond
                    cell = cell &+ heading.vector
                    cellsTraveled += 1
                    visits[cell.y * maze.width + cell.x] += 1
                    chooseNextLeg()
                }
            case .turning(let to, let elapsed, let duration, let then):
                let left = duration - elapsed
                if remaining < left {
                    phase = .turning(to: to, elapsed: elapsed + remaining, duration: duration, then: then)
                    remaining = 0
                } else {
                    remaining -= left
                    heading = then
                    yaw = to
                    phase = .moving(progress: 0)
                }
            }
        }
        return pose
    }

    private mutating func chooseNextLeg() {
        let ahead = maze.openDirections(from: cell).filter { $0 != heading.opposite }
        let choice: Maze.Direction
        if ahead.isEmpty {
            choice = heading.opposite                                   // dead end
        } else {
            // Like someone exploring: mostly head for the way walked least, and keep going straight if that is one.
            func timesEntered(_ direction: Maze.Direction) -> Int {
                let next = cell &+ direction.vector
                return visits[next.y * maze.width + next.x]
            }
            let fewest = ahead.map(timesEntered).min() ?? 0
            let leastWalked = ahead.filter { timesEntered($0) == fewest }
            if leastWalked.contains(heading), Double.random(in: 0..<1, using: &rng) < Self.straightness {
                choice = heading
            } else if Double.random(in: 0..<1, using: &rng) < Self.curiosity {
                choice = leastWalked.randomElement(using: &rng) ?? heading
            } else {
                choice = ahead.randomElement(using: &rng) ?? heading
            }
        }

        guard choice != heading else {
            phase = .moving(progress: 0)
            return
        }
        // Turn the short way round, so the view never spins nearly a full circle.
        var delta = (Self.yaw(for: choice) - yaw).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
        turnFrom = yaw
        phase = .turning(to: yaw + delta, elapsed: 0,
                         duration: choice == heading.opposite ? Self.aboutFaceSeconds : Self.turnSeconds, then: choice)
    }
}
