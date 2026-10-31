import Foundation

/// Face lenses that react to your expression, and funhouse warps.
enum ExpressionFaces {
    static let all: [LensInfo] = {
        // The funhouse warps need a GPU kernel that takes a moment to build; start it now, while the catalog loads.
        ExprWarpKernel.warmUp()
        return entries + newer
    }()

    private static func withText(_ info: LensInfo) -> LensInfo {
        var info = info
        info.showsText = true
        return info
    }

    private static let entries: [LensInfo] = [
        LensCatalog.face("heart-eyes", "Love Eyes", "😍", "Hearts throb in your eyes. Smile and more float up.") { ExprHeartEyesLens() },
        LensCatalog.face("star-eyes", "Star Eyes", "🤩", "Stars twinkle in your eyes. Raise your eyebrows for a burst of sparkles.") { ExprStarEyesLens() },
        LensCatalog.face("happy-tears", "Happy Tears", "😂", "Smile big and tears of joy squirt out, fall and splash.") { ExprHappyTearsLens() },
        LensCatalog.face("storm-cloud", "Storm Cloud", "⛈️", "A little cloud sulks over your head. Raise your eyebrows and it storms.") { ExprStormCloudLens() },
        LensCatalog.face("emoji-mask", "Emoji Mask", "🙂", "An emoji wears your face and changes with your expression.") { ExprEmojiMaskLens() },
        LensCatalog.face("pinocchio", "Pinocchio", "🤥", "Open your mouth and a wooden nose grows. Shut it and it shrinks.") { ExprPinocchioLens() },
        LensCatalog.face("mood-aura", "Mood Aura", "🔮", "A glow around your head shows your mood: calm, happy, surprised or loud.") { ExprMoodAuraLens() },
        LensCatalog.face("alien-face", "Alien", "👽", "Big forehead, green skin, black eyes and wiggling antennae.") { ExprAlienLens() },
        LensCatalog.face("swirl-face", "Swirl", "🌀", "Your face twirls. Open wide or tip your head to turn it.") { ExprSwirlLens() },
        LensCatalog.face("squeeze-face", "Squeeze", "🪗", "Your features shrink to dots, then swell to giants, again and again.") { ExprSqueezeLens() },
        LensCatalog.face("googly-eyes", "Googly Eyes", "🤪", "Big loose pupils that slosh about when you move.") { ExprGooglyEyesLens() },
    ]

    /// Round two: seventeen more, each set off by something your face does.
    private static let newer: [LensInfo] = [
        LensCatalog.face("anime-eyes", "Anime Eyes", "🥺", "Huge sparkly anime eyes that squeeze shut with a blush when you smile.") { ExprAnimeEyesLens() },
        LensCatalog.face("sweat-drop", "Sweat Drop", "😅", "Raise your eyebrows and a big nervous sweat drop slides down your temple.") { ExprSweatDropLens() },
        LensCatalog.face("fuming", "Fuming", "😤", "Shout and steam blasts out of your ears as your face goes red.") { ExprFumingLens() },
        LensCatalog.face("dizzy-stars", "Dizzy", "💫", "Stars circle your head, faster as you tip it side to side, until your eyes spin.") { ExprDizzyLens() },
        LensCatalog.face("kiss-marks", "Kisses", "💋", "Pucker up and lipstick kisses fly out and land on the screen.") { ExprKissLens() },
        withText(LensCatalog.face("sleepy-zzz", "Sleepy", "😴", "Close your eyes to nod off, with drifting Z's and a bubble at your nose.") { ExprSleepyLens() }),
        LensCatalog.face("mind-blown", "Mind Blown", "🤯", "Drop your jaw and raise your eyebrows to blow the top of your head off.") { ExprMindBlownLens() },
        LensCatalog.face("thought-bubble", "Thinking", "💭", "A thought bubble shows what your face is thinking: love, laughs, ideas or food.") { ExprThoughtBubbleLens() },
        withText(LensCatalog.face("face-scanner", "Face Scan", "🎯", "A sci-fi scanner locks onto your face and reads your mood live.") { ExprFaceScanLens() }),
        LensCatalog.face("cyber-visor", "Cyber Visor", "🥽", "A glowing visor with a sweeping light: raise your brows to target, smile to party.") { ExprCyberVisorLens() },
        withText(LensCatalog.face("comic-pow", "Comic Pow", "💥", "Laugh, gasp or raise your eyebrows and comic sound effects burst out beside you.") { ExprComicPowLens() }),
        LensCatalog.face("balloon-head", "Balloon Head", "🎈", "Smile and your head blows up like a balloon.") { ExprBalloonHeadLens() },
        LensCatalog.face("tiny-head", "Tiny Head", "🤏", "Your head shrinks to a pea, and smaller still when you raise your eyebrows.") { ExprTinyHeadLens() },
        LensCatalog.face("long-face", "Long Face", "🐴", "Open your mouth and your chin stretches down, then boings back.") { ExprLongFaceLens() },
        LensCatalog.face("mirror-face", "Mirror Face", "🦋", "One half of your face mirrored onto the other; tip your head to switch sides.") { ExprMirrorFaceLens() },
        LensCatalog.face("melting-face", "Melting", "🫠", "Open your mouth and your face melts and drips like wax.") { ExprMeltingLens() },
        LensCatalog.face("glitch-face", "Glitch Face", "🤖", "Your face breaks up like a bad signal when you blink or open your mouth.") { ExprGlitchFaceLens() },
    ]
}
