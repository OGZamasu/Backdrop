import Foundation

/// The first two games played with your hands.
enum FlagshipHandGames {
    static let all: [LensInfo] = [
        shown(LensCatalog.game("fruit-slash", "Fruit Slash", "🍉", "Your hand is the sword: slice the fruit, spare the bombs.", hands: true) {
            // The body cut stands in while a hand is blurred or out of view, so the game needs the silhouette too.
            HandGameLens<FruitSlashGame>(id: "fruit-slash", needs: [.hands, .matte])
        }),
        shown(LensCatalog.game("finger-guns", "Finger Guns", "🔫", "Point like a gun and drop your thumb to shoot the targets.", hands: true) {
            HandGameLens<FingerGunsGame>(id: "finger-guns", needs: [.hands])
        }),
    ]

    /// Hand games put a score and words on the picture.
    static func shown(_ info: LensInfo) -> LensInfo {
        var info = info
        info.showsText = true
        return info
    }
}
