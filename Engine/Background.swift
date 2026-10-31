import Foundation

enum GradientPreset: String, Codable, CaseIterable, Hashable, Identifiable {
    case aurora, sunset, ocean, graphite
    case forest, candy, lavender, ember, mint, midnight, roseGold, neon
    case lagoon, nectar, iris, sage, glacier, cobalt

    var id: String { rawValue }
    var title: String {
        switch self {
        case .roseGold: return "Rose Gold"
        default: return rawValue.capitalized
        }
    }

    /// The last digits of the built-in's id. Fixed forever, and a switch so a new preset cannot forget to take one.
    fileprivate var builtInNumber: Int {
        switch self {
        case .aurora: return 10
        case .sunset: return 11
        case .ocean: return 12
        case .graphite: return 13
        case .forest: return 40
        case .candy: return 41
        case .lavender: return 42
        case .ember: return 43
        case .mint: return 44
        case .midnight: return 45
        case .roseGold: return 46
        case .neon: return 47
        case .lagoon: return 70
        case .nectar: return 71
        case .iris: return 72
        case .sage: return 73
        case .glacier: return 74
        case .cobalt: return 75
        }
    }

    /// RGB triples in 0...1. The first two form the base ramp, the last two drive the drifting highlights.
    var colors: [[Double]] {
        switch self {
        case .aurora:   return [[0.04, 0.10, 0.22], [0.05, 0.45, 0.42], [0.35, 0.85, 0.60], [0.45, 0.35, 0.90]]
        case .sunset:   return [[0.16, 0.07, 0.25], [0.85, 0.30, 0.35], [1.00, 0.65, 0.35], [0.95, 0.45, 0.60]]
        case .ocean:    return [[0.02, 0.10, 0.25], [0.05, 0.35, 0.60], [0.30, 0.70, 0.85], [0.15, 0.50, 0.75]]
        case .graphite: return [[0.08, 0.08, 0.10], [0.22, 0.23, 0.27], [0.40, 0.42, 0.48], [0.30, 0.32, 0.38]]
        case .forest:   return [[0.02, 0.10, 0.08], [0.06, 0.30, 0.20], [0.40, 0.70, 0.30], [0.12, 0.55, 0.50]]
        case .candy:    return [[0.52, 0.24, 0.66], [0.96, 0.46, 0.70], [1.00, 0.76, 0.82], [0.42, 0.86, 0.92]]
        case .lavender: return [[0.22, 0.17, 0.44], [0.55, 0.46, 0.80], [0.82, 0.72, 0.96], [0.58, 0.76, 0.96]]
        case .ember:    return [[0.09, 0.02, 0.04], [0.50, 0.11, 0.07], [1.00, 0.45, 0.10], [0.85, 0.18, 0.16]]
        case .mint:     return [[0.05, 0.30, 0.31], [0.34, 0.74, 0.64], [0.78, 0.96, 0.86], [0.42, 0.84, 0.92]]
        case .midnight: return [[0.01, 0.02, 0.08], [0.06, 0.08, 0.27], [0.20, 0.26, 0.66], [0.36, 0.20, 0.56]]
        case .roseGold: return [[0.38, 0.21, 0.25], [0.80, 0.52, 0.50], [0.99, 0.80, 0.66], [0.90, 0.60, 0.72]]
        case .neon:     return [[0.04, 0.02, 0.12], [0.22, 0.05, 0.44], [0.00, 0.90, 1.00], [1.00, 0.10, 0.70]]
        case .lagoon:   return [[0.02, 0.20, 0.25], [0.07, 0.64, 0.64], [0.72, 0.89, 0.35], [0.11, 0.44, 0.72]]
        case .nectar:   return [[0.23, 0.05, 0.18], [0.91, 0.20, 0.43], [1.00, 0.54, 0.24], [1.00, 0.79, 0.29]]
        case .iris:     return [[0.11, 0.08, 0.27], [0.29, 0.23, 0.82], [0.95, 0.63, 0.48], [0.63, 0.36, 0.84]]
        case .sage:     return [[0.18, 0.23, 0.18], [0.56, 0.65, 0.49], [0.85, 0.80, 0.64], [0.70, 0.42, 0.29]]
        case .glacier:  return [[0.06, 0.16, 0.29], [0.18, 0.44, 0.66], [0.89, 0.95, 0.98], [0.50, 0.72, 0.90]]
        case .cobalt:   return [[0.02, 0.04, 0.18], [0.12, 0.29, 1.00], [0.00, 0.76, 1.00], [0.42, 0.48, 1.00]]
        }
    }
}

