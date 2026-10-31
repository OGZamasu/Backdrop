import CoreGraphics
import Foundation

/// What the mannequin does while a lens is tried on it, so the thumbnail catches the lens doing its thing: a smile or an open
/// mouth for lenses that react to them, a raised hand in the right pose for hand lenses, a few seconds of play for games.
struct LensBrowserDirection {
    /// Seconds to run before the picture is taken. For a game this is time spent playing, after the countdown.
    var seconds: Double
    /// Frames a second while running. Lower is quicker to make; real cameras give 30.
    var fps: Double = 20
    /// Where the lens's clock starts, for a lens that does its thing at certain moments rather than all the time.
    var startTime = 0.0
    /// What is behind the mannequin.
    var setting = Setting.studio
    /// What is behind the mannequin: the plain studio backdrop that makes effects stand out, or a furnished room with shapes for
    /// a lens that restyles the whole picture to work on.
    enum Setting { case studio, room }
    /// What the mannequin is doing at a moment. Repeats sensibly for a preview that keeps playing.
    var pose: (Double) -> LensBrowserPose
}

enum LensBrowserDirections {
    /// The direction for a lens: its own entry if it has one, otherwise one made from its category, what it needs and the words of its blurb.
    static func direction(for info: LensInfo) -> LensBrowserDirection {
        if let special = special(info.id) { return special }
        switch info.category {
        case .filters: return info.needsHands ? handFilter(info.id) : filter(info.id)
        case .faces: return face(info)
        case .games: return game(info)
        case .scenes: return scene(info)
        case .custom: return info.needsFace ? face(info, excited: true) : LensBrowserDirection(seconds: 1.6) { calm($0) }
        }
    }

    // MARK: Building blocks

    /// 0 before `start`, easing up to 1 over `duration`.
    static func ease(_ t: Double, start: Double, duration: Double = 0.3) -> Double {
        let x = min(1, max(0, (t - start) / max(duration, 1e-6)))
        return x * x * (3 - 2 * x)
    }

    /// A soft on-off beat: 1 for `duty` of every `period`, easing in and out.
    static func beat(_ t: Double, period: Double, duty: Double = 0.4, phase: Double = 0) -> Double {
        let x = ((t + phase) / period).truncatingRemainder(dividingBy: 1)
        let edge = 0.08
        if x < edge { return x / edge }
        if x < duty { return 1 }
        if x < duty + edge { return 1 - (x - duty) / edge }
        return 0
    }

    private static func wave(_ t: Double, _ period: Double, _ phase: Double = 0) -> Double { sin(2 * .pi * (t / period + phase)) }

    /// Standing easy: a slight sway and a pleasant smile.
    static func calm(_ t: Double, smile: Double = 0.55) -> LensBrowserPose {
        LensBrowserPose(offset: CGVector(dx: 10 * wave(t, 3.2), dy: 0), lean: 0.03 * wave(t, 4.1, 0.2), mouthOpen: 0, smile: smile)
    }

    /// Hand sizes and spots beside the head where a raised hand reads clearly and stays off the face.
    private static let handSize = 92.0
    private static let rightSpot = CGPoint(x: 945, y: 250)
    private static let leftSpot = CGPoint(x: 335, y: 250)

    /// A hand facing the camera, palm out: on the right of the picture that is a left hand, so its thumb points back toward the middle.
    private static func hand(_ fingers: LensBrowserHand.Fingers, at wrist: CGPoint, angle: Double = 0, id: Int = 1) -> LensBrowserHand {
        LensBrowserHand(fingers: fingers, wrist: wrist, size: handSize, angle: angle, mirrored: wrist.x > 640, id: id)
    }

