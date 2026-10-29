import AppKit
import CoreImage
import Metal
import SceneKit

/// Renders a SceneKit scene into a Metal texture and hands it back as a CIImage, without reading pixels back to the CPU.
final class OffscreenSceneRenderer {
    let width: Int
    let height: Int

    private let queue: MTLCommandQueue
    private let renderer: SCNRenderer
    private let resolved: MTLTexture
    private let pass = MTLRenderPassDescriptor()

    init?(scene: SCNScene, pointOfView: SCNNode, width: Int, height: Int, samples: Int = 4) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }

        func descriptor(_ format: MTLPixelFormat, usage: MTLTextureUsage, samples: Int, storage: MTLStorageMode) -> MTLTextureDescriptor {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            d.usage = usage
            d.storageMode = storage
            if samples > 1 { d.textureType = .type2DMultisample; d.sampleCount = samples }
            return d
        }
        guard let resolved = device.makeTexture(descriptor: descriptor(.bgra8Unorm, usage: [.renderTarget, .shaderRead], samples: 1, storage: .shared)),
              let color = device.makeTexture(descriptor: descriptor(.bgra8Unorm, usage: .renderTarget, samples: samples, storage: .private)),
              let depth = device.makeTexture(descriptor: descriptor(.depth32Float_stencil8, usage: .renderTarget, samples: samples, storage: .private))
        else { return nil }

        self.width = width
        self.height = height
        self.queue = queue
        self.resolved = resolved
        renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = pointOfView

        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].resolveTexture = resolved
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        pass.stencilAttachment.texture = depth
        pass.stencilAttachment.loadAction = .clear
        pass.stencilAttachment.storeAction = .dontCare
    }

    func render(at time: TimeInterval) -> CIImage? {
        guard let buffer = queue.makeCommandBuffer() else { return nil }
        renderer.render(atTime: time, viewport: CGRect(x: 0, y: 0, width: width, height: height),
                        commandBuffer: buffer, passDescriptor: pass)
        buffer.commit()
        // The result is read by a different command queue (Core Image's), so wait rather than race it.
        buffer.waitUntilCompleted()
        guard buffer.status == .completed,
              let image = CIImage(mtlTexture: resolved, options: [.colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        else { return nil }
        // Metal textures are stored top row first; Core Image counts rows from the bottom.
        return image.oriented(.downMirrored)
    }
}

/// The old Windows "3D Pipes" screensaver, behind you.
final class PipesSource: BackgroundSource {
    private var stage: PipesStage?

    // SceneKit objects are built and used only on the thread that asks for frames (the pipeline queue).
    func frame(at time: CFTimeInterval, camera: CIImage) -> CIImage? {
        if stage == nil { stage = PipesStage() }
        return stage?.frame(at: time)
    }

    func stop() { stage = nil }
}

final class PipesStage {
    static let palette: [NSColor] = [
        NSColor(red: 0.92, green: 0.20, blue: 0.20, alpha: 1),
        NSColor(red: 0.20, green: 0.78, blue: 0.30, alpha: 1),
        NSColor(red: 0.25, green: 0.45, blue: 0.95, alpha: 1),
        NSColor(red: 0.97, green: 0.80, blue: 0.15, alpha: 1),
        NSColor(red: 0.85, green: 0.30, blue: 0.85, alpha: 1),
        NSColor(red: 0.15, green: 0.80, blue: 0.85, alpha: 1),
        NSColor(red: 0.98, green: 0.55, blue: 0.15, alpha: 1),
        NSColor(red: 0.85, green: 0.88, blue: 0.92, alpha: 1),
    ]

    private let scene = SCNScene()
    private let pipes = SCNNode()
    private let cameraNode = SCNNode()
    private var growth: PipeGrowth
    private var renderer: OffscreenSceneRenderer?

    // Bold enough to survive video compression, which smears thin lines away.
    private static let pipeRadius: CGFloat = 0.21
    private static let jointRadius: CGFloat = 0.31
    private let cylinders: [SCNCylinder]
    private let spheres: [SCNSphere]

    private let stepInterval: CFTimeInterval = 0.06
    private let frameInterval: CFTimeInterval = 1.0 / 24
    private var lastStep: CFTimeInterval?
    private var lastRender: (time: CFTimeInterval, image: CIImage)?
    private var growing: [(node: SCNNode, started: CFTimeInterval, axis: Bool)] = []
    private var origin: CFTimeInterval?

    /// Where the pipes' cube is centred, so the camera can look at it.
    private var centre: SIMD3<Float> {
        let d = growth.dimensions
        return SIMD3<Float>(Float(d.x - 1) / 2, Float(d.y - 1) / 2, Float(d.z - 1) / 2)
    }

    init(seed: UInt64 = .random(in: .min ... .max)) {
        growth = PipeGrowth(seed: seed)

        func material(_ color: NSColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .blinn
            m.diffuse.contents = color
            m.specular.contents = NSColor.white
            m.shininess = 0.85
            return m
        }
        cylinders = Self.palette.map { color in
            let g = SCNCylinder(radius: Self.pipeRadius, height: 1)
            g.radialSegmentCount = 24
            g.materials = [material(color)]
            return g
        }
        spheres = Self.palette.map { color in
            let g = SCNSphere(radius: Self.jointRadius)
            g.segmentCount = 28
            g.materials = [material(color)]
            return g
        }

        scene.background.contents = NSColor.black
        scene.rootNode.addChildNode(pipes)

        let camera = SCNCamera()
        camera.fieldOfView = 46
        camera.zNear = 0.1
        camera.zFar = 200
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = NSColor(white: 0.30, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        func omni(_ position: SCNVector3, _ color: NSColor, _ intensity: CGFloat) {
            let node = SCNNode()
            node.light = SCNLight()
            node.light?.type = .omni
            node.light?.color = color
            node.light?.intensity = intensity
            node.position = position
            scene.rootNode.addChildNode(node)
        }
        omni(SCNVector3(x: 6, y: 16, z: 22), NSColor(white: 1, alpha: 1), 1200)
        omni(SCNVector3(x: -20, y: -8, z: 14), NSColor(red: 0.6, green: 0.7, blue: 1, alpha: 1), 500)

        renderer = OffscreenSceneRenderer(scene: scene, pointOfView: cameraNode, width: 1280, height: 720)
        placeCamera(at: 0)
    }

    func frame(at time: CFTimeInterval) -> CIImage? {
        if origin == nil { origin = time; lastStep = time }
        let elapsed = time - (origin ?? time)

        // SceneKit batches node changes into an implicit transaction that only commits when a run loop turn ends.
        // This runs on a dispatch queue with no run loop, so without an explicit transaction the renderer would
        // never see anything added after the first frame.
        SCNTransaction.begin()
        SCNTransaction.disableActions = true

        // Grow in fixed steps however fast frames arrive, but never try to catch up on a long stall in one go.
        var steps = 0
        while let last = lastStep, time - last >= stepInterval, steps < 6 {
            lastStep = last + stepInterval
            apply(growth.step(), at: time)
            steps += 1
        }
        if steps == 6 { lastStep = time }

        let due = lastRender.map { time - $0.time >= frameInterval } ?? true
        if due {
            updateGrowingNodes(at: time)
            placeCamera(at: elapsed)
        }
        SCNTransaction.commit()

        guard due else { return lastRender?.image }
        guard let image = renderer?.render(at: elapsed) else { return lastRender?.image }
        lastRender = (time, image)
        return image
    }

    // MARK: Scene

    private func position(of cell: PipeGrowth.Cell) -> SCNVector3 {
        let c = centre
        let x = CGFloat(Float(cell.x) - c.x)
        let y = CGFloat(Float(cell.y) - c.y)
        let z = CGFloat(Float(cell.z) - c.z)
        return SCNVector3(x: x, y: y, z: z)
    }

    private func apply(_ events: [PipeGrowth.Event], at time: CFTimeInterval) {
        for event in events {
            switch event {
            case .clear:
                pipes.childNodes.forEach { $0.removeFromParentNode() }
                growing.removeAll()
            case .start(let cell, let color, _):
                addJoint(at: cell, color: color, time: time)
            case .end(let cell, let color, _):
                addJoint(at: cell, color: color, time: time)
            case .extend(let from, let to, let color, let turned, _):
                if turned { addJoint(at: from, color: color, time: time) }
                addSegment(from: from, to: to, color: color, time: time)
            }
        }
    }

    private func addJoint(at cell: PipeGrowth.Cell, color: Int, time: CFTimeInterval) {
        let node = SCNNode(geometry: spheres[color])
        node.position = position(of: cell)
        node.scale = SCNVector3(0.2, 0.2, 0.2)
        pipes.addChildNode(node)
        growing.append((node, time, false))
    }

    private func addSegment(from: PipeGrowth.Cell, to: PipeGrowth.Cell, color: Int, time: CFTimeInterval) {
        let node = SCNNode(geometry: cylinders[color])
        let direction = SIMD3<Float>(Float(to.x - from.x), Float(to.y - from.y), Float(to.z - from.z))
        // Pivot at one end so the pipe extends outward from where it left off, instead of swelling from its middle.
        node.pivot = SCNMatrix4MakeTranslation(0, -0.5, 0)
        node.position = position(of: from)
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction)
        node.scale = SCNVector3(1, 0.02, 1)
        pipes.addChildNode(node)
        growing.append((node, time, true))
    }

    private func updateGrowingNodes(at time: CFTimeInterval) {
        growing.removeAll { entry in
            let t = min(1, (time - entry.started) / (stepInterval * 1.5))
            if entry.axis {
                entry.node.scale = SCNVector3(1, CGFloat(max(0.02, t)), 1)
            } else {
                // A little overshoot, so joints seem to pop into place.
                let s = CGFloat(0.2 + 0.8 * t + 0.15 * sin(t * .pi))
                entry.node.scale = SCNVector3(s, s, s)
            }
            guard t >= 1 else { return false }
            entry.node.scale = SCNVector3(1, 1, 1)
            return true
        }
    }

    /// Faces the wide box almost head-on and sways a few degrees. A full orbit would swing the box edge-on, where it
    /// is only a few cells wide, and the frame would be mostly black.
    private func placeCamera(at elapsed: CFTimeInterval) {
        let t = Float(elapsed)
        let yaw = 0.13 * sin(t * 0.11)
        let lift = 0.5 * sin(t * 0.07 + 1)
        // Close enough that the box overfills the frame: its edges are always off-screen, never visible as a margin.
        let distance: Float = 13
        cameraNode.simdPosition = SIMD3<Float>(distance * sin(yaw), lift, distance * cos(yaw))
        cameraNode.simdLook(at: .zero, up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, -1))
    }
}
