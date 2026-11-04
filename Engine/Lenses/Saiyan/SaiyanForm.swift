import Foundation
import simd

/// The forms of the Dragon Ball lens, in the order you climb through them by powering up.
///
/// This file is the one place that says what each form is: its colours, its hair, its aura and how strong it is. The face
/// half (hair, brows, eyes), the body half (aura, lightning, power-up) and the moves all read it, so the forms look like the
/// same form everywhere. Every colour is sRGB, 0...1.
enum SaiyanForm: Int, CaseIterable, Comparable {
    case base
    // Dragon Ball Z
    case superSaiyan, superSaiyan2, superSaiyan3
    // Dragon Ball Super
    case superSaiyanGod, superSaiyanBlue, blueKaioken, ultraEgo, ultraInstinctSign, ultraInstinct

    static func < (a: SaiyanForm, b: SaiyanForm) -> Bool { a.rawValue < b.rawValue }

    enum Series: String { case base = "", dragonBallZ = "Dragon Ball Z", dragonBallSuper = "Dragon Ball Super" }

    /// The next form up, or nil at the top.
    var next: SaiyanForm? { SaiyanForm(rawValue: rawValue + 1) }
    static var top: SaiyanForm { allCases[allCases.count - 1] }
    var isBase: Bool { self == .base }

    var series: Series {
        switch self {
        case .base: return .base
        case .superSaiyan, .superSaiyan2, .superSaiyan3: return .dragonBallZ
        default: return .dragonBallSuper
        }
    }

    var title: String {
        switch self {
        case .base: return "Base"
        case .superSaiyan: return "Super Saiyan"
        case .superSaiyan2: return "Super Saiyan 2"
        case .superSaiyan3: return "Super Saiyan 3"
        case .superSaiyanGod: return "Super Saiyan God"
        case .superSaiyanBlue: return "Super Saiyan Blue"
        case .blueKaioken: return "Blue Kaioken"
        case .ultraEgo: return "Ultra Ego"
        case .ultraInstinctSign: return "Ultra Instinct Sign"
        case .ultraInstinct: return "Ultra Instinct"
        }
    }

    /// A short name for tight places (a ring label, a thumbnail).
    var shortTitle: String {
        switch self {
        case .base: return "Base"
        case .superSaiyan: return "SSJ"
        case .superSaiyan2: return "SSJ2"
        case .superSaiyan3: return "SSJ3"
        case .superSaiyanGod: return "God"
        case .superSaiyanBlue: return "Blue"
        case .blueKaioken: return "Kaioken"
        case .ultraEgo: return "Ego"
        case .ultraInstinctSign: return "UI Sign"
        case .ultraInstinct: return "UI"
        }
    }

    /// How strong the form is, 0 for base to 1 for the top. Moves scale their width, brightness and crackle by this, and the aura
    /// by its own `auraScale`.
    var power: Double {
        switch self {
        case .base: return 0
        case .superSaiyan: return 0.25
        case .superSaiyan2: return 0.38
        case .superSaiyan3: return 0.5
        case .superSaiyanGod: return 0.6
        case .superSaiyanBlue: return 0.7
        case .blueKaioken: return 0.78
        case .ultraEgo: return 0.86
        case .ultraInstinctSign: return 0.92
        case .ultraInstinct: return 1
        }
    }

    // MARK: Look

    enum HairStyle {
        /// The person's own hair: nothing is drawn.
        case natural
        /// Super Saiyan: a few tall spikes, swept up, with one fringe lock between the brows.
        case spiky
        /// Super Saiyan 2: straighter, sharper, more jagged spikes standing up and back.
        case jagged
        /// Super Saiyan 3: a huge upright mane with the hair falling to the waist behind the shoulders.
        case long
        /// God, Blue, Ultra Ego: Super Saiyan's silhouette, taller and cleaner, with sharper tips.
        case swept
        /// Ultra Instinct: silver, with loose strands that float and glint.
        case silver
    }

    enum AuraStyle {
        case none
        /// Super Saiyan: golden flame licking up around the outline.
        case flame
        /// Super Saiyan 2: the same, brighter and taller, with lightning crackling through it.
        case electric
        /// Super Saiyan 3: a huge roaring flame that spreads wide.
        case blaze
        /// Super Saiyan God: a smooth, calm crimson flame with a soft edge.
        case smooth
        /// Blue Kaioken: the Blue aura with a red rim and a pulse.
        case kaioken
        /// Ultra Instinct: a cool silver glow with fine wisps and a slow shimmer.
        case silver
        /// Ultra Ego: a heavy violet aura that rolls rather than licks.
        case ego
    }

