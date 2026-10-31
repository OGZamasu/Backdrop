import Foundation

/// Filters that put weather, light and particles around you.
enum WorldFilters {
    static let all: [LensInfo] = [
        LensCatalog.filter("confetti", "Confetti", "🎉", "Party poppers fire; the confetti tumbles down and settles on your shoulders.") { ConfettiCannonLens() },
        LensCatalog.filter("rain", "Rain", "🌧️", "A cold storm: rain splashes off your head, with the odd flash of lightning.") { RainstormLens() },
        LensCatalog.filter("fireflies", "Fireflies", "🌌", "Fireflies glow in the dark around you. Move and they come to look.") { FireflyGladeLens() },
        LensCatalog.filter("fireworks", "Fireworks", "🎆", "A night sky of fireworks bursting behind you.") { FireworkSkyLens() },
        LensCatalog.filter("blossoms", "Falling Blossoms", "🌸", "Cherry petals flutter down in slow drifts.") { PetalDriftLens() },
        LensCatalog.filter("northern-lights", "Northern Lights", "🏔️", "Green curtains of light ripple across a starry sky behind you.") { WorldNorthernLightsLens() },
        LensCatalog.filter("spotlight", "Spotlight", "🎤", "A stage spotlight finds you and follows you around.") { WorldSpotlightLens() },
        LensCatalog.filter("warp-speed", "Warp Speed", "🚀", "Stars rush past you, and every few seconds you jump to light speed.") { WorldWarpLens() },
        LensCatalog.filter("campfire", "Campfire", "🔥", "Sparks swirl up from a fire below, and its light flickers on you.") { WorldCampfireLens() },
        LensCatalog.filter("fog", "Fog", "🌫️", "Mist rolls through the room and parts around you.") { WorldFogLens() },
        LensCatalog.filter("bubbles", "Bubbles", "🫧", "Soap bubbles drift up, bump off you and pop.") { WorldBubblesLens() },
        LensCatalog.filter("disco", "Disco", "🪩", "A mirror ball throws spots of light across the room and you.") { WorldDiscoLens() },
        LensCatalog.filter("sunbeams", "Sunbeams", "🌅", "Golden afternoon light streams through a window, with dust glittering in it.") { WorldSunbeamsLens() },
        LensCatalog.filter("underwater", "Underwater", "🐠", "Rippling light from the surface plays over you, deep under the sea.") { WorldUnderwaterLens() },
        LensCatalog.filter("butterflies", "Butterflies", "🦋", "Butterflies flutter round and land on your head. Move and they fly off.") { WorldButterfliesLens() },
    ]
}
