import Foundation

/// One entry in the lens picker.
struct LensInfo: Identifiable, Hashable {
    enum Category: String, CaseIterable, Identifiable {
        case filters = "Filters"
        case faces = "Faces"
        case games = "Games"
        /// Living backdrops: a place you stand in, with things in it that notice you.
        case scenes = "Scenes"
        /// Lenses from the user's own Lenses folder.
        case custom = "My Lenses"
        var id: String { rawValue }
    }

    let id: String
    let name: String
    /// An emoji to stand for it in the picker.
    let glyph: String
    /// One line on what it does or how to play.
    let blurb: String
    let category: Category
    /// Whether it keeps a high score.
    let scored: Bool
    /// Whether it needs your face to be in view.
    let needsFace: Bool
    let make: () -> Lens
    /// Whether it needs a hand in view.
    var needsHands = false
    // Only lenses from a folder have these.
    var author: String? = nil
    var tags: [String] = []
    var warnings: [String] = []
    /// When its lens.json last changed, so an edited lens can be picked up again.
    var modified: Date? = nil
    var folder: URL? = nil
    /// Whether it puts words on the picture, which would read backwards in a mirrored preview.
    var showsText = false
    /// The shelf it sits on inside its category in the picker ("Looks", "Costumes", "Hands"). Nil leaves it to the picker's own
    /// table (`LensBrowserGroups`), which knows every built-in lens and sorts anything new by what it needs.
    var subgroup: String? = nil

    static func == (a: LensInfo, b: LensInfo) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Everything on offer, in the order the picker shows it.
enum LensCatalog {
    static let all: [LensInfo] = filters + faces + games + scenes

    static func info(for id: String) -> LensInfo? { all.first { $0.id == id } }
    static func lenses(in category: LensInfo.Category) -> [LensInfo] { all.filter { $0.category == category } }

    // The entries are kept in several files (one per kind of lens, see Catalog/) so that each can grow on its own.
    // These make an entry of each kind.

    static func filter(_ id: String, _ name: String, _ glyph: String, _ blurb: String, hands: Bool = false, make: @escaping () -> Lens) -> LensInfo {
        var info = LensInfo(id: id, name: name, glyph: glyph, blurb: blurb, category: .filters, scored: false, needsFace: false, make: make)
        info.needsHands = hands
        return info
    }

    static func face(_ id: String, _ name: String, _ glyph: String, _ blurb: String, make: @escaping () -> Lens) -> LensInfo {
        LensInfo(id: id, name: name, glyph: glyph, blurb: blurb, category: .faces, scored: false, needsFace: true, make: make)
    }

    static func game(_ id: String, _ name: String, _ glyph: String, _ blurb: String, face: Bool = false, hands: Bool = false,
                     make: @escaping () -> Lens) -> LensInfo {
        var info = LensInfo(id: id, name: name, glyph: glyph, blurb: blurb, category: .games, scored: true, needsFace: face, make: make)
        info.needsHands = hands
        return info
    }

    /// A living backdrop. `face` and `hands` say which of those it also reacts to; it always uses the silhouette.
    static func scene(_ id: String, _ name: String, _ glyph: String, _ blurb: String, face: Bool = false, hands: Bool = false,
                      make: @escaping () -> Lens) -> LensInfo {
        var info = LensInfo(id: id, name: name, glyph: glyph, blurb: blurb, category: .scenes, scored: false, needsFace: face, make: make)
        info.needsHands = hands
        return info
    }

    /// Marks an entry as putting words on the picture, so its preview isn't mirrored.
    static func shown(_ info: LensInfo) -> LensInfo {
        var copy = info
        copy.showsText = true
        return copy
    }

    static let filters: [LensInfo] = coreFilters + LookFilters.all + WorldFilters.all + HandFilters.all
    static let faces: [LensInfo] = coreFaces + HeadwearFaces.all + ExpressionFaces.all
    static let games: [LensInfo] = coreGames + FlagshipHandGames.all + HandGames.all + HandGamesMore.all + FaceGames.all + BodyGames.all
    static let scenes: [LensInfo] = SceneCatalog.all + SceneCatalogMore.all

    private static let coreFilters: [LensInfo] = [
        filter("aura", "Aura", "✨", "A glowing aura and rising sparks around you.") { AuraLens(style: .power) },
        filter("aura-rainbow", "Rainbow Aura", "🌈", "The same, in every colour.") { AuraLens(style: .rainbow) },
        filter("ghost-trails", "Ghost Trails", "👻", "Wave your arms and leave glowing echoes behind.") { GhostTrailsLens() },
        filter("comic", "Comic Book", "🖍️", "Flat colours and bold ink lines.") { ComicLens() },
        filter("pixel-art", "Pixel Art", "👾", "Big chunky pixels.") { PixelArtLens() },
        filter("glitch", "Glitch", "📺", "Signal tearing and colour splits, in bursts.") { GlitchLens() },
        filter("matrix", "Matrix Rain", "🟩", "Green code falls behind you.") { MatrixLens() },
        filter("mirror", "Mirror", "🪞", "Two of you, side by side.") { MirrorLens() },
        filter("kaleidoscope", "Kaleidoscope", "🔮", "You, a dozen times over, spinning.") { KaleidoscopeLens() },
        filter("snow", "Snowfall", "❄️", "Snow falls and settles on your head and shoulders.") { SnowLens() },
    ]

    private static let coreFaces: [LensInfo] = [
        face("big-eyes", "Big Eyes", "👀", "Eyes like saucers; raise your eyebrows and they grow even bigger.") { FunhouseLens(kind: .bigEyes) },
        face("chipmunk", "Chipmunk", "🐿️", "Puffy chipmunk cheeks that fill up when you smile.") { FunhouseLens(kind: .chipmunk) },
        face("big-mouth", "Big Mouth", "👄", "Your mouth swells as you open it wide.") { FunhouseLens(kind: .bigMouth) },
        face("rainbow-barf", "Rainbow", "🌈", "Open wide and a glossy rainbow pours out.") { BreathLens(kind: .rainbow) },
        face("fire-breath", "Fire Breath", "🔥", "Open wide and breathe fire, with sparks and smoke.") { BreathLens(kind: .fire) },
        face("laser-eyes", "Laser Eyes", "⚡️", "Raise your eyebrows and lasers burn out of your eyes.") { LaserEyesLens() },
    ]

    private static let coreGames: [LensInfo] = [
        game("balloon-pop", "Balloon Pop", "🎈", "Swat the balloons. Gold is worth five; bombs cost three.") {
            GameLens<BalloonGame>(id: "balloon-pop", needs: [.matte])
        },
        game("breakout", "Breakout", "🧱", "You are the paddle: bat the ball into the bricks.") {
            GameLens<BreakoutGame>(id: "breakout", needs: [.matte])
        },
        LensInfo(id: "ball-pit", name: "Ball Pit", glyph: "🛝", blurb: "Balls rain down and bounce off you.", category: .games,
                 scored: false, needsFace: false) { BallPitLens() },
        shown(game("mouth-catch", "Mouth Catch", "🍕", "Open wide to eat the food. Keep it shut for bombs.", face: true) {
            FaceGameLens<MouthCatchGame>(id: "mouth-catch")
        }),
        shown(game("flappy-face", "Flappy Face", "🐤", "Your face is the bird. Move your head to fly through the gaps.", face: true) {
            FaceGameLens<FlappyFaceGame>(id: "flappy-face")
        }),
    ]
}