    enum Eyes {
        /// The person's own eyes: nothing is drawn.
        case natural
        /// Teal-green irises with a hard white highlight (Super Saiyan, 2, 3).
        case teal
        /// A calm single colour, no pupil detail (God, Blue, Ego).
        case calm
        /// Silver, with a faint glow (Ultra Instinct).
        case silver
    }

    var hairStyle: HairStyle {
        switch self {
        case .base: return .natural
        case .superSaiyan: return .spiky
        case .superSaiyan2: return .jagged
        case .superSaiyan3: return .long
        case .superSaiyanGod, .superSaiyanBlue, .blueKaioken, .ultraEgo: return .swept
        case .ultraInstinctSign, .ultraInstinct: return .silver
        }
    }

    var auraStyle: AuraStyle {
        switch self {
        case .base: return .none
        case .superSaiyan: return .flame
        case .superSaiyan2: return .electric
        case .superSaiyan3: return .blaze
        case .superSaiyanGod: return .smooth
        case .superSaiyanBlue: return .smooth
        case .blueKaioken: return .kaioken
        case .ultraEgo: return .ego
        case .ultraInstinctSign, .ultraInstinct: return .silver
        }
    }

    var eyes: Eyes {
        switch self {
        case .base: return .natural
        case .superSaiyan, .superSaiyan2, .superSaiyan3: return .teal
        case .superSaiyanGod, .superSaiyanBlue, .blueKaioken, .ultraEgo: return .calm
        case .ultraInstinctSign, .ultraInstinct: return .silver
        }
    }

    /// Super Saiyan 3 has no eyebrows: its brow ridge is bare.
    var hasBrows: Bool { self != .superSaiyan3 }

    /// How much of the aura's outline is lightning, 0...1. Super Saiyan 2 crackles all the time; Super Saiyan 3 is the heaviest.
    var lightning: Double {
        switch self {
        case .base, .superSaiyanGod, .ultraInstinct: return 0
        case .superSaiyan: return 0.14
        case .superSaiyan2: return 0.72
        case .superSaiyan3: return 1
        case .superSaiyanBlue: return 0.16
        case .blueKaioken: return 0.4
        case .ultraEgo: return 0.32
        case .ultraInstinctSign: return 0.1
        }
    }

    /// How big the aura is next to the person: 1 hugs the outline, bigger spreads wide and licks high.
    var auraScale: Double {
        switch self {
        case .base: return 0
        case .superSaiyan: return 1
        case .superSaiyan2: return 1.2
        case .superSaiyan3: return 1.8
        case .superSaiyanGod: return 1.1
        case .superSaiyanBlue: return 1.15
        case .blueKaioken: return 1.4
        case .ultraEgo: return 1.55
        case .ultraInstinctSign: return 1.1
        case .ultraInstinct: return 1.3
        }
    }

    /// How many embers rise off the outline each second at the form's strength.
    var embers: Double { auraStyle == .none ? 0 : 60 + 140 * power }

    var palette: SaiyanPalette { SaiyanPalette.of(self) }
}

/// The colours of one form.
struct SaiyanPalette {
    /// The body of the hair, its shadow side, and its lit tips.
    var hairBase: SIMD3<Double>
    var hairShade: SIMD3<Double>
    var hairHighlight: SIMD3<Double>
    /// The aura from the inside out: a white-hot core, the body of the flame, and the faint rim that fades into the room.
    var auraCore: SIMD3<Double>
    var auraMid: SIMD3<Double>
    var auraRim: SIMD3<Double>
    var eye: SIMD3<Double>
    var lightning: SIMD3<Double>
    /// The colour a move leans toward in this form (a Kamehameha stays blue in Super Saiyan and goes red in God).
    /// `nil` in the forms where moves keep their own colour.
    var kiTint: SIMD3<Double>?