    /// Both arms up, palms out, as if reaching for something overhead, rocking with the body.
    private static func armsUp(_ t: Double, reach: Double = 1, period: Double = 1.6) -> [LensBrowserHand] {
        let lift = 120 * reach
        return [
            hand(.open, at: CGPoint(x: 370 + 30 * wave(t, period), y: 300 + lift + 25 * wave(t, period, 0.25)), angle: -0.25, id: 1),
            hand(.open, at: CGPoint(x: 910 + 30 * wave(t, period, 0.5), y: 300 + lift + 25 * wave(t, period, 0.75)), angle: 0.25, id: 2),
        ]
    }

    // MARK: Filters

    private static func filter(_ id: String) -> LensBrowserDirection {
        switch LensBrowserGroups.table[id] {
        case "Weather & Light": return LensBrowserDirection(seconds: 2.6) { calm($0) }
        case "Looks": return LensBrowserDirection(seconds: 1.0, setting: .room) { calm($0) }
        default: return LensBrowserDirection(seconds: 1.0) { calm($0) }
        }
    }

    private static func handFilter(_ id: String) -> LensBrowserDirection {
        LensBrowserDirection(seconds: 1.8) { t in
            var pose = calm(t)
            pose.hands = [hand(.open, at: CGPoint(x: rightSpot.x + 40 * wave(t, 1.2), y: rightSpot.y + 20 * wave(t, 0.6)), angle: 0.1 * wave(t, 1.2))]
            return pose
        }
    }

    // MARK: Faces

    /// Reads the blurb for what the lens reacts to, and does that a moment in, so the reaction is under way when the picture is
    /// taken. `excited` is for a lens whose words say nothing about it (the user's own): a laugh with raised brows sets off most
    /// expression triggers at once.
    private static func face(_ info: LensInfo, excited: Bool = false) -> LensBrowserDirection {
        let words = (info.name + " " + info.blurb).lowercased()
        func says(_ any: [String]) -> Bool { any.contains { words.contains($0) } }
        var mouth = says(["open", "mouth", "wide", "breathe", "shout", "yawn", "tongue"])
        var brows = says(["eyebrow", "brows", "surprise"])
        var smiles = says(["smile", "laugh", "expression", "mood", "happy", "joy"])
        let sleeps = says(["close your eyes", "eyes closed", "shut your eyes", "sleep"])
        let blinks = !sleeps && says(["blink", "wink"])
        let tilts = says(["tip your head", "tilt"])
        let moves = says(["move", "slosh", "sway", "as you go"])
        if excited, !(mouth || brows || smiles || sleeps || blinks) { (mouth, brows, smiles) = (true, true, true) }
        let wide = excited ? 0.55 : 0.75
        return LensBrowserDirection(seconds: 2.0) { t in
            var pose = calm(t, smile: smiles ? 0.45 + 0.5 * ease(t, start: 0.4) : 0.55)
            if mouth { pose.mouthOpen = 0.1 + wide * ease(t, start: 0.5) }
            else if smiles { pose.mouthOpen = 0.1 + 0.25 * ease(t, start: 0.4) }
            if brows { pose.browRaise = (excited ? 0.75 : 1) * ease(t, start: 0.35) }
            if blinks { pose.blink = beat(t, period: 1.0, duty: 0.14, phase: 0.1) }
            if sleeps { pose.blink = ease(t, start: 0.5, duration: 0.25); pose.smile = 0.3; pose.mouthOpen = 0 }
            if tilts { pose.lean = 0.22 * ease(t, start: 0.4, duration: 0.6) }
            if moves { pose.offset.dx = 60 * wave(t, 1.1); pose.lean = 0.08 * wave(t, 1.1, 0.2) }
            return pose
        }
    }

    // MARK: Games