/// A look made out of the camera feed itself, so it is the room behind you with something done to it.
enum CameraTreatment: String, Codable, CaseIterable, Hashable, Identifiable {
    case frosted, dimmed, noir, golden

    var id: String { rawValue }
    var title: String {
        switch self {
        case .frosted: return "Frosted Glass"
        case .dimmed: return "Dim Room"
        case .noir: return "Noir"
        case .golden: return "Golden Hour"
        }
    }
    /// The last digits of the built-in's id (see `GradientPreset.builtInNumber`).
    fileprivate var builtInNumber: Int {
        switch self {
        case .frosted: return 49
        case .dimmed: return 51
        case .noir: return 52
        case .golden: return 53
        }
    }
    var blurb: String {
        switch self {
        case .frosted: return "Your room seen through milky frosted glass."
        case .dimmed: return "Your room with the lights turned down low."
        case .noir: return "Your room, soft and in black and white."
        case .golden: return "Your room, out of focus in warm evening light."
        }
    }
}

/// A scene drawn in code: no files. Most move and never repeat exactly; the studio sets and a few landscapes are stills.
enum ProceduralStyle: String, Codable, CaseIterable, Hashable, Identifiable {
    case starfield, synthwave, lavaLamp, bokeh, plasma, fireflies, rain
    // Studio sets.
    case homeOffice, library, brickLoft, plantCorner, podcastStudio, galleryWall, woodSlats, coffeeShop
    // Places.
    case mountainLake, desertDunes, sunsetBeach, forestLight, snowyCabin, nightSkyline, tokyoRain
    // Abstract.
    case liquidMarble, northernLights, topographic, lowPoly, vaporwave
    // Live scenes and seasons.
    case driftingClouds, campfire, aquarium, nebula, cherryBlossom, digitalRain, autumnLeaves, holidayLights

