import Foundation

/// One entry in the lens picker.
struct LensInfo: Identifiable, Hashable {
    enum Category: String, CaseIterable, Identifiable {
        case filters = "Filters"
        case faces = "Faces"
        case games = "Games"
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

    static func == (a: LensInfo, b: LensInfo) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Everything on offer, in the order the picker shows it.
enum LensCatalog {
    static let all: [LensInfo] = filters + faces + games

    static func info(for id: String) -> LensInfo? { all.first { $0.id == id } }
    static func lenses(in category: LensInfo.Category) -> [LensInfo] { all.filter { $0.category == category } }

    private static func filter(_ id: String, _ name: String, _ glyph: String, _ blurb: String, make: @escaping () -> Lens) -> LensInfo {
        LensInfo(id: id, name: name, glyph: glyph, blurb: blurb, category: .filters, scored: false, needsFace: false, make: make)
    }

    private static func face(_ id: String, _ name: String, _ glyph: String, _ blurb: String, make: @escaping () -> Lens) -> LensInfo {
        LensInfo(id: id, name: name, glyph: glyph, blurb: blurb, category: .faces, scored: false, needsFace: true, make: make)
    }

    private static func game(_ id: String, _ name: String, _ glyph: String, _ blurb: String, face: Bool = false, make: @escaping () -> Lens) -> LensInfo {
        LensInfo(id: id, name: name, glyph: glyph, blurb: blurb, category: .games, scored: true, needsFace: face, make: make)
    }

    static let filters: [LensInfo] = [
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

    static let faces: [LensInfo] = [
        face("cat", "Cat Ears", "🐱", "Ears, a nose and whiskers.") { PropsLens(kind: .cat) },
        face("shades", "Deal With It", "😎", "Sunglasses drop onto your face.") { PropsLens(kind: .shades) },
        face("crown", "Crown", "👑", "Royalty.") { PropsLens(kind: .crown) },
        face("party-hat", "Party Hat", "🥳", "Every call is a party.") { PropsLens(kind: .party) },
        face("big-eyes", "Big Eyes", "👀", "Eyes like saucers.") { FunhouseLens(kind: .bigEyes) },
        face("chipmunk", "Chipmunk", "🐿️", "Cheeks full of nuts.") { FunhouseLens(kind: .chipmunk) },
        face("big-mouth", "Big Mouth", "👄", "A mouth that gets bigger when you open it.") { FunhouseLens(kind: .bigMouth) },
        face("rainbow-barf", "Rainbow", "🌈", "Open wide.") { BreathLens(kind: .rainbow) },
        face("fire-breath", "Fire Breath", "🔥", "Open wide and breathe out.") { BreathLens(kind: .fire) },
        face("laser-eyes", "Laser Eyes", "⚡️", "Raise your eyebrows.") { LaserEyesLens() },
    ]

    static let games: [LensInfo] = [
        game("balloon-pop", "Balloon Pop", "🎈", "Swat the balloons. Gold is worth five; bombs cost three.") {
            GameLens<BalloonGame>(id: "balloon-pop", needs: [.matte])
        },
        game("breakout", "Breakout", "🧱", "You are the paddle: bat the ball into the bricks.") {
            GameLens<BreakoutGame>(id: "breakout", needs: [.matte])
        },
        LensInfo(id: "ball-pit", name: "Ball Pit", glyph: "🔴", blurb: "Balls rain down and bounce off you.", category: .games,
                 scored: false, needsFace: false) { BallPitLens() },
        game("mouth-catch", "Mouth Catch", "🍕", "Open wide to eat the food. Shut up for bombs.", face: true) {
            GameLens<MouthCatchGame>(id: "mouth-catch", needs: [.face])
        },
        game("flappy-face", "Flappy Face", "🐤", "Your face is the bird. Move your head to fly through the gaps.", face: true) {
            GameLens<FlappyFaceGame>(id: "flappy-face", needs: [.face])
        },
    ]
}
