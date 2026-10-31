import CoreGraphics
import CoreImage
import Foundation
import Metal

/// Lets the renderer see where a game is (waiting, counting down, playing, over) without knowing which game it is.
protocol LensBrowserGameLike: AnyObject {
    var lensBrowserIsPlaying: Bool { get }
    var lensBrowserIsOver: Bool { get }
}

extension GameLens: LensBrowserGameLike {
    var lensBrowserIsPlaying: Bool { if case .playing = phase { return true } else { return false } }
    var lensBrowserIsOver: Bool { if case .over = phase { return true } else { return false } }
}

/// Runs a lens over the mannequin, offscreen, the way the pipeline runs it over the camera: the same compositor (edge softening,
/// colour match, light wrap), the same services, a silhouette grid for games, a face and hands for lenses that ask for them.
/// Never touches the camera, Vision or the video queue.
///
/// Not thread-safe: use one per thread. It holds about 40 MB of buffers, so keep only a couple.
final class LensBrowserRenderer {
    static let thumbnailSize = CGSize(width: 320, height: 180)

    let mannequin = LensBrowserMannequin()
    let compositor = Compositor()
    /// Asks the GPU for low priority, so thumbnails never get in the way of the live video.
    let context: CIContext
    let services: LensServices
    private let grid = MatteGrid(outputSize: LensBrowserMannequin.size)
    private let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    init() {
        let options: [CIContextOption: Any] = [.priorityRequestLow: true, .name: "LensThumbnails"]
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
        services = LensServices(context: context, size: LensBrowserMannequin.size)
    }

    // MARK: Frames

    /// One lens running over the mannequin, a frame at a time. Used for thumbnails and for the live preview.
    final class Session {
        let info: LensInfo
        let lens: Lens
        let direction: LensBrowserDirection
        private unowned let renderer: LensBrowserRenderer
        private(set) var time = 0.0
        private var previous: LensBrowserPose?

        init(info: LensInfo, renderer: LensBrowserRenderer) {
            self.info = info
            self.renderer = renderer
            lens = info.make()
            direction = LensBrowserDirections.direction(for: info)
            time = direction.startTime
        }

        var game: LensBrowserGameLike? { lens as? LensBrowserGameLike }

        /// Moves on by `dt` and returns the lens's picture. `poseTime` is where in the direction the mannequin is.
        func step(_ dt: Double, poseTime: Double? = nil) -> CIImage {
            time += dt
            let pose = direction.pose(poseTime ?? (time - direction.startTime))
            let input = renderer.input(pose: pose, previous: previous, time: time, dt: dt, lens: lens, setting: direction.setting)
            previous = pose
            return lens.render(input).cropped(to: renderer.compositor.rect)
        }

        /// A game waits for you to step in, then counts down from three. Two long frames get it straight to playing.
        func skipToPlay() {
            guard let game else { return }
            for dt in [0.6, LensBrowserRenderer.countdown + 0.05, 0.6, LensBrowserRenderer.countdown + 0.05] where !game.lensBrowserIsPlaying {
                _ = step(dt, poseTime: 0)
            }
            time = direction.startTime
        }
    }

    static var countdown: Double { 3 }

    /// What a lens is handed for one frame, made the way the pipeline makes it.
    func input(pose: LensBrowserPose, previous: LensBrowserPose?, time: Double, dt: Double, lens: Lens,
               setting: LensBrowserDirection.Setting = .studio) -> LensInput {
        let frame = mannequin.frame(pose)
        let backdrop = setting == .room ? mannequin.room : mannequin.backdrop
        let matte = compositor.refinedMatte(camera: frame.camera, mask: frame.mask)
        let composed = compositor.composite(camera: frame.camera, matte: matte, background: backdrop)
        var matteGrid: MatteGrid?
        if lens.wantsMatteGrid {
            grid.update(from: matte, rect: compositor.rect, context: context)
            matteGrid = grid
        }
        var hands: [HandState] = []
        if lens.needs.contains(.hands) {
            let before = previous.map { $0.hands.map { $0.state() } } ?? []
            hands = frame.hands.enumerated().map { i, hand in
                guard i < before.count, dt > 0 else { return hand }
                var moving = hand
                let palm = hand.palm, was = before[i].palm
                moving.velocity = CGVector(dx: (palm.x - was.x) / dt, dy: (palm.y - was.y) / dt)
                let tip = hand[.indexTip], wasTip = before[i][.indexTip]
                moving.tipVelocity = CGVector(dx: (tip.x - wasTip.x) / dt, dy: (tip.y - wasTip.y) / dt)
                return moving
            }
        }
        return LensInput(time: time, dt: dt, rect: compositor.rect, camera: frame.camera, matte: matte, background: backdrop,
                         composed: composed, matteGrid: matteGrid, face: lens.needs.contains(.face) ? frame.face : nil,
                         services: services, hands: hands)
    }

    /// The mannequin with no lens, as the camera would show it in front of the backdrop.
    func plain(_ pose: LensBrowserPose = LensBrowserDirections.calm(0), setting: LensBrowserDirection.Setting = .studio) -> CIImage {
        let frame = mannequin.frame(pose)
        let matte = compositor.refinedMatte(camera: frame.camera, mask: frame.mask)
        return compositor.composite(camera: frame.camera, matte: matte, background: setting == .room ? mannequin.room : mannequin.backdrop)
    }

    /// A picture shrunk to `size` with a good filter, read back now (lens pictures share buffers and must be read before the next frame).
    func picture(_ image: CIImage, size: CGSize = LensBrowserRenderer.thumbnailSize) -> CGImage? {
        let rect = compositor.rect
        let scale = size.width / rect.width
        let shrunk = image.cropped(to: rect).clampedToExtent()
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: (size.height / rect.height) / scale])
            .cropped(to: CGRect(origin: .zero, size: size))
        return context.createCGImage(shrunk, from: CGRect(origin: .zero, size: size), format: .RGBA8, colorSpace: space)
    }

    // MARK: Thumbnails

    /// A thumbnail of a lens: run long enough to show what it does, then taken. A game is played for a few seconds with the
    /// mannequin following a script; if it ends early the last picture from before the end is kept, and the "best score" the
    /// game wrote down for itself is put back, so trying it on doesn't count as playing.
    func thumbnail(for info: LensInfo) -> CGImage? {
        let session = Session(info: info, renderer: self)
        let scoreKey = "backdrop.best.\(info.id)"
        let bestBefore = UserDefaults.standard.object(forKey: scoreKey)
        defer {
            if session.game != nil, !Self.same(UserDefaults.standard.object(forKey: scoreKey), bestBefore) {
                if let bestBefore { UserDefaults.standard.set(bestBefore, forKey: scoreKey) } else { UserDefaults.standard.removeObject(forKey: scoreKey) }
            }
        }
        session.skipToPlay()
        let dt = 1 / max(5, session.direction.fps)
        let frames = max(1, Int((session.direction.seconds / dt).rounded()))
        var kept: CGImage?
        for i in 1...frames {
            let image = session.step(dt)
            if let game = session.game, game.lensBrowserIsOver { return kept ?? picture(image) }
            // Keep a picture now and then, in case a game ends before the last frame.
            if i == frames || (session.game != nil && i % 10 == 0) { kept = picture(image) }
        }
        return kept
    }

    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x as NSObject, y as NSObject): return x.isEqual(y)
        default: return false
        }
    }
}
