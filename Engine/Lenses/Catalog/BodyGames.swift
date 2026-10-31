import Foundation

/// Games played with your whole body.
enum BodyGames {
    static let all: [LensInfo] = [
        LensCatalog.game("meteor-dodge", "Meteor Dodge", "☄️", "Dodge the falling meteors and grab the shields and stars.") {
            GameLens<MeteorDodgeGame>(id: "meteor-dodge", needs: [.matte])
        },
        LensCatalog.game("hole-in-the-wall", "Hole in the Wall", "🕳️", "Strike the pose to fit through the hole in the wall before it hits you.") {
            GameLens<HoleInTheWallGame>(id: "hole-in-the-wall", needs: [.matte])
        },
        LensCatalog.game("bubble-wrap", "Bubble Wrap", "🫧", "Swipe and wave to pop the bubbles, and pop fast for combos.") {
            GameLens<BubbleWrapGame>(id: "bubble-wrap", needs: [.matte])
        },
        LensCatalog.game("keepy-uppy", "Keepy Uppy", "🏐", "Bump the beach ball up with your head and hands and never let it drop.") {
            GameLens<KeepyUppyGame>(id: "keepy-uppy", needs: [.matte])
        },
        LensCatalog.game("laser-limbo", "Laser Limbo", "🚨", "Duck and lean out of the way of the sweeping lasers.") {
            GameLens<LaserLimboGame>(id: "laser-limbo", needs: [.matte])
        },
        LensCatalog.game("punching-bag", "Punching Bag", "🥊", "Swing your arms into the bag: hard, fast hits score most.") {
            GameLens<PunchingBagGame>(id: "punching-bag", needs: [.matte])
        },
        LensCatalog.game("goalkeeper", "Goalkeeper", "🧤", "Get in front of each shot before it reaches the ring.") {
            GameLens<GoalkeeperGame>(id: "goalkeeper", needs: [.matte])
        },
        LensCatalog.game("ninja-stars", "Ninja Stars", "🥷", "Swat the throwing stars away with quick moves, or step aside.") {
            GameLens<NinjaStarsGame>(id: "ninja-stars", needs: [.matte])
        },
    ]
}
