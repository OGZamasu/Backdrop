import Foundation

/// More living backdrops, each a painted place whose creatures notice you, come over, do something, and run off when you wave.
enum SceneCatalogMore {
    static let all: [LensInfo] = entries.map { entry in
        // The creatures talk in speech bubbles, which would read backwards in a mirrored preview.
        var info = entry
        info.showsText = true
        return info
    }

    private static let entries: [LensInfo] = [
        LensCatalog.scene("scene-arctic", "Arctic", "🐧", "Northern lights over the ice: a polar bear rears up, penguins slide over, an owl lands on your hand.", hands: true) {
            VistaLens(stage: VistaArcticStage())
        },
        LensCatalog.scene("scene-outer-space", "Outer Space", "🚀", "Float among the stars: astronauts wave, a robot rolls up, and a flying saucer beams you up.", hands: true) {
            VistaLens(stage: VistaSpaceStage())
        },
        LensCatalog.scene("scene-dragon-castle", "Dragon Castle", "🐉", "A castle at dusk: knights salute you, bats circle, and a dragon breathes fire right beside you.", hands: true) {
            VistaLens(stage: VistaDragonStage())
        },
        LensCatalog.scene("scene-enchanted-forest", "Enchanted Forest", "🍄", "A glowing wood: fairies circle your head, a fox sits with you, and a giant cat peeks over the bushes.", hands: true) {
            VistaLens(stage: VistaForestStage())
        },
        LensCatalog.scene("scene-pirate-cove", "Pirate Cove", "🦜", "A tropical bay at sunset: parrots land on your hand, crabs snap, and a kraken rises from the sea.", hands: true) {
            VistaLens(stage: VistaPirateStage())
        },
    ]
}
