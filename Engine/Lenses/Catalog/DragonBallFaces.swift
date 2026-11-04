import Foundation

/// The Dragon Ball lens: powering up and the moves, as one lens.
enum DragonBallFaces {
    static let all: [LensInfo] = [
        dragonBall,
    ]

    /// One entry for both halves: the form (hair, eyes, aura) and the moves share your hands and your face, and the form scales the moves.
    static let dragonBall: LensInfo = {
        var info = LensCatalog.face("dragon-ball", "Dragon Ball", "🐉",
                                    "Hold both fists up to power up through the Super Saiyan forms, then fire a Kamehameha and more from the show with your hands.") {
            SaiyanLens()
        }
        info.needsHands = true
        return info
    }()
}
