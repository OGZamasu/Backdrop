import Foundation

/// Filters you play with your hands.
enum HandFilters {
    static let all: [LensInfo] = [
        LensCatalog.filter("air-paint", "Air Paint", "🖌️", "Point a finger to draw glowing neon lines in the air. Open your palm to wipe.", hands: true) { AirPaintLens() },
        LensCatalog.filter("energy-ball", "Energy Ball", "🔵", "Hold your palm open to charge a ball of energy, then flick to throw it.", hands: true) { EnergyBallLens() },
        LensCatalog.filter("finger-lightning", "Finger Lightning", "⚡", "Electric arcs jump between your fingers, and from hand to hand.", hands: true) { FingerLightningLens() },
        LensCatalog.filter("sparkle-trail", "Sparkle Trail", "🪄", "Glitter streams off your fingertips: the faster you wave, the more.", hands: true) { SparkleTrailLens() },
        LensCatalog.filter("laser-pointer", "Laser Pointer", "🎯", "Point and a laser beam shoots from your fingertip to the edge of the picture.", hands: true) { LaserPointerLens() },
        LensCatalog.filter("fire-hands", "Fire Hands", "🔥", "Open your hand and it bursts into flame. Make a fist to put it out.", hands: true) { FireHandsLens() },
        LensCatalog.filter("frost-hands", "Frost Hands", "🧊", "Hold your hand still and ice creeps over it. Shake it to shatter the ice.", hands: true) { FrostHandsLens() },
        LensCatalog.filter("light-blade", "Light Blade", "🗡️", "Make a fist to light a glowing blade, then swing it around.", hands: true) { LightBladeLens() },
        LensCatalog.filter("magic-wand", "Magic Wand", "🌟", "Point a finger to hold a magic wand. Flick it to cast a spell.", hands: true) { MagicWandLens() },
        LensCatalog.filter("black-hole", "Black Hole", "🪐", "Hold up both hands and a black hole opens between them. Spread them to make it grow.", hands: true) { BlackHoleLens() },
        LensCatalog.filter("shockwave", "Shockwave", "💥", "Clap, or push your palm at the camera, to send a shockwave through the picture.", hands: true) { ShockwaveLens() },
        LensCatalog.filter("magnifier", "Magnifier", "🔍", "Hold a lens between your thumb and finger to magnify what is behind it.", hands: true) { MagnifierLens() },
        LensCatalog.filter("hologram-hand", "Hologram Hand", "💠", "Your hand becomes a glowing hologram, with a readout for every finger.", hands: true) { HologramHandLens() },
        LensCatalog.filter("rainbow-ribbon", "Rainbow Ribbon", "🎀", "A long silk ribbon trails from your hand. Twirl it like a gymnast.", hands: true) { RainbowRibbonLens() },
        LensCatalog.filter("bubble-wand", "Bubble Wand", "🫧", "Touch finger and thumb into a ring and wave it to blow bubbles. Poke them to pop.", hands: true) { BubbleWandLens() },
    ]
}
