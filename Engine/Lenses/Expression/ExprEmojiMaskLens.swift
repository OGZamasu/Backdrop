import CoreGraphics
import CoreImage
import Foundation

/// A big emoji sits where your face is, tilts with your head, and changes to match your expression with a little pop.
final class ExprEmojiMaskLens: Lens {
    enum Mood: String, CaseIterable {
        case neutral, smile, laugh, surprised, astonished, sleepy, kiss

        var emoji: String {
            switch self {
            case .neutral: return "🙂"
            case .smile: return "😄"
            case .laugh: return "😂"
            case .surprised: return "😮"
            case .astonished: return "😲"
            case .sleepy: return "😑"
            case .kiss: return "😗"
            }
        }
    }

    let needs: LensNeeds = [.face]
    var status: LensStatus? { statusBox.value }

    /// How the mask is sized: across, in eye-spacings.
    static let sizeInEyeSpacings = 3.05

    private let statusBox = StatusBox()
    private var hint = FaceHint()
    private var present = false
    private var candidate = Mood.neutral
    private var candidateFor = 0.0
    private var popAge = 10.0

    /// The emoji on show right now.
    private(set) var shown = Mood.neutral

    init() {
        // Drawing a big emoji the first time takes tens of milliseconds; do every face now, off to the side, so changing
        // expression never stalls a frame.
        ExprEmoji.prepare(Mood.allCases.map(\.emoji))
    }

    func restart() {
        present = false
        shown = .neutral; candidate = .neutral; candidateFor = 0; popAge = 10
    }

    /// Which expression this face is making. `current` is what is showing, which needs a little less to stay than to start.
    static func mood(for f: FaceState, current: Mood) -> Mood {
        let width = f.mouthWidth / max(f.interocular, 1)
        if f.smile > (current == .laugh ? 0.4 : 0.6) && f.mouthOpen > (current == .laugh ? 0.3 : 0.45) { return .laugh }
        if f.browRaise > (current == .astonished ? 0.35 : 0.55) { return .astonished }
        if f.mouthOpen > (current == .surprised ? 0.3 : 0.45) { return .surprised }
        if f.smile > (current == .smile ? 0.3 : 0.5) { return .smile }
        if width < (current == .kiss ? 0.68 : 0.6) && f.smile < 0.2 { return .kiss }
        if f.blink > (current == .sleepy ? 0.5 : 0.7) { return .sleepy }
        return .neutral
    }

    /// A change has to last this long before the emoji follows it, so a flicker of the tracker or a quick blink goes unnoticed.
    static func settleTime(for mood: Mood) -> Double { mood == .sleepy ? 0.28 : 0.1 }

    /// The size of the mask while it pops: starts small, overshoots, settles.
    static func pop(_ age: Double) -> Double { 1 - 0.32 * exp(-8 * age) * cos(17 * age) }

    func render(_ input: LensInput) -> CIImage {
        hint.latest = input.face
        statusBox.value = hint.status("Make a face")
        guard let face = input.face else { present = false; return input.composed }
        let dt = input.dt

        let target = Self.mood(for: face, current: shown)
        if !present {
            present = true
            shown = target; candidate = target; candidateFor = 0
            popAge = 0
        } else {
            popAge += dt
            if target == shown {
                candidate = shown; candidateFor = 0
            } else if target == candidate {
                candidateFor += dt
                if candidateFor >= Self.settleTime(for: target) {
                    shown = target; candidateFor = 0; popAge = 0
                }
            } else {
                candidate = target; candidateFor = dt
            }
        }

        // Never wait for an emoji to be drawn: until it is ready, show nothing, and pop it in when it is.
        guard let image = ExprEmoji.cached(shown.emoji) else {
            ExprEmoji.prepare([shown.emoji])
            popAge = 0
            return input.composed
        }
        let size = face.interocular * Self.sizeInEyeSpacings * Self.pop(popAge)
        let centre = face.exprPoint(0, -0.3)
        guard let layer = input.services.exprOverlay({ ctx in
            // A soft contact shadow down and to the right, as if it were a mask held just off the face.
            ctx.glow(center: CGPoint(x: centre.x + size * 0.03, y: centre.y - size * 0.05), radius: size * 0.66, red: 0.06, green: 0.02, blue: 0.1, alpha: 0.32)
            ctx.draw(image, center: centre, height: CGFloat(size) * CGFloat(image.height) / CGFloat(image.width), rotation: CGFloat(face.roll))
        }) else { return input.composed }
        return layer.composited(over: input.composed).cropped(to: input.rect)
    }
}
