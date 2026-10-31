import Foundation

/// The shelves inside each lens category ("Looks", "Weather & Light", "Hands" among the filters), and which lens sits on which.
///
/// Kept as a table keyed by lens id rather than as a field filled in by every catalog file, so lenses being added elsewhere
/// land somewhere sensible without anyone touching this file: a lens that names its own `subgroup` goes there, a lens the table
/// knows goes where the table says, and anything else is sorted by what it needs (a hand filter to "Hands", a face game to
/// "Face") or put on the category's "More" shelf.
enum LensBrowserGroups {
    /// The name of the catch-all shelf at the end of every category.
    static let more = "More"

    /// The shelves of a category, in the order the picker shows them. "More" is always last.
    static func order(for category: LensInfo.Category) -> [String] {
        switch category {
        case .filters: return ["Looks", "Weather & Light", "Hands", more]
        case .faces: return ["Costumes", "Expressions", "Funhouse", more]
        case .games: return ["Hands", "Face", "Body", "Classic", more]
        case .scenes: return ["Wildlife", "Fantasy", "After Dark", more]
        case .custom: return ["Face", "Screen", more]
        }
    }

    /// SF Symbol for a shelf, used on its chip and header.
    static func symbol(for group: String, in category: LensInfo.Category) -> String {
        switch (category, group) {
        case (.filters, "Looks"): return "camera.filters"
        case (.filters, "Weather & Light"): return "cloud.sun"
        case (_, "Hands"): return "hand.raised"
        case (.faces, "Costumes"): return "theatermasks"
        case (.faces, "Expressions"): return "face.smiling"
        case (.faces, "Funhouse"): return "eyes"
        case (_, "Face"): return "face.smiling"
        case (.games, "Body"): return "figure.wave"
        case (.games, "Classic"): return "gamecontroller"
        case (.scenes, "Wildlife"): return "pawprint"
        case (.scenes, "Fantasy"): return "wand.and.stars"
        case (.scenes, "After Dark"): return "moon.stars"
        case (.custom, "Screen"): return "rectangle.on.rectangle"
        default: return "square.grid.2x2"
        }
    }

