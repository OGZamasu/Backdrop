import AppKit
import CoreGraphics
import CoreImage
import SceneKit

/// Textures drawn in code, so the maze needs no image files. All tile seamlessly.
enum MazeTextures {
    static func bricks() -> CGImage {
        bitmap(256, 256) { ctx in
            var rng = SplitMix64(seed: 0xB41C)
            func jitter(_ amount: CGFloat) -> CGFloat { CGFloat.random(in: -amount...amount, using: &rng) }

            ctx.setFillColor(CGColor(red: 0.66, green: 0.63, blue: 0.58, alpha: 1))   // mortar
            ctx.fill(CGRect(x: 0, y: 0, width: 256, height: 256))

            let rows = 8, brickH = 32, brickW = 64
            for row in 0..<rows {
                let shift = row % 2 == 0 ? 0 : -brickW / 2
                for k in 0...4 {
                    let x = shift + k * brickW
                    let color = CGColor(red: 0.60 + jitter(0.07), green: 0.20 + jitter(0.04), blue: 0.14 + jitter(0.03), alpha: 1)
                    // Decide the speckles once, then draw the brick at each wrap-around position so the tile has no seam.
                    let specks: [(CGFloat, CGFloat, CGFloat, Bool)] = (0..<16).map { _ in
                        (CGFloat.random(in: 4..<CGFloat(brickW - 8), using: &rng), CGFloat.random(in: 4..<CGFloat(brickH - 8), using: &rng),
                         CGFloat.random(in: 2...5, using: &rng), Bool.random(using: &rng))
                    }
                    for wrap in [-256, 0, 256] {
                        let rect = CGRect(x: x + wrap + 2, y: row * brickH + 2, width: brickW - 4, height: brickH - 4)
                        ctx.setFillColor(color)
                        ctx.fill(rect)
                        for (dx, dy, size, light) in specks {
                            ctx.setFillColor(light ? CGColor(red: 1, green: 0.8, blue: 0.7, alpha: 0.16) : CGColor(red: 0, green: 0, blue: 0, alpha: 0.20))
                            ctx.fill(CGRect(x: rect.minX + dx, y: rect.minY + dy, width: size, height: size * 0.7))
                        }
                        ctx.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.75, alpha: 0.10))   // lit top edge
                        ctx.fill(CGRect(x: rect.minX, y: rect.maxY - 3, width: rect.width, height: 3))
                        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.18))         // shaded bottom edge
                        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 3))
                    }
                }
            }
        }
    }

    static func floor() -> CGImage {
        bitmap(256, 256) { ctx in
            var rng = SplitMix64(seed: 0xF100)
            for ty in 0..<4 {
                for tx in 0..<4 {
                    let base: CGFloat = (tx + ty) % 2 == 0 ? 0.50 : 0.36
                    let n = CGFloat.random(in: -0.025...0.025, using: &rng)
                    ctx.setFillColor(CGColor(red: base + n, green: base - 0.02 + n, blue: base - 0.06 + n, alpha: 1))
                    ctx.fill(CGRect(x: tx * 64, y: ty * 64, width: 64, height: 64))
                }
            }
            ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 0.6))   // grout
            for i in 0..<4 {
                ctx.fill(CGRect(x: i * 64, y: 0, width: 2, height: 256))
                ctx.fill(CGRect(x: 0, y: i * 64, width: 256, height: 2))
            }
        }
    }

    static func ceiling() -> CGImage {
        bitmap(128, 128) { ctx in
            ctx.setFillColor(CGColor(red: 0.22, green: 0.22, blue: 0.25, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
            ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 3))
            ctx.fill(CGRect(x: 0, y: 0, width: 3, height: 128))
        }
    }

    private static func bitmap(_ width: Int, _ height: Int, draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx)
        return ctx.makeImage()!
    }
}

/// The old Windows "3D Maze" screensaver, behind you: a first-person wander through red-brick corridors.
final class MazeSource: BackgroundSource {
    private var stage: MazeStage?

