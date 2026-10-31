import Foundation

/// Games played with your face.
enum FaceGames {
    static let all: [LensInfo] = [
        entry("staring-contest", "Staring Contest", "👁️", "Don't blink for 30 seconds while the screen tries to make you.") {
            FaceGameLens<StaringContestGame>(id: "staring-contest")
        },
        entry("brow-runner", "Brow Runner", "🤨", "Raise your eyebrows to jump the cacti, crates and puddles.") {
            FaceGameLens<BrowRunnerGame>(id: "brow-runner")
        },
        entry("face-snake", "Face Snake", "🐍", "Steer the snake with your nose. Eat fruit, don't bite your tail.") {
            FaceGameLens<FaceSnakeGame>(id: "face-snake")
        },
        entry("face-copycat", "Copy Cat", "😺", "Pull the same face as the cat before its timer runs out.") {
            FaceGameLens<CopyCatGame>(id: "face-copycat")
        },
        entry("face-space-blaster", "Space Blaster", "🚀", "Steer the ship with your head and open your mouth to fire.") {
            FaceGameLens<SpaceBlasterGame>(id: "face-space-blaster")
        },
        entry("face-keepy-uppy", "Head Ball", "⚽️", "Bounce the beach ball off your head. Don't let it drop.") {
            FaceGameLens<FaceKeepyUppyGame>(id: "face-keepy-uppy")
        },
        entry("face-tilt-racer", "Tilt Racer", "🏎️", "Tip your head to steer down the road and dodge the traffic.") {
            FaceGameLens<TiltRacerGame>(id: "face-tilt-racer")
        },
        entry("face-bubble-gum", "Bubble Gum", "🫧", "Open your mouth to blow a bubble. Close it before it pops.") {
            FaceGameLens<BubbleGumGame>(id: "face-bubble-gum")
        },
    ]

    /// Every face game puts words on the picture (its score, tips and end card), so each entry says so.
    private static func entry(_ id: String, _ name: String, _ glyph: String, _ blurb: String, make: @escaping () -> Lens) -> LensInfo {
        var info = LensCatalog.game(id, name, glyph, blurb, face: true, make: make)
        info.showsText = true
        return info
    }
}
