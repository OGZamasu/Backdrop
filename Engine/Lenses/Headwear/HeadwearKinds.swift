import Foundation

/// The costumes on offer.
enum HeadwearKind: String, CaseIterable {
    case dog, bunny, devil, angel, wizard, santa, gentleman, pirate, clown, flowers
    case catEars, shades, crown, partyHat
    case headphones, cowboy, viking, propeller, astronaut, chef, fox, panda, tabby, unicorn, mermaid, robot, reindeer, witch

    func makeCostume() -> HeadwearCostume {
        switch self {
        case .dog: return HeadwearDog()
        case .bunny: return HeadwearBunny()
        case .devil: return HeadwearDevil()
        case .angel: return HeadwearAngel()
        case .wizard: return HeadwearWizard()
        case .santa: return HeadwearSanta()
        case .gentleman: return HeadwearGentleman()
        case .pirate: return HeadwearPirate()
        case .clown: return HeadwearClown()
        case .flowers: return HeadwearFlowerCrown()
        case .catEars: return HeadwearCatEars()
        case .shades: return HeadwearShades()
        case .crown: return HeadwearCrown()
        case .partyHat: return HeadwearPartyHat()
        case .headphones: return HeadwearHeadphones()
        case .cowboy: return HeadwearCowboy()
        case .viking: return HeadwearViking()
        case .propeller: return HeadwearPropeller()
        case .astronaut: return HeadwearAstronaut()
        case .chef: return HeadwearChef()
        case .fox: return HeadwearFox()
        case .panda: return HeadwearPanda()
        case .tabby: return HeadwearTabby()
        case .unicorn: return HeadwearUnicorn()
        case .mermaid: return HeadwearMermaid()
        case .robot: return HeadwearRobot()
        case .reindeer: return HeadwearReindeer()
        case .witch: return HeadwearWitch()
        }
    }
}