    /// Every built-in lens and its shelf. A lens missing from here still gets one (see `group(for:)`).
    static let table: [String: String] = [
        // Filters
        "comic": "Looks", "pixel-art": "Looks", "glitch": "Looks", "mirror": "Looks", "kaleidoscope": "Looks", "neon-outline": "Looks",
        "old-film": "Looks", "halftone": "Looks", "pencil-sketch": "Looks", "oil-painting": "Looks", "cyberpunk": "Looks",
        "duotone": "Looks", "film-noir": "Looks", "super-eight": "Looks", "blockbuster": "Looks", "dreamy-glow": "Looks",
        "golden-hour": "Looks", "hologram": "Looks", "stained-glass": "Looks", "watercolour": "Looks", "thermal": "Looks", "vhs": "Looks",
        "instant-photo": "Looks", "blueprint": "Looks", "night-vision": "Looks",
        "aura": "Weather & Light", "aura-rainbow": "Weather & Light", "ghost-trails": "Weather & Light", "matrix": "Weather & Light",
        "snow": "Weather & Light", "confetti": "Weather & Light", "rain": "Weather & Light", "fireflies": "Weather & Light",
        "fireworks": "Weather & Light", "blossoms": "Weather & Light", "northern-lights": "Weather & Light",
        "spotlight": "Weather & Light", "warp-speed": "Weather & Light", "campfire": "Weather & Light", "fog": "Weather & Light",
        "bubbles": "Weather & Light", "disco": "Weather & Light", "sunbeams": "Weather & Light", "underwater": "Weather & Light",
        "butterflies": "Weather & Light",
        "air-paint": "Hands", "energy-ball": "Hands", "finger-lightning": "Hands", "sparkle-trail": "Hands", "laser-pointer": "Hands",
        "fire-hands": "Hands", "frost-hands": "Hands", "light-blade": "Hands", "magic-wand": "Hands", "black-hole": "Hands",
        "shockwave": "Hands", "magnifier": "Hands", "hologram-hand": "Hands", "rainbow-ribbon": "Hands", "bubble-wand": "Hands",
        // Faces
        "dress-cat": "Costumes", "dress-shades": "Costumes", "dress-crown": "Costumes", "dress-party-hat": "Costumes",
        "dress-dog": "Costumes", "dress-bunny": "Costumes", "dress-devil": "Costumes", "dress-angel": "Costumes",
        "dress-pirate": "Costumes", "dress-wizard": "Costumes", "dress-santa": "Costumes", "dress-gentleman": "Costumes",
        "dress-clown": "Costumes", "dress-flower-crown": "Costumes", "dress-headphones": "Costumes", "dress-cowboy": "Costumes",
        "dress-viking": "Costumes", "dress-propeller": "Costumes", "dress-astronaut": "Costumes", "dress-chef": "Costumes",
        "dress-fox": "Costumes", "dress-panda": "Costumes", "dress-tabby": "Costumes", "dress-unicorn": "Costumes",
        "dress-mermaid": "Costumes", "dress-robot": "Costumes", "dress-reindeer": "Costumes", "dress-witch": "Costumes",
        "alien-face": "Costumes",
        "heart-eyes": "Expressions", "star-eyes": "Expressions", "happy-tears": "Expressions", "storm-cloud": "Expressions",
        "emoji-mask": "Expressions", "mood-aura": "Expressions", "laser-eyes": "Expressions", "rainbow-barf": "Expressions",
        "fire-breath": "Expressions", "anime-eyes": "Expressions", "sweat-drop": "Expressions", "fuming": "Expressions",
        "dizzy-stars": "Expressions", "kiss-marks": "Expressions", "sleepy-zzz": "Expressions", "mind-blown": "Expressions",
        "thought-bubble": "Expressions", "face-scanner": "Expressions", "cyber-visor": "Expressions", "comic-pow": "Expressions",
        "big-eyes": "Funhouse", "chipmunk": "Funhouse", "big-mouth": "Funhouse", "swirl-face": "Funhouse", "squeeze-face": "Funhouse",
        "googly-eyes": "Funhouse", "pinocchio": "Funhouse", "balloon-head": "Funhouse", "tiny-head": "Funhouse", "long-face": "Funhouse",
        "mirror-face": "Funhouse", "melting-face": "Funhouse", "glitch-face": "Funhouse",
        // Games
        "fruit-slash": "Hands", "finger-guns": "Hands", "whack-a-mole": "Hands", "rock-paper-scissors": "Hands", "magic-duel": "Hands",
        "beat-pads": "Hands", "palm-star-catcher": "Hands", "hand-simon": "Hands", "palm-juggle": "Hands",
        "mouth-catch": "Face", "staring-contest": "Face", "brow-runner": "Face", "face-copycat": "Face", "face-keepy-uppy": "Face",
        "face-bubble-gum": "Face",
        "balloon-pop": "Body", "ball-pit": "Body", "meteor-dodge": "Body", "hole-in-the-wall": "Body", "bubble-wrap": "Body",
        "keepy-uppy": "Body", "laser-limbo": "Body", "punching-bag": "Body", "goalkeeper": "Body", "ninja-stars": "Body",
        "breakout": "Classic", "palm-pong": "Classic", "face-snake": "Classic", "flappy-face": "Classic", "air-hockey": "Classic",
        "face-space-blaster": "Classic", "face-tilt-racer": "Classic",
        // Scenes
        "scene-safari": "Wildlife", "scene-jungle": "Wildlife", "scene-deep-sea": "Wildlife", "scene-dino-park": "Wildlife",
        "scene-arctic": "Wildlife",
        "scene-dragon-castle": "Fantasy", "scene-enchanted-forest": "Fantasy", "scene-pirate-cove": "Fantasy",
        "scene-outer-space": "Fantasy",
        "scene-haunted": "After Dark",
    ]

