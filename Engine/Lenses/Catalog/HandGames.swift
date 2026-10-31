import Foundation

/// Games played with your hands.
enum HandGames {
    static let all: [LensInfo] = [
        FlagshipHandGames.shown(LensCatalog.game("whack-a-mole", "Whack-a-Mole", "🔨", "Poke the moles with your fingers. Leave the bunnies and bombs alone.", hands: true) {
            HandGameLens<WhackAMoleGame>(id: "whack-a-mole", needs: [.hands])
        }),
        FlagshipHandGames.shown(LensCatalog.game("rock-paper-scissors", "Rock Paper Scissors", "✌️", "Best of five against the robot. Show your move on SHOOT.", hands: true) {
            HandGameLens<RockPaperScissorsGame>(id: "rock-paper-scissors", needs: [.hands])
        }),
        FlagshipHandGames.shown(LensCatalog.game("palm-pong", "Palm Pong", "🏓", "Steer the paddle with your palm and keep the ball in play.", hands: true) {
            HandGameLens<PalmPongGame>(id: "palm-pong", needs: [.hands])
        }),
    ]
}
