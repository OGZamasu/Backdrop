import Foundation

/// Hats, glasses, ears and other things that sit on your face.
enum HeadwearFaces {
    static let all: [LensInfo] = [
        LensCatalog.face("dress-cat", "Cat Ears", "🐱", "A velvet cat-ear headband, a pink nose and whiskers. Blink and the ears flick.") { DressUpLens(kind: .catEars) },
        LensCatalog.face("dress-shades", "Deal With It", "😎", "Pixel shades slide down onto your face. Raise your brows to peek over them.") { DressUpLens(kind: .shades) },
        LensCatalog.face("dress-crown", "Crown", "👑", "A jewelled gold crown. Smile and the gems sparkle.") { DressUpLens(kind: .crown) },
        LensCatalog.face("dress-party-hat", "Party Hat", "🥳", "A party hat with a bouncy pom-pom. Open your mouth to blow the party horn.") { DressUpLens(kind: .partyHat) },
        LensCatalog.face("dress-dog", "Dog", "🐶", "Floppy ears and a tongue that rolls out when you open wide.") { DressUpLens(kind: .dog) },
        LensCatalog.face("dress-bunny", "Bunny", "🐰", "Long ears that flop about, and stand tall when you raise your brows.") { DressUpLens(kind: .bunny) },
        LensCatalog.face("dress-devil", "Devil", "😈", "Horns, a goatee and embers. Smile and the horns blaze.") { DressUpLens(kind: .devil) },
        LensCatalog.face("dress-angel", "Angel", "😇", "A glowing halo and wings. Smile and they flutter.") { DressUpLens(kind: .angel) },
        LensCatalog.face("dress-pirate", "Pirate", "🏴‍☠️", "A skull hat, an eye patch, a gold hoop and a scar.") { DressUpLens(kind: .pirate) },
        LensCatalog.face("dress-wizard", "Wizard", "🧙", "A starry hat and a long white beard that sways.") { DressUpLens(kind: .wizard) },
        LensCatalog.face("dress-santa", "Santa", "🎅", "A bobble hat, a fluffy white beard and rosy cheeks.") { DressUpLens(kind: .santa) },
        LensCatalog.face("dress-gentleman", "Gentleman", "🎩", "A top hat, a monocle and a curly moustache that twitches when you smile.") { DressUpLens(kind: .gentleman) },
        LensCatalog.face("dress-clown", "Clown", "🤡", "A rainbow wig and a red nose that squeaks when you blink.") { DressUpLens(kind: .clown) },
        LensCatalog.face("dress-flower-crown", "Flower Crown", "🌸", "Blossoms round your head, dropping petals as you go.") { DressUpLens(kind: .flowers) },
        LensCatalog.face("dress-headphones", "Headphones", "🎧", "Big studio headphones. Smile and the music starts.") { DressUpLens(kind: .headphones) },
        LensCatalog.face("dress-cowboy", "Cowboy", "🤠", "A felt hat and a red bandana. Raise your brows to tip your hat.") { DressUpLens(kind: .cowboy) },
        LensCatalog.face("dress-viking", "Viking", "🛡️", "A horned helmet and long braids. Open wide for a battle roar.") { DressUpLens(kind: .viking) },
        LensCatalog.face("dress-propeller", "Propeller Cap", "🧢", "A patchwork cap with a propeller. Smile and it whirs.") { DressUpLens(kind: .propeller) },
        LensCatalog.face("dress-astronaut", "Astronaut", "🧑‍🚀", "A glass space helmet. Open your mouth and your breath fogs it up.") { DressUpLens(kind: .astronaut) },
        LensCatalog.face("dress-chef", "Chef", "🧑‍🍳", "A tall chef's hat and a curly moustache. Raise your brows and the hat puffs up.") { DressUpLens(kind: .chef) },
        LensCatalog.face("dress-fox", "Fox", "🦊", "Pointed ears, a black nose and cheek fluff. Blink and your ears flick.") { DressUpLens(kind: .fox) },
        LensCatalog.face("dress-panda", "Panda", "🐼", "Round ears and panda eye patches. Smile and you blush.") { DressUpLens(kind: .panda) },
        LensCatalog.face("dress-tabby", "Tabby Cat", "🐈", "Striped ears, whisker pads and a pink nose. Smile and your whiskers lift.") { DressUpLens(kind: .tabby) },
        LensCatalog.face("dress-unicorn", "Unicorn", "🦄", "A pearly horn and a pastel mane. Smile and the horn glows.") { DressUpLens(kind: .unicorn) },
        LensCatalog.face("dress-mermaid", "Mermaid", "🧜", "A tiara of shells and pearls. Smile and bubbles float up.") { DressUpLens(kind: .mermaid) },
        LensCatalog.face("dress-robot", "Robot", "🤖", "A metal cap, an antenna and ear bolts. Talk and the lights follow your voice.") { DressUpLens(kind: .robot) },
        LensCatalog.face("dress-reindeer", "Reindeer", "🦌", "Antlers, soft ears and a red nose. Smile to make it glow.") { DressUpLens(kind: .reindeer) },
        LensCatalog.face("dress-witch", "Witch", "🧙‍♀️", "A crooked hat with a spider on a thread. Open your mouth and down it drops.") { DressUpLens(kind: .witch) },
    ]
}