    private static func c(_ hex: UInt32) -> SIMD3<Double> {
        SIMD3(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    static func of(_ form: SaiyanForm) -> SaiyanPalette {
        switch form {
        case .base:
            return SaiyanPalette(hairBase: c(0x2A2220), hairShade: c(0x151010), hairHighlight: c(0x5A4A44), auraCore: c(0xFFFFFF),
                                 auraMid: c(0xCFE6FF), auraRim: c(0x7FB0FF), eye: c(0x2B1B14), lightning: c(0xBFE0FF), kiTint: nil)
        case .superSaiyan:
            return SaiyanPalette(hairBase: c(0xFFD21F), hairShade: c(0xE49A0C), hairHighlight: c(0xFFF3A6), auraCore: c(0xFFFBE0),
                                 auraMid: c(0xFFC21A), auraRim: c(0xFF8A00), eye: c(0x2FD4C4), lightning: c(0xFFF2A0), kiTint: nil)
        case .superSaiyan2:
            return SaiyanPalette(hairBase: c(0xFFDC2E), hairShade: c(0xEBA511), hairHighlight: c(0xFFF8C2), auraCore: c(0xFFFFF0),
                                 auraMid: c(0xFFCF2B), auraRim: c(0xFF9A10), eye: c(0x27E0D0), lightning: c(0xBFE9FF), kiTint: nil)
        case .superSaiyan3:
            return SaiyanPalette(hairBase: c(0xFFD020), hairShade: c(0xE08C08), hairHighlight: c(0xFFF4B0), auraCore: c(0xFFFFE8),
                                 auraMid: c(0xFFBA14), auraRim: c(0xFF7A00), eye: c(0x28D8C8), lightning: c(0xC8EBFF), kiTint: nil)
        case .superSaiyanGod:
            return SaiyanPalette(hairBase: c(0xE0262E), hairShade: c(0x8E0B18), hairHighlight: c(0xFF8A7A), auraCore: c(0xFFE6DC),
                                 auraMid: c(0xFF3040), auraRim: c(0xB00A22), eye: c(0xE3243A), lightning: c(0xFFB0A0), kiTint: c(0xFF3A44))
        case .superSaiyanBlue:
            return SaiyanPalette(hairBase: c(0x2FA8F5), hairShade: c(0x0F62C8), hairHighlight: c(0xB5F0FF), auraCore: c(0xF2FFFF),
                                 auraMid: c(0x32C8FF), auraRim: c(0x1170E8), eye: c(0x2ABFE8), lightning: c(0xC8F6FF), kiTint: c(0x3FD0FF))
        case .blueKaioken:
            return SaiyanPalette(hairBase: c(0x2C9AF0), hairShade: c(0x0E55BE), hairHighlight: c(0xB5EEFF), auraCore: c(0xF6FFFF),
                                 auraMid: c(0x38C2FF), auraRim: c(0xFF2A2A), eye: c(0x28B6E8), lightning: c(0xFF9A8A), kiTint: c(0xFF4A52))
        case .ultraEgo:
            return SaiyanPalette(hairBase: c(0x7A2CC8), hairShade: c(0x3E0E7A), hairHighlight: c(0xD3A2FF), auraCore: c(0xF6E8FF),
                                 auraMid: c(0xA24CFF), auraRim: c(0x5A12B8), eye: c(0xB255F0), lightning: c(0xDDB0FF), kiTint: c(0xB968FF))
        case .ultraInstinctSign:
            return SaiyanPalette(hairBase: c(0x6C7488), hairShade: c(0x2E3446), hairHighlight: c(0xDCE4F4), auraCore: c(0xFFFFFF),
                                 auraMid: c(0xB9C6E0), auraRim: c(0x6E7FA8), eye: c(0xC8D2E8), lightning: c(0xE8F0FF), kiTint: c(0xC5D2EE))
        case .ultraInstinct:
            return SaiyanPalette(hairBase: c(0xC9D2E4), hairShade: c(0x7B86A2), hairHighlight: c(0xFFFFFF), auraCore: c(0xFFFFFF),
                                 auraMid: c(0xDDE6F8), auraRim: c(0x8FA2D0), eye: c(0xE4ECFA), lightning: c(0xFFFFFF), kiTint: c(0xE0E9FA))
        }
    }

    /// A move's own colour with this form's tint blended in. A form with no tint leaves the move as it is. `amount` is how far toward the
    /// tint to go when there is one (a move's signature colour should still read, so stay under about 0.75).
    func tinting(_ colour: SIMD3<Double>, amount: Double = 0.7) -> SIMD3<Double> {
        guard let tint = kiTint else { return colour }
        let k = min(1, max(0, amount))
        return colour + (tint - colour) * k
    }
}