    // SceneKit objects are built and used only on the thread that asks for frames (the pipeline queue).
    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        if stage == nil { stage = MazeStage() }
        return stage?.frame(at: time)
    }

    func stop() { stage = nil }
}

final class MazeStage {
    static let columns = 21
    static let rows = 11

    private let cell: CGFloat = 3
    private let wallHeight: CGFloat = 2.6
    private let wallThickness: CGFloat = 0.3
    private let eyeHeight: CGFloat = 1.3

    private let scene = SCNScene()
    private let cameraNode = SCNNode()
    private var world = SCNNode()
    private var renderer: OffscreenSceneRenderer?

    private var seeds: SplitMix64
    private(set) var maze: Maze
    private(set) var walker: MazeWalker
    private(set) var mazesBuilt = 0
    /// A fresh maze after this many cells, so it never feels like the same few corridors.
    private let cellsPerMaze = 300

    private let wallMaterial: SCNMaterial
    private let endMaterial: SCNMaterial
    private let floorMaterial: SCNMaterial
    private let ceilingMaterial: SCNMaterial

    private let frameInterval: CFTimeInterval = 1.0 / 30
    private var lastTime: CFTimeInterval?
    private var lastRender: (time: CFTimeInterval, image: CIImage)?

    init(seed: UInt64 = .random(in: .min ... .max)) {
        seeds = SplitMix64(seed: seed)
        maze = Maze(width: Self.columns, height: Self.rows, seed: 0)
        walker = MazeWalker(maze: maze, seed: 0)

        func material(_ image: CGImage, repeating: (CGFloat, CGFloat), shininess: CGFloat) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .blinn
            m.diffuse.contents = image
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(repeating.0, repeating.1, 1)
            m.diffuse.mipFilter = .linear
            m.diffuse.maxAnisotropy = 8
            m.specular.contents = NSColor(white: 0.18, alpha: 1)
            m.shininess = shininess
            return m
        }
        // One brick tile is 1.5 world units square. That divides a cell (3.0) exactly, so each wall segment, which
        // starts its texture afresh, lines up with its neighbour instead of leaving a seam every cell.
        let tile: CGFloat = 1.5
        let bricks = MazeTextures.bricks()
        wallMaterial = material(bricks, repeating: ((3 + 0.3) / tile, 2.6 / tile), shininess: 0.1)
        endMaterial = material(bricks, repeating: (0.3 / tile, 2.6 / tile), shininess: 0.1)   // the thin end of a wall
        floorMaterial = material(MazeTextures.floor(), repeating: (CGFloat(Self.columns) * 3 / 3, CGFloat(Self.rows) * 3 / 3), shininess: 0.4)
        ceilingMaterial = material(MazeTextures.ceiling(), repeating: (CGFloat(Self.columns) * 3 / 1.5, CGFloat(Self.rows) * 3 / 1.5), shininess: 0.05)

        scene.background.contents = NSColor.black
        scene.fogColor = NSColor.black
        scene.fogStartDistance = 5
        scene.fogEndDistance = 22
        scene.fogDensityExponent = 1

        let camera = SCNCamera()
        camera.fieldOfView = 62
        camera.zNear = 0.05
        camera.zFar = 80
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        // A torch carried at head height, so walls glow nearby and fade into the dark ahead.
        let torch = SCNNode()
        torch.light = SCNLight()
        torch.light?.type = .omni
        torch.light?.color = NSColor(red: 1, green: 0.93, blue: 0.82, alpha: 1)
        torch.light?.intensity = 1500
        torch.light?.attenuationStartDistance = 1.5
        torch.light?.attenuationEndDistance = 16
        torch.light?.attenuationFalloffExponent = 2
        torch.position = SCNVector3(x: 0, y: 0.25, z: 0)
        cameraNode.addChildNode(torch)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = NSColor(white: 0.16, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        rebuild()
        renderer = OffscreenSceneRenderer(scene: scene, pointOfView: cameraNode, width: 1280, height: 720)
    }

