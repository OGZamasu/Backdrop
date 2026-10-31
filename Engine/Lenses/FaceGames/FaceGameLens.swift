import AppKit
import CoreImage

/// How a round ended, which picks the result card's colour and the status line.
enum FaceGameEnding: Equatable {
    /// Lost, with a headline saying how: "YOU BLINKED!".
    case lost(String)
    /// Beat the game outright.
    case won(String)
    /// The clock ran out: not a loss, just a score.
    case timeUp(String)
}

/// One item in the status plate of a face game.
enum FaceGameChip: Equatable {
    /// Lives as hearts: `left` full ones out of `of`.
    case hearts(Int, of: Int)
    /// Seconds left on the clock, of how many.
    case clock(Double, of: Double)
    /// A score multiplier; shown only above one.
    case multiplier(Int)
    case text(String)
}

/// What the little "how to play" face acts out on the cards and in hints.
enum FaceGameMove: Equatable, CaseIterable {
    case keepEyesOpen, raiseBrows, openMouth, moveHead, nodHead, steerNose, tiltHead, smile, copyFaces
}

/// A game played with your face. On top of `Game`, it names the move the mascot acts out on its cards, and says what goes in the
/// status plate, how the round ended and a tip for the bottom of the picture; these fill in the shared screens.
protocol FaceGame: Game {
    static var move: FaceGameMove { get }
    var chips: [FaceGameChip] { get }
    var ending: FaceGameEnding { get }
    /// One line on the result card about how the round went: "Eyes open for 12.3 seconds".
    var endLine: String { get }
    /// A short tip for the pill at the bottom of the picture, while there is something worth saying.
    var tip: String? { get }
}

extension FaceGame {
    static var accent: SIMD3<Double> { FaceGamePalette.sky }
    static var icon: GameUIIcon { .face(move) }
    /// Face games teach with their live `tip` instead.
    static var onboarding: [String] { [] }
    var chips: [FaceGameChip] { [.text(summary)] }
    var ending: FaceGameEnding { .lost("GAME OVER") }
    var endLine: String { "" }
    var tip: String? { nil }

    var readout: GameUIReadout {
        var readout = GameUIReadout(score: score, tip: tip)
        for chip in chips {
            switch chip {
            case .hearts(let left, let of): readout.lives = (max(0, left), of)
            case .clock(let left, let of): readout.time = (max(0, left), of)
            case .multiplier(let k): readout.combo = k
            case .text(let words): readout.label = words
            }
        }
        return readout
    }

    var result: GameUIResult {
        switch ending {
        case .won(let words): return GameUIResult(headline: words, line: endLine, kind: .won)
        case .lost(let words): return GameUIResult(headline: words, line: endLine, kind: .lost)
        case .timeUp(let words): return GameUIResult(headline: words, line: endLine, kind: .timeUp)
        }
    }
}

/// Runs a face game: the shared runner and screens, waiting for a face rather than a body. A face has to stay in view a little
/// longer before a round starts (the tracker flickers as you sit down), and the game's art is resampled quickly, since face games
/// draw many scaled sprites.
final class FaceGameLens<G: FaceGame>: GameLens<G> {
    override class var settleSeconds: Double { 0.6 }
    override class var artInterpolation: CGInterpolationQuality? { .low }

    init(id: String, store: ScoreStore = DefaultsScoreStore(), size: CGSize = CGSize(width: 1280, height: 720), make: ((CGSize, UInt64) -> G)? = nil) {
        super.init(id: id, needs: [.face], store: store, size: size, make: make)
    }
}
