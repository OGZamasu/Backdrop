import CoreGraphics
import CoreImage

/// Makes the live source for each scene drawn in code.
enum ProceduralBackdrop {
    static func makeSource(for style: ProceduralStyle) -> BackgroundSource {
        switch style {
        case .starfield: return StarfieldSource()
        case .synthwave: return SynthwaveSource()
        case .lavaLamp: return LavaLampSource()
        case .bokeh: return BokehSource()
        case .plasma: return PlasmaSource()
        case .fireflies: return FirefliesSource()
        case .rain: return RainWindowSource()
        case .homeOffice: return BackdropStudioSet(.homeOffice)
        case .library: return BackdropStudioSet(.library)
        case .brickLoft: return BackdropStudioSet(.brickLoft)
        case .plantCorner: return BackdropStudioSet(.plantCorner)
        case .podcastStudio: return BackdropStudioSet(.podcast)
        case .galleryWall: return BackdropStudioSet(.gallery)
        case .woodSlats: return BackdropStudioSet(.woodSlats)
        case .coffeeShop: return BackdropStudioSet(.coffeeShop)
        case .mountainLake: return BackdropMountainLake()
        case .desertDunes: return BackdropDesertDunes()
        case .sunsetBeach: return BackdropSunsetBeach()
        case .forestLight: return BackdropForestLight()
        case .snowyCabin: return BackdropSnowyCabin()
        case .nightSkyline: return BackdropNightSkyline()
        case .tokyoRain: return BackdropTokyoRain()
        case .liquidMarble: return BackdropLiquidMarble()
        case .northernLights: return BackdropNorthernLights()
        case .topographic: return BackdropTopographic()
        case .lowPoly: return BackdropLowPoly()
        case .vaporwave: return BackdropVaporwave()
        case .driftingClouds: return BackdropDriftingClouds()
        case .campfire: return BackdropCampfire()
        case .aquarium: return BackdropAquarium()
        case .nebula: return BackdropNebula()
        case .cherryBlossom: return BackdropCherryBlossom()
        case .digitalRain: return BackdropDigitalRain()
        case .autumnLeaves: return BackdropAutumnLeaves()
        case .holidayLights: return BackdropHolidayLights()
        }
    }

    /// A still of the scene for the picker, `width` pixels across: the real source at a moment where it looks its best.
    static func thumbnail(for style: ProceduralStyle, width: Int = 480) -> CGImage? {
        let source = makeSource(for: style)
        defer { source.stop() }
        guard let frame = source.frame(at: style.thumbnailMoment, camera: CIImage.empty()) else { return nil }
        let scale = CGFloat(width) / 1280
        let size = CGRect(x: 0, y: 0, width: width, height: Int((720 * scale).rounded()))
        return thumbnailContext.createCGImage(frame.transformed(by: CGAffineTransform(scaleX: scale, y: scale)), from: size,
                                              format: .RGBA8, colorSpace: BackdropCanvas.space)
    }

    fileprivate static let thumbnailContext = CIContext()
}

/// Pictures of the built-ins for the picker, made by their real sources so a tile shows exactly what you get.
enum BackdropThumbnail {
    /// A still of `background`, `width` pixels across, or nil for kinds that come from files, windows or 3D scenes.
    static func render(_ background: Background, width: Int = 480) -> CGImage? {
        let source: BackgroundSource
        var moment = 6.0
        var camera = CIImage.empty()
        switch background.kind {
        case .procedural(let style): return ProceduralBackdrop.thumbnail(for: style, width: width)
        case .gradient(let preset): source = GradientSource(preset: preset); moment = 12
        case .solid(let hex, let lit): source = SolidBackdropSource(hex: hex, lit: lit)
        case .treated(let treatment): source = CameraTreatmentSource(treatment); camera = demoRoom
        case .blur(let radius): source = BlurSource(radius: radius); camera = demoRoom
        default: return nil
        }
        guard let frame = source.frame(at: moment, camera: camera) else { return nil }
        let fitted = frame.transformed(by: CGAffineTransform(translationX: -frame.extent.minX, y: -frame.extent.minY))
        let scale = CGFloat(width) / max(1, fitted.extent.width)
        let size = CGRect(x: 0, y: 0, width: width, height: Int((fitted.extent.height * scale).rounded()))
        return ProceduralBackdrop.thumbnailContext.createCGImage(fitted.transformed(by: CGAffineTransform(scaleX: scale, y: scale)), from: size,
                                                                 format: .RGBA8, colorSpace: BackdropCanvas.space)
    }

    /// A room to show the camera looks on: the home office set, as a camera might see a real one.
    static let demoRoom: CIImage = BackdropStudioSet(.homeOffice).frame(at: 0, camera: .empty()) ?? CIImage(color: .gray).cropped(to: BackdropPainter.frame)
}

private extension ProceduralStyle {
    /// Seconds into the scene to take its picture from.
    var thumbnailMoment: Double {
        switch self {
        case .starfield: return 20
        case .synthwave: return 3
        case .lavaLamp: return 33
        case .bokeh: return 14
        case .plasma: return 17
        case .fireflies: return 9
        case .rain: return 7
        default: return 6
        }
    }
}
