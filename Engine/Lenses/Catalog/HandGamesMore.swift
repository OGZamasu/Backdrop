import Foundation

/// More games played with your hands.
enum HandGamesMore {
    static let all: [LensInfo] = [
        LensCatalog.game("magic-duel", "Magic Duel", "🪄", "Push an open hand to throw fireballs at the shadows. Make a fist to shield.", hands: true) {
            GameLens<HandPlayMagicDuel>(id: "magic-duel", needs: [.hands])
        },
        LensCatalog.game("beat-pads", "Beat Pads", "🥁", "Tap each glowing pad just as its ring closes in.", hands: true) {
            GameLens<HandPlayBeatPads>(id: "beat-pads", needs: [.hands])
        },
        LensCatalog.game("air-hockey", "Air Hockey", "🏒", "Your hands are the mallets. Score in the top goal, guard the bottom.", hands: true) {
            GameLens<HandPlayAirHockey>(id: "air-hockey", needs: [.hands])
        },
        LensCatalog.game("palm-star-catcher", "Star Catcher", "🌟", "Catch falling stars in an open hand, then make a fist to bank them.", hands: true) {
            GameLens<HandPlayStarCatcher>(id: "palm-star-catcher", needs: [.hands])
        },
        LensCatalog.game("hand-simon", "Hand Simon", "🧠", "Watch the run of hand shapes, then copy it in order.", hands: true) {
            GameLens<HandPlaySimon>(id: "hand-simon", needs: [.hands])
        },
        LensCatalog.game("palm-juggle", "Juggle", "🤹", "Bounce the balls up with your palms and keep them all in the air.", hands: true) {
            GameLens<HandPlayJuggle>(id: "palm-juggle", needs: [.hands])
        },
    ]
}
