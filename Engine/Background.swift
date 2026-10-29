import Foundation

enum GradientPreset: String, Codable, CaseIterable, Hashable, Identifiable {
    case aurora, sunset, ocean, graphite

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// RGB triples in 0...1. The first two form the base ramp, the last two drive the drifting highlights.
    var colors: [[Double]] {
        switch self {
        case .aurora:   return [[0.04, 0.10, 0.22], [0.05, 0.45, 0.42], [0.35, 0.85, 0.60], [0.45, 0.35, 0.90]]
        case .sunset:   return [[0.16, 0.07, 0.25], [0.85, 0.30, 0.35], [1.00, 0.65, 0.35], [0.95, 0.45, 0.60]]
        case .ocean:    return [[0.02, 0.10, 0.25], [0.05, 0.35, 0.60], [0.30, 0.70, 0.85], [0.15, 0.50, 0.75]]
        case .graphite: return [[0.08, 0.08, 0.10], [0.22, 0.23, 0.27], [0.40, 0.42, 0.48], [0.30, 0.32, 0.38]]
        }
    }
}

enum BackgroundKind: Codable, Hashable {
    /// Camera is passed through untouched.
    case passthrough
    case blur(radius: Double)
    case gradient(GradientPreset)
    /// The old Windows 3D Pipes screensaver.
    case pipes
    /// The old Windows 3D Maze screensaver.
    case maze
    case image(file: String)
    case video(file: String)
    /// A live window, matched by app (and optionally title) each time the background activates.
    case window(bundleID: String, title: String?)
    case display
}

struct Background: Identifiable, Codable, Hashable {
    enum Origin: String, Codable { case builtIn, imported, generated }

    var id: UUID
    var name: String
    var kind: BackgroundKind
    var origin: Origin
    /// Shifts the backdrop slightly as you move, for a sense of depth.
    var parallax: Bool = false
    /// The text prompt, for AI-generated backgrounds.
    var prompt: String?
    var createdAt = Date()

    /// Whether the background changes over time and so needs a steady frame clock.
    var isLive: Bool {
        switch kind {
        case .video, .window, .display, .gradient, .pipes, .maze: return true
        default: return false
        }
    }
}

extension Background {
    private static func builtIn(_ n: Int, _ name: String, _ kind: BackgroundKind) -> Background {
        Background(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!,
                   name: name, kind: kind, origin: .builtIn)
    }

    static let off = builtIn(1, "Off", .passthrough)
    static let softBlur = builtIn(2, "Soft Blur", .blur(radius: 14))
    static let heavyBlur = builtIn(3, "Heavy Blur", .blur(radius: 40))

    static let pipes = builtIn(30, "3D Pipes", .pipes)
    static let maze = builtIn(31, "3D Maze", .maze)

    static let builtIns: [Background] =
        [off, softBlur, heavyBlur, pipes, maze]
        + GradientPreset.allCases.enumerated().map { builtIn(10 + $0.offset, $0.element.title, .gradient($0.element)) }
}