    private static func game(_ info: LensInfo) -> LensBrowserDirection {
        if info.needsHands {
            return LensBrowserDirection(seconds: 3) { t in
                var pose = calm(t)
                pose.hands = [hand(.open, at: CGPoint(x: 900 + 160 * wave(t, 1.6), y: 300 + 90 * wave(t, 0.8)))]
                return pose
            }
        }
        if info.needsFace {
            return LensBrowserDirection(seconds: 3) { t in
                var pose = calm(t)
                pose.offset = CGVector(dx: 70 * wave(t, 2.2), dy: 40 * wave(t, 1.4))
                pose.mouthOpen = 0.1 + 0.8 * beat(t, period: 1.2, duty: 0.45)
                pose.browRaise = beat(t, period: 1.5, duty: 0.3, phase: 0.6)
                return pose
            }
        }
        // Played with the whole body: sway across the picture with both arms up.
        return LensBrowserDirection(seconds: 3) { t in
            var pose = calm(t, smile: 0.8)
            pose.offset.dx = 150 * wave(t, 2.0)
            pose.lean = 0.06 * wave(t, 2.0, 0.25)
            pose.mouthOpen = 0.35
            pose.hands = armsUp(t).map { var h = $0; h.wrist.x += 150 * wave(t, 2.0); return h }
            return pose
        }
    }

    // MARK: Scenes

    private static func scene(_ info: LensInfo) -> LensBrowserDirection {
        LensBrowserDirection(seconds: 4) { t in
            var pose = calm(t, smile: 0.8)
            pose.mouthOpen = 0.3
            if info.needsHands { pose.hands = [hand(.open, at: CGPoint(x: rightSpot.x + 20 * wave(t, 2.4), y: rightSpot.y + 30), angle: 0.15)] }
            return pose
        }
    }

    // MARK: Lenses with their own direction

