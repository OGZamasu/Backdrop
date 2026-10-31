import Foundation

/// Living backdrops: a painted place with animals in it that notice you, come over, do something, and run off when you wave.
enum SceneCatalog {
    static let all: [LensInfo] = entries.map { entry in
        // The animals talk in speech bubbles, which would read backwards in a mirrored preview.
        var info = entry
        info.showsText = true
        return info
    }

    private static let entries: [LensInfo] = [
        LensCatalog.scene("scene-safari", "Safari", "🦁", "Golden hour on the savanna: lions, elephants and zebras come over to look at you.", hands: true) {
            SceneLens(style: SafariScene(), hands: true)
        },
        LensCatalog.scene("scene-jungle", "Jungle", "🌴", "A misty jungle: a monkey climbs on your head, parrots land on your hand, a tiger roars.", hands: true) {
            SceneLens(style: JungleScene(), hands: true)
        },
        LensCatalog.scene("scene-deep-sea", "Deep Sea", "🦈", "A coral reef: fish swirl around you, and a shark circles, then comes right at you.") {
            SceneLens(style: DeepSeaScene())
        },
        LensCatalog.scene("scene-dino-park", "Dino Park", "🦖", "A volcano valley: a T-rex charges you and roars, raptors dart about, pterodactyls circle.") {
            SceneLens(style: DinoScene())
        },
        LensCatalog.scene("scene-haunted", "Haunted Manor", "👻", "A moonlit graveyard: ghosts float over to say boo, bats circle your head and spiders drop in.") {
            SceneLens(style: HauntedScene())
        },
    ]
}