    var id: String { rawValue }
    var title: String {
        switch self {
        case .starfield: return "Starfield"
        case .synthwave: return "Synthwave"
        case .lavaLamp: return "Lava Lamp"
        case .bokeh: return "Bokeh Lights"
        case .plasma: return "Plasma"
        case .fireflies: return "Fireflies"
        case .rain: return "Rainy Window"
        case .homeOffice: return "Home Office"
        case .library: return "Library"
        case .brickLoft: return "Brick Loft"
        case .plantCorner: return "Plant Corner"
        case .podcastStudio: return "Podcast Studio"
        case .galleryWall: return "Gallery Wall"
        case .woodSlats: return "Wood Slats"
        case .coffeeShop: return "Coffee Shop"
        case .mountainLake: return "Mountain Lake"
        case .desertDunes: return "Desert Dunes"
        case .sunsetBeach: return "Sunset Beach"
        case .forestLight: return "Forest Light"
        case .snowyCabin: return "Snowy Cabin"
        case .nightSkyline: return "Night Skyline"
        case .tokyoRain: return "Tokyo Rain"
        case .liquidMarble: return "Liquid Marble"
        case .northernLights: return "Northern Lights"
        case .topographic: return "Topographic"
        case .lowPoly: return "Low Poly"
        case .vaporwave: return "Vaporwave"
        case .driftingClouds: return "Drifting Clouds"
        case .campfire: return "Campfire"
        case .aquarium: return "Aquarium"
        case .nebula: return "Nebula"
        case .cherryBlossom: return "Cherry Blossom"
        case .digitalRain: return "Digital Rain"
        case .autumnLeaves: return "Autumn Leaves"
        case .holidayLights: return "Holiday Lights"
        }
    }
    /// The last digits of the built-in's id (see `GradientPreset.builtInNumber`).
    fileprivate var builtInNumber: Int {
        switch self {
        case .starfield: return 60
        case .synthwave: return 61
        case .lavaLamp: return 62
        case .bokeh: return 63
        case .plasma: return 64
        case .fireflies: return 65
        case .rain: return 66
        case .homeOffice: return 80
        case .library: return 81
        case .brickLoft: return 82
        case .plantCorner: return 83
        case .podcastStudio: return 84
        case .galleryWall: return 85
        case .woodSlats: return 86
        case .coffeeShop: return 87
        case .mountainLake: return 88
        case .desertDunes: return 89
        case .sunsetBeach: return 90
        case .forestLight: return 91
        case .snowyCabin: return 92
        case .nightSkyline: return 93
        case .tokyoRain: return 94
        case .liquidMarble: return 95
        case .northernLights: return 96
        case .topographic: return 97
        case .lowPoly: return 98
        case .vaporwave: return 99
        case .driftingClouds: return 100
        case .campfire: return 101
        case .aquarium: return 102
        case .nebula: return 103
        case .cherryBlossom: return 104
        case .digitalRain: return 105
        case .autumnLeaves: return 106
        case .holidayLights: return 107
        }
    }
    var blurb: String {
        switch self {
        case .starfield: return "Stars streaming past, as if you were at warp speed."
        case .synthwave: return "A neon sun over a glowing grid, rolling toward you."
        case .lavaLamp: return "Warm blobs of wax drifting up and down."
        case .bokeh: return "Out-of-focus warm lights floating by."
        case .plasma: return "Slow, smooth swirls of colour."
        case .fireflies: return "A summer night with fireflies blinking in the dark."
        case .rain: return "Rain running down a window onto blurred city lights."
        case .homeOffice: return "A bright home office with a window, books and a desk lamp."
        case .library: return "Shelves of books in dark wood, lit by warm lamps."
        case .brickLoft: return "Old brick, a tall bright window and two bare bulbs."
        case .plantCorner: return "A calm wall, a big leafy plant and soft daylight."
        case .podcastStudio: return "Dark sound panels and a glowing neon soundwave."
        case .galleryWall: return "A white wall hung with framed art."
        case .woodSlats: return "Warm oak slats lit softly from above and below."
        case .coffeeShop: return "A cosy café behind you, softly out of focus."
        case .mountainLake: return "Mountains at dawn, mirrored in a still lake."
        case .desertDunes: return "Smooth sand dunes under a deep blue sky."
        case .sunsetBeach: return "The sun setting into a glittering sea, waves washing in."
        case .forestLight: return "Shafts of sunlight falling through a misty wood."
        case .snowyCabin: return "Snow falling past the window of a warm log cabin."
        case .nightSkyline: return "A city at night across the river, its windows lit."
        case .tokyoRain: return "A rainy street at night, glowing with neon signs."
        case .liquidMarble: return "Green marble with gold veins, flowing very slowly."
        case .northernLights: return "Green and violet curtains of light over snowy pines."
        case .topographic: return "Contour lines of a map, drifting slowly."
        case .lowPoly: return "Faceted hills in teal, violet and coral."
        case .vaporwave: return "A pastel sun, palms and a checkered floor rolling by."
        case .driftingClouds: return "Soft white clouds sliding across a summer sky."
        case .campfire: return "A crackling campfire at night, sparks rising into the dark."
        case .aquarium: return "Fish gliding through rippling light under water."
        case .nebula: return "Drifting forever through glowing clouds of gas and stars."
        case .cherryBlossom: return "Pink petals drifting down from a tree in bloom."
        case .digitalRain: return "Green glyphs streaming down a dark screen."
        case .autumnLeaves: return "Red and gold leaves tumbling through a park in autumn."
        case .holidayLights: return "Strings of coloured bulbs glowing softly on a winter evening."
        }
    }
    /// Whether the scene moves. The still ones are painted once and cost nothing after.
    var isAnimated: Bool {
        switch self {
        case .homeOffice, .library, .brickLoft, .plantCorner, .podcastStudio, .galleryWall, .woodSlats, .coffeeShop,
             .mountainLake, .desertDunes, .lowPoly: return false
        default: return true
        }
    }
}

enum BackgroundKind: Codable, Hashable {
    /// Camera is passed through untouched.
    case passthrough
    case blur(radius: Double)
    case gradient(GradientPreset)
    /// The old Windows 3D Pipes screensaver.
    case pipes
    /// The old Windows 3D Maze screensaver.
    case maze
    case image(file: String)
    case video(file: String)
    /// A live window, matched by app (and optionally title) each time the background activates.
    case window(bundleID: String, title: String?)
    case display
    /// One flat colour, `hex` being "RRGGBB". `lit` adds the faint falloff of a softly lit wall, so it looks like a
    /// room rather than a swatch; leave it off for a colour that has to be exactly the same everywhere (chroma key).
    case solid(hex: String, lit: Bool)
    /// The camera feed with something done to it (frosted, dimmed, noir...).
    case treated(CameraTreatment)
    /// A moving scene drawn in code.
    case procedural(ProceduralStyle)
}

