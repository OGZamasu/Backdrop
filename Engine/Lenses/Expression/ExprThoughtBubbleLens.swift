import CoreGraphics
import CoreImage
import Foundation

/// A thought bubble floats beside your head and shows what you're thinking, going by your face: a ponder at rest, a heart
/// when you smile, a big laugh, a light bulb when you raise your eyebrows, food when you open wide and Z's with your eyes shut.
final class ExprThoughtBubbleLens: ExprOverlayLens {
    enum Thought: String, CaseIterable {
        case pondering, love, laugh, idea, hungry, sleepy

        var emoji: String {
            switch self {
            case .pondering: return "🤔"
            case .love: return "❤️"
            case .laugh: return "😂"
            case .idea: return "💡"
            case .hungry: return "🍕"
            case .sleepy: return "💤"
            }
        }
    }

    /// A change of thought has to hold this long before the bubble follows it.
    static let settle = 0.18

    private(set) var shown = Thought.pondering
    private var candidate = Thought.pondering
    private var candidateFor = 0.0
    private var popAge = 10.0
    /// +1 for the bubble on the right of the head, -1 on the left; it moves over only when it has to.
    private(set) var side = 1.0
    private var sideBlend = ExprSpring(1)

    override var hintText: String { "Make a face and see what you're thinking" }

    override init() {
        super.init()
        // Each thought's emoji is slow to draw the first time; draw them all now, off to the side.
        DispatchQueue.global(qos: .utility).async {
            for thought in Thought.allCases { _ = ExprEmoji.image(thought.emoji, size: 160) }
            _ = Self.bubble
        }
    }

    override func restart() {
        super.restart()
        shown = .pondering; candidate = .pondering; candidateFor = 0; popAge = 10; side = 1; sideBlend.reset(1)
    }

    /// What this face is thinking. `current` needs a little less to stay than a new thought needs to start.
    static func thought(for f: FaceState, current: Thought) -> Thought {
        func over(_ v: Double, _ start: Double, _ stay: Double, _ t: Thought) -> Bool { v > (current == t ? stay : start) }
        if over(f.blink, 0.7, 0.5, .sleepy) { return .sleepy }
        if f.smile > 0.45 && over(f.mouthOpen, 0.45, 0.3, .laugh) { return .laugh }
        if over(f.browRaise, 0.55, 0.35, .idea) { return .idea }
        if over(f.mouthOpen, 0.45, 0.3, .hungry) { return .hungry }
        if over(f.smile, 0.5, 0.3, .love) { return .love }
        return .pondering
    }

    override func step(_ face: FaceState?, dt: Double, time: Double) {
        popAge += dt
        guard let face else { return }
        if presence.visibleFor <= dt {
            shown = Self.thought(for: face, current: shown); candidate = shown; candidateFor = 0; popAge = 0
        } else {
            let want = Self.thought(for: face, current: shown)
            if want == shown {
                candidate = shown; candidateFor = 0
            } else if want == candidate {
                candidateFor += dt
                if candidateFor >= Self.settle { shown = want; candidateFor = 0; popAge = 0 }
            } else {
                candidate = want; candidateFor = dt
            }
        }
        // Keep the bubble on its side unless there's no room there and there is on the other.
        let room = { (s: Double) -> Bool in
            let c = face.exprPoint(s * 1.95, 1.65)
            let half = self.bubbleWidth(face) * 0.55
            return c.x - half > self.bounds.minX + self.bounds.width * 0.03 && c.x + half < self.bounds.maxX - self.bounds.width * 0.03
        }
        if !room(side) && room(-side) { side = -side }
        sideBlend.step(toward: side, dt: dt, frequency: 2.2, damping: 0.7)
    }

    private func bubbleWidth(_ face: FaceState) -> Double { max(face.interocular, 46) * 1.7 }

    /// The bubble itself: a scalloped cloud of white, lit from the top left, with the house's soft shadow and edge.
    static let bubble: CGImage? = ExprSprites.make("expr-thought-bubble", side: 320) { ctx in
        let path = CGMutablePath()
        let lobes = 9
        for i in 0..<lobes {
            let a = Double(i) / Double(lobes) * 2 * .pi
            let r = 0.21 + 0.03 * Double(i % 2)
            let c = CGPoint(x: cos(a) * 0.62, y: sin(a) * 0.42)
            path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        path.addEllipse(in: CGRect(x: -0.66, y: -0.44, width: 1.32, height: 0.88))
        let px = max(ctx.ctm.a, 1)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0.025 * px, height: -0.045 * px), blur: 0.07 * px, color: exprColor((0.05, 0.02, 0.12), 0.35))
        ctx.setLineJoin(.round); ctx.setLineWidth(0.06)
        ctx.setStrokeColor(exprColor(ExprPalette.cloud.edge)); ctx.addPath(path); ctx.strokePath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path); ctx.clip(using: .winding)
        if let g = ExprShapes.gradient([((1, 1, 1), 0), ((0.97, 0.97, 1.0), 0.55), ((0.84, 0.86, 0.94), 1)]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: -0.4, y: 0.6), end: CGPoint(x: 0.4, y: -0.6), options: [])
        }
        ctx.restoreGState()
    }

    override func draw(_ ctx: CGContext, face: FaceState?, time: Double) {
        guard let face else { return }
        let fade = presence.alpha
        let w = bubbleWidth(face)
        let s = sideBlend.value
        let bob = sin(time * 1.6) * w * 0.025
        let raw = face.exprPoint(s * 1.95, 1.65)
        let centre = face.exprKeepInside(CGPoint(x: raw.x, y: raw.y + bob), half: CGSize(width: w * 0.55, height: w * 0.4), in: bounds)
        let pop = popIn
        // The trail of little bubbles from the head up to the thought.
        let from = face.exprPoint(s * 0.85, 1.05)
        for i in 0..<3 {
            let t = 0.22 + Double(i) * 0.25
            let p = CGPoint(x: from.x + (centre.x - from.x) * t * 0.82, y: from.y + (centre.y - from.y) * t * 0.82 + sin(time * 2 + Double(i)) * w * 0.012)
            let r = w * (0.045 + 0.03 * Double(i)) * pop
            ctx.exprStamp(Self.bubble, at: p, height: r * 3.2, alpha: fade)
        }
        ctx.exprStamp(Self.bubble, at: centre, height: w * 1.25 * pop, rotation: sin(time * 0.9) * 0.03, alpha: fade)
        // The thought, popping in when it changes.
        let grow = exprOutBack(min(1, popAge / 0.38), overshoot: 2.4)
        let size = w * 0.5 * grow * pop
        if shown == .idea {
            ctx.setBlendMode(.plusLighter)
            ctx.glow(center: centre, radius: size * 1.0, red: 1, green: 0.85, blue: 0.4, alpha: 0.35 * fade)
            ctx.setBlendMode(.normal)
        }
        let wiggle = shown == .laugh ? sin(time * 18) * 0.12 : (shown == .pondering ? sin(time * 1.3) * 0.08 : 0)
        ctx.exprStamp(ExprEmoji.image(shown.emoji, size: 160), at: centre, height: size, rotation: wiggle, alpha: fade)
    }
}