    private static func special(_ id: String) -> LensBrowserDirection? {
        switch id {
        case "ghost-trails":
            return LensBrowserDirection(seconds: 1.3) { t in
                var pose = calm(t, smile: 0.8)
                pose.offset.dx = 170 * wave(t, 1.4)
                pose.lean = 0.08 * wave(t, 1.4, 0.2)
                pose.hands = armsUp(t, reach: 0.6, period: 0.7).map { var h = $0; h.wrist.x += 170 * wave(t, 1.4); return h }
                return pose
            }
        case "snow", "confetti", "fireworks", "blossoms":
            return LensBrowserDirection(seconds: 3.2) { calm($0, smile: 0.75) }
        case "air-paint":
            // Draw a loop in the air with a pointing finger.
            return LensBrowserDirection(seconds: 2.6) { t in
                var pose = calm(t)
                let a = 2 * .pi * t / 2.2
                let tip = CGPoint(x: 945 + 150 * sin(a), y: 470 + 80 * sin(2 * a))
                pose.hands = [hand(.point, at: CGPoint(x: tip.x - 0.38 * handSize + 30, y: tip.y - 1.8 * handSize), angle: 0.15)]
                return pose
            }
        case "energy-ball":
            return LensBrowserDirection(seconds: 2.6) { t in
                var pose = calm(t, smile: 0.8)
                pose.hands = [hand(.open, at: CGPoint(x: rightSpot.x, y: rightSpot.y + 6 * wave(t, 1.6)), angle: 0.12)]
                return pose
            }
        case "finger-lightning":
            return LensBrowserDirection(seconds: 1.4) { t in
                var pose = calm(t, smile: 0.7)
                pose.hands = [hand(.open, at: CGPoint(x: leftSpot.x + 10 * wave(t, 1.3), y: leftSpot.y), angle: -0.3, id: 1),
                              hand(.open, at: CGPoint(x: rightSpot.x + 10 * wave(t, 1.3, 0.5), y: rightSpot.y), angle: 0.3, id: 2)]
                return pose
            }
        case "sparkle-trail":
            return LensBrowserDirection(seconds: 1.6) { t in
                var pose = calm(t, smile: 0.8)
                pose.hands = [hand(.open, at: CGPoint(x: rightSpot.x + 130 * wave(t, 0.9), y: rightSpot.y + 60 + 50 * wave(t, 0.45)), angle: 0.2 * wave(t, 0.9))]
                return pose
            }
        case "laser-pointer":
            return LensBrowserDirection(seconds: 1.0) { t in
                var pose = calm(t)
                pose.hands = [hand(.point, at: CGPoint(x: rightSpot.x - 20, y: rightSpot.y + 20), angle: -0.55 + 0.05 * wave(t, 1.5))]
                return pose
            }
        case "light-blade":
            // A fist raised and swung like a hilt.
            return LensBrowserDirection(seconds: 2.0) { t in
                var pose = calm(t, smile: 0.8)
                pose.hands = [hand(.fist, at: CGPoint(x: rightSpot.x - 40, y: rightSpot.y - 10), angle: 0.5 + 0.7 * wave(t, 1.3))]
                return pose
            }
        case "magic-wand":
            // Point, then flick the wand.
            return LensBrowserDirection(seconds: 2.0) { t in
                var pose = calm(t, smile: 0.8)
                pose.hands = [hand(.point, at: CGPoint(x: rightSpot.x + 30 * wave(t, 1.1), y: rightSpot.y + 10), angle: 0.25 + 0.5 * wave(t, 1.1))]
                return pose
            }
        case "shockwave":
            // Two open hands closing in for a clap, again and again.
            return LensBrowserDirection(seconds: 2.4) { t in
                var pose = calm(t, smile: 0.8)
                let close = 0.5 - 0.5 * cos(2 * .pi * t / 1.2)
                let gap = 330 - 285 * close
                pose.hands = [hand(.open, at: CGPoint(x: 640 - gap, y: 300), angle: -0.25, id: 1), hand(.open, at: CGPoint(x: 640 + gap, y: 300), angle: 0.25, id: 2)]
                return pose
            }
        case "magnifier":
            // Thumb out and finger up, as if pinching the rim of a lens.
            return LensBrowserDirection(seconds: 1.6) { t in
                var pose = calm(t, smile: 0.7)
                pose.hands = [hand(.gun, at: CGPoint(x: rightSpot.x - 10 + 12 * wave(t, 1.4), y: rightSpot.y + 10), angle: 0.35)]
                return pose
            }
        case "bubble-wand":
            // Finger and thumb touching in a ring, waved through the air.
            return LensBrowserDirection(seconds: 2.4) { t in
                var pose = calm(t, smile: 0.8)
                var ring = hand(.gun, at: CGPoint(x: rightSpot.x + 90 * wave(t, 1.0), y: rightSpot.y + 40 * wave(t, 0.5)), angle: 0.35)
                ring.pinch = 1
                pose.hands = [ring]
                return pose
            }
        case "mirror":
            // Off to one side, so the reflection is a second person rather than the same one.
            return LensBrowserDirection(seconds: 0.5, setting: .room) { t in
                var pose = calm(t, smile: 0.8)
                pose.offset.dx = -230
                pose.lean = 0.06
                return pose
            }
        case "glitch":
            return LensBrowserDirection(seconds: 0.5, startTime: glitchMoment, setting: .room) { calm($0, smile: 0.7) }
        case "balloon-pop":
            return LensBrowserDirection(seconds: 3.5) { t in
                var pose = calm(t, smile: 0.8)
                pose.offset.dx = 120 * wave(t, 2.6)
                pose.mouthOpen = 0.3
                return pose
            }
        case "googly-eyes":
            return LensBrowserDirection(seconds: 1.6) { t in
                var pose = calm(t, smile: 0.7)
                pose.offset.dx = 70 * wave(t, 0.8)
                pose.lean = 0.12 * wave(t, 0.8, 0.25)
                return pose
            }
        case "staring-contest":
            return LensBrowserDirection(seconds: 2.5) { t in
                var pose = calm(t, smile: 0.2)
                pose.browRaise = 0.35
                pose.mouthOpen = 0.05
                return pose
            }
        case "brow-runner":
            return LensBrowserDirection(seconds: 3.5) { t in
                var pose = calm(t, smile: 0.6)
                pose.browRaise = beat(t, period: 0.9, duty: 0.35)
                return pose
            }
        case "flappy-face":
            return LensBrowserDirection(seconds: 3.5) { t in
                var pose = calm(t, smile: 0.7)
                pose.offset.dy = 80 * wave(t, 1.3)
                return pose
            }
        case "face-snake":
            return LensBrowserDirection(seconds: 3.5) { t in
                var pose = calm(t, smile: 0.6)
                pose.offset = CGVector(dx: 60 * cos(2 * .pi * t / 2), dy: 40 * sin(2 * .pi * t / 2))
                return pose
            }
        case "mouth-catch":
            return LensBrowserDirection(seconds: 3.5) { t in
                var pose = calm(t, smile: 0.5)
                pose.offset.dx = 90 * wave(t, 2.4)
                pose.mouthOpen = 0.05 + 0.85 * beat(t, period: 0.9, duty: 0.5)
                return pose
            }
        case "breakout", "meteor-dodge":
            return LensBrowserDirection(seconds: 3.5) { t in
                var pose = calm(t, smile: 0.7)
                pose.offset.dx = 220 * wave(t, 2.2)
                pose.lean = 0.05 * wave(t, 2.2, 0.25)
                return pose
            }
        case "fruit-slash":
            // Quick swipes back and forth across the picture.
            return LensBrowserDirection(seconds: 3) { t in
                var pose = calm(t, smile: 0.8)
                let x = 640 + 330 * wave(t, 0.9)
                pose.hands = [LensBrowserHand(fingers: .open, wrist: CGPoint(x: x, y: 330 + 70 * wave(t, 0.45)), size: handSize,
                                            angle: -0.5 * cos(2 * .pi * t / 0.9), mirrored: true)]
                return pose
            }
        case "finger-guns":
            return LensBrowserDirection(seconds: 3) { t in
                var pose = calm(t)
                var fingers = LensBrowserHand.Fingers.gun
                fingers.thumb = 1 - beat(t, period: 0.6, duty: 0.25)
                pose.hands = [hand(fingers, at: CGPoint(x: 990, y: 230), angle: 0.55 + 0.35 * wave(t, 2.4))]
                return pose
            }
        case "whack-a-mole":
            // Poke one spot after another.
            return LensBrowserDirection(seconds: 3) { t in
                var pose = calm(t)
                let spots = [CGPoint(x: 330, y: 260), CGPoint(x: 960, y: 300), CGPoint(x: 420, y: 470), CGPoint(x: 880, y: 470)]
                let spot = spots[Int(t / 0.55) % spots.count]
                pose.hands = [hand(.point, at: CGPoint(x: spot.x - 0.38 * handSize, y: spot.y - 1.8 * handSize), angle: 0)]
                return pose
            }
        case "rock-paper-scissors":
            return LensBrowserDirection(seconds: 3) { t in
                var pose = calm(t, smile: 0.8)
                pose.hands = [hand(.peace, at: CGPoint(x: rightSpot.x, y: rightSpot.y + 10 * wave(t, 0.5)), angle: 0.1)]
                return pose
            }
        case "palm-pong":
            return LensBrowserDirection(seconds: 3) { t in
                var pose = calm(t)
                pose.hands = [LensBrowserHand(fingers: .open, wrist: CGPoint(x: 640 + 300 * wave(t, 2.2), y: 230), size: handSize, mirrored: true)]
                return pose
            }
        case "hole-in-the-wall":
            return LensBrowserDirection(seconds: 3) { t in
                var pose = calm(t, smile: 0.8)
                pose.mouthOpen = 0.4
                pose.hands = armsUp(t, reach: 0.8, period: 3)
                return pose
            }
        default:
            return nil
        }
    }
}

private extension LensBrowserDirections {
    /// The first moment the glitch lens is in the thick of a burst, half a second before the picture is taken.
    static let glitchMoment: Double = {
        var t = 0.0
        while t < 60, GlitchPlan.burst(at: t + 0.5) < 0.8 { t += 1.0 / 30 }
        return t
    }()
}