struct Background: Identifiable, Codable, Hashable {
    enum Origin: String, Codable { case builtIn, imported, generated }

    var id: UUID
    var name: String
    var kind: BackgroundKind
    var origin: Origin
    /// Shifts the backdrop slightly as you move, for a sense of depth.
    var parallax: Bool = false
    /// The text prompt, for AI-generated backgrounds.
    var prompt: String?
    var createdAt = Date()

    /// Whether the background changes over time and so needs a steady frame clock.
    var isLive: Bool {
        switch kind {
        case .video, .window, .display, .gradient, .pipes, .maze: return true
        case .procedural(let style): return style.isAnimated
        default: return false
        }
    }
}

extension Background {
    private static func builtIn(_ n: Int, _ name: String, _ kind: BackgroundKind) -> Background {
        Background(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!,
                   name: name, kind: kind, origin: .builtIn)
    }

    // The numbers below are the ids and never change: rules and saved choices refer to built-ins by id.
    // 1-3 and 48-53 camera looks, 10-13, 40-47 and 70-75 gradients, 30-31 screensavers, 54-59 colours, 60-66 live scenes,
    // 80-107 the scenes added in round two (rooms, places, abstract and live).
    static let off = builtIn(1, "Off", .passthrough)
    static let softBlur = builtIn(2, "Soft Blur", .blur(radius: 14))
    static let heavyBlur = builtIn(3, "Heavy Blur", .blur(radius: 40))
    static let lightBlur = builtIn(48, "Light Blur", .blur(radius: 6))

    static let pipes = builtIn(30, "3D Pipes", .pipes)
    static let maze = builtIn(31, "3D Maze", .maze)

    private static func gradient(_ preset: GradientPreset) -> Background {
        builtIn(preset.builtInNumber, preset.title, .gradient(preset))
    }

    static let whiteWall = builtIn(54, "White Wall", .solid(hex: "F2F1EE", lit: true))
    static let studioGrey = builtIn(55, "Studio Grey", .solid(hex: "7E8185", lit: true))
    static let chromaGreen = builtIn(56, "Chroma Green", .solid(hex: "00B140", lit: false))
    static let deepNavy = builtIn(57, "Deep Navy", .solid(hex: "14213D", lit: true))
    static let charcoal = builtIn(58, "Charcoal", .solid(hex: "2A2C30", lit: true))
    static let sand = builtIn(59, "Sand", .solid(hex: "D8CAB2", lit: true))

    /// The first nine keep the order they have always had; the rest follow, grouped by sort, older ones first so a grid
    /// someone knows does not shuffle: live scenes, camera looks, gradients, colours, then the newer scenes and gradients.
    static let builtIns: [Background] =
        [off, softBlur, heavyBlur, pipes, maze]
        + [GradientPreset.aurora, .sunset, .ocean, .graphite].map(gradient)
        + [ProceduralStyle.starfield, .synthwave, .lavaLamp, .bokeh, .plasma, .fireflies, .rain].map { builtIn($0.builtInNumber, $0.title, .procedural($0)) }
        + [lightBlur]
        + CameraTreatment.allCases.map { builtIn($0.builtInNumber, $0.title, .treated($0)) }
        + [GradientPreset.forest, .candy, .lavender, .ember, .mint, .midnight, .roseGold, .neon].map(gradient)
        + [whiteWall, studioGrey, chromaGreen, deepNavy, charcoal, sand]
        + newScenes.map { builtIn($0.builtInNumber, $0.title, .procedural($0)) }
        + [GradientPreset.lagoon, .nectar, .iris, .sage, .glacier, .cobalt].map(gradient)

    /// The scenes added after the first seven, in the order the grid shows them: rooms, places, abstract, then live ones.
    private static let newScenes: [ProceduralStyle] = [
        .homeOffice, .library, .brickLoft, .plantCorner, .podcastStudio, .galleryWall, .woodSlats, .coffeeShop,
        .mountainLake, .desertDunes, .sunsetBeach, .forestLight, .snowyCabin, .nightSkyline, .tokyoRain,
        .liquidMarble, .northernLights, .topographic, .lowPoly, .vaporwave,
        .driftingClouds, .campfire, .aquarium, .nebula, .cherryBlossom, .digitalRain, .autumnLeaves, .holidayLights,
    ]
}