    func frame(at time: CFTimeInterval) -> CIImage? {
        let elapsed = lastTime.map { max(0, time - $0) } ?? 0
        lastTime = time

        // SceneKit batches node changes until a run loop turn ends. Frames are made on a dispatch queue with no
        // run loop, so commit explicitly or the renderer never sees anything after the first frame.
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        walker.advance(by: elapsed)
        if walker.cellsTraveled >= cellsPerMaze { rebuild() }
        let due = lastRender.map { time - $0.time >= frameInterval } ?? true
        if due { place(walker.pose) }
        SCNTransaction.commit()

        guard due else { return lastRender?.image }
        guard let image = renderer?.render(at: time) else { return lastRender?.image }
        lastRender = (time, image)
        return image
    }

    // MARK: Building

    private func rebuild() {
        world.removeFromParentNode()
        world = SCNNode()
        scene.rootNode.addChildNode(world)

        maze = Maze(width: Self.columns, height: Self.rows, seed: seeds.next())
        walker = MazeWalker(maze: maze, seed: seeds.next())
        mazesBuilt += 1

        let length = cell + wallThickness
        let along = SCNBox(width: length, height: wallHeight, length: wallThickness, chamferRadius: 0)      // runs east-west
        let across = SCNBox(width: wallThickness, height: wallHeight, length: length, chamferRadius: 0)     // runs north-south
        // Box faces run front, right, back, left, top, bottom. The long faces get the full brick; the thin ends, which
        // show wherever a wall stops at a corner, get a brick scaled to fit rather than the texture squashed flat.
        along.materials = [wallMaterial, endMaterial, wallMaterial, endMaterial, endMaterial, endMaterial]
        across.materials = [endMaterial, wallMaterial, endMaterial, wallMaterial, endMaterial, endMaterial]

        func wall(_ geometry: SCNBox, x: CGFloat, z: CGFloat) {
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(x: x, y: wallHeight / 2, z: z)
            world.addChildNode(node)
        }
        // Each wall once: a cell supplies its north and west sides; the last row and column add the far edges.
        for y in 0..<maze.height {
            for x in 0..<maze.width {
                let c = Maze.Cell(x, y)
                let cx = CGFloat(x) * cell, cz = CGFloat(y) * cell
                if !maze.isOpen(c, .north) { wall(along, x: cx, z: cz - cell / 2) }
                if !maze.isOpen(c, .west) { wall(across, x: cx - cell / 2, z: cz) }
                if y == maze.height - 1 { wall(along, x: cx, z: cz + cell / 2) }
                if x == maze.width - 1 { wall(across, x: cx + cell / 2, z: cz) }
            }
        }

        let width = CGFloat(maze.width) * cell, depth = CGFloat(maze.height) * cell
        let centre = SCNVector3(x: CGFloat(maze.width - 1) * cell / 2, y: 0, z: CGFloat(maze.height - 1) * cell / 2)

        let floor = SCNNode(geometry: SCNPlane(width: width, height: depth))
        floor.geometry?.materials = [floorMaterial]
        floor.eulerAngles = SCNVector3(x: -.pi / 2, y: 0, z: 0)
        floor.position = centre
        world.addChildNode(floor)

        let ceiling = SCNNode(geometry: SCNPlane(width: width, height: depth))
        ceiling.geometry?.materials = [ceilingMaterial]
        ceiling.eulerAngles = SCNVector3(x: .pi / 2, y: 0, z: 0)
        ceiling.position = SCNVector3(x: centre.x, y: wallHeight, z: centre.z)
        world.addChildNode(ceiling)

        place(walker.pose)
    }

    private func place(_ pose: MazeWalker.Pose) {
        cameraNode.position = SCNVector3(x: CGFloat(pose.x) * cell, y: eyeHeight, z: CGFloat(pose.y) * cell)
        cameraNode.eulerAngles = SCNVector3(x: 0, y: CGFloat(pose.yaw), z: 0)
    }
}
