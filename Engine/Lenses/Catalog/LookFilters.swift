import Foundation

/// Filters that change how the whole picture looks: a grade, a texture, a way of drawing.
enum LookFilters {
    static let all: [LensInfo] = [
        LensCatalog.filter("neon-outline", "Neon Outline", "💡", "The room goes dark and a glowing neon tube traces you.") { LookNeonLens() },
        thermal,
        LensCatalog.filter("old-film", "Old Film", "🎞️", "Faded silver film with grain, dust and flicker.") { LookOldFilmLens() },
        vhs,
        nightVision,
        LensCatalog.filter("halftone", "Halftone Print", "📰", "A pop-art newspaper print made of coloured dots.") { LookHalftoneLens() },
        LensCatalog.filter("pencil-sketch", "Pencil Sketch", "✏️", "A pencil drawing on paper that shimmers as it is redrawn.") { LookPencilLens() },
        LensCatalog.filter("oil-painting", "Oil Painting", "🎨", "Thick strokes of paint on canvas.") { LookOilLens() },
        LensCatalog.filter("cyberpunk", "Cyberpunk", "🌆", "Teal and pink neon, glowing lights and long streaks.") { LookCyberpunkLens() },
        LensCatalog.filter("duotone", "Duotone", "🟣", "A two-colour poster that slowly changes ink.") { LookDuotoneLens() },
        LensCatalog.filter("film-noir", "Film Noir", "🕵️", "Black and white, deep shadows and light through the blinds.") { LookNoirLens() },
        instantPhoto,
        LensCatalog.filter("super-eight", "Super 8", "📽️", "A warm, grainy home movie that flickers in its frame.") { LookSuperEightLens() },
        LensCatalog.filter("blockbuster", "Blockbuster", "🎬", "Teal and orange movie colour with widescreen bars.") { LookBlockbusterLens() },
        LensCatalog.filter("dreamy-glow", "Dreamy", "☁️", "Soft glowing light, pastel colour and drifting bokeh.") { LookDreamyLens() },
        LensCatalog.filter("golden-hour", "Magic Hour", "🌅", "Warm low sun from the side, with a gentle lens flare.") { LookGoldenHourLens() },
        LensCatalog.filter("hologram", "Hologram", "💠", "You as a flickering blue hologram in a dark room.") { LookHologramLens() },
        LensCatalog.filter("stained-glass", "Stained Glass", "⛪", "You in pieces of jewel-coloured glass and lead.") { LookStainedGlassLens() },
        LensCatalog.filter("watercolour", "Watercolour", "💧", "Soft washes of paint bleeding on textured paper.") { LookWatercolourLens() },
        blueprint,
    ]

    // These put words on the picture, which would read backwards in a mirrored preview.
    private static var thermal: LensInfo {
        var info = LensCatalog.filter("thermal", "Thermal Camera", "🌡️", "A heat-camera view with a crosshair and a temperature readout.") { LookThermalLens() }
        info.showsText = true
        return info
    }

    private static var vhs: LensInfo {
        var info = LensCatalog.filter("vhs", "VHS Tape", "📼", "A worn home video with PLAY, a date stamp and tracking glitches.") { LookVHSLens() }
        info.showsText = true
        return info
    }

    private static var instantPhoto: LensInfo {
        var info = LensCatalog.filter("instant-photo", "Instant Photo", "📸", "A fresh instant photo that develops as you watch.") { LookInstantLens() }
        info.showsText = true
        return info
    }

    private static var blueprint: LensInfo {
        var info = LensCatalog.filter("blueprint", "Blueprint", "📐", "A technical drawing of you, in white on blueprint blue.") { LookBlueprintLens() }
        info.showsText = true
        return info
    }

    private static var nightVision: LensInfo {
        var info = LensCatalog.filter("night-vision", "Night Vision", "🔦", "Green night-vision video with a blinking REC.") { LookNightVisionLens() }
        info.showsText = true
        return info
    }
}