    /// The shelf a lens sits on.
    static func group(for info: LensInfo) -> String {
        let order = order(for: info.category)
        if let own = info.subgroup, !own.isEmpty { return own }
        if let known = table[info.id], order.contains(known) { return known }
        switch info.category {
        case .filters where info.needsHands: return "Hands"
        case .games where info.needsHands: return "Hands"
        case .games where info.needsFace: return "Face"
        case .custom: return info.needsFace ? "Face" : "Screen"
        default: return more
        }
    }

    /// The lenses of one category split into its shelves, in shelf order, leaving out empty ones. A shelf a lens named for
    /// itself that the category doesn't list comes just before "More".
    static func sections(_ lenses: [LensInfo], in category: LensInfo.Category) -> [(group: String, lenses: [LensInfo])] {
        let mine = lenses.filter { $0.category == category }
        var buckets: [String: [LensInfo]] = [:]
        var extra: [String] = []
        let known = order(for: category)
        for info in mine {
            let group = group(for: info)
            if !known.contains(group), !extra.contains(group) { extra.append(group) }
            buckets[group, default: []].append(info)
        }
        let names = known.dropLast() + extra + [more]
        return names.compactMap { name in buckets[name].map { (name, $0) } }
    }

    // MARK: Searching

    /// Whether a lens matches what was typed: every word has to be found in its name, blurb, category, shelf, author or tags.
    static func matches(_ info: LensInfo, query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard !words.isEmpty else { return true }
        let haystack = ([info.name, info.blurb, info.category.rawValue, group(for: info), info.author ?? ""] + info.tags + needWords(info))
            .joined(separator: " ").lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }

    /// Extra words a lens can be found by: "hand" finds the lenses played with a hand, "score" the games.
    private static func needWords(_ info: LensInfo) -> [String] {
        var words: [String] = []
        if info.needsHands { words.append("hand hands") }
        if info.needsFace { words.append("face") }
        if info.scored { words.append("game score") }
        return words
    }

    /// Search results, best first: names that start with the query, then names that contain it, then everything else that matches.
    static func search(_ lenses: [LensInfo], query: String) -> [LensInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return lenses }
        let hits = lenses.filter { matches($0, query: q) }
        func rank(_ info: LensInfo) -> Int {
            let name = info.name.lowercased()
            if name.hasPrefix(q) { return 0 }
            if name.contains(q) { return 1 }
            return 2
        }
        return hits.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: What a lens needs

    /// What a lens needs to see, said plainly, for the detail panel.
    static func needs(of info: LensInfo) -> [(text: String, symbol: String)] {
        var out: [(String, String)] = []
        if info.needsFace { out.append(("Needs your face", "face.smiling")) }
        if info.needsHands { out.append(("Needs a hand in view", "hand.raised")) }
        if out.isEmpty {
            switch info.category {
            case .scenes, .games: out.append(("Needs you in the picture", "figure.stand"))
            default: out.append(("Works on any picture", "photo"))
            }
        }
        return out
    }

    /// The little marks on a card: a hand for hand lenses, a face for face-driven lenses outside the Faces shelf (where every
    /// lens needs one), a trophy for anything that keeps a score.
    enum Badge: String, CaseIterable {
        case hand, face, score

        var symbol: String {
            switch self {
            case .hand: return "hand.raised.fill"
            case .face: return "face.smiling.inverse"
            case .score: return "trophy.fill"
            }
        }

        var label: String {
            switch self {
            case .hand: return "Needs a hand"
            case .face: return "Needs your face"
            case .score: return "Keeps a score"
            }
        }
    }

    static func badges(for info: LensInfo) -> [Badge] {
        var out: [Badge] = []
        if info.needsHands { out.append(.hand) }
        if info.needsFace, info.category != .faces, info.category != .custom { out.append(.face) }
        if info.scored { out.append(.score) }
        return out
    }
}
