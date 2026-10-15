import UIKit

/// A mixed cel and its ordinary PixelOps-rendered reference, for native backing/pose comparisons.
/// This authors scene data only; both pictures use the normal layer and canvas routes.
enum LiquifyRasterUITestSeeds {
    @MainActor
    static func seedIfRequested(into manager: CanvasManager) {
        guard ProjectBackupManager.honoursGalleryReset(isSimulator: ProjectBackupManager.isSimulator),
              (ProcessInfo.processInfo.arguments.contains("-uiTestSeedLiquifyBacking") ||
               ProcessInfo.processInfo.arguments.contains("-uiTestSeedEraserBacking")),
              let size = manager.canvasSize, !manager.layers.isEmpty else { return }
        if ProcessInfo.processInfo.arguments.contains("-uiTestSeedEraserBacking") {
            seedEraser(into: manager, size: size)
            return
        }
        manager.streamCoordinator.startsClients = false
        let bounds = CGRect(origin: .zero, size: size)
        let backing = UIGraphicsImageRenderer(size: size, format: PixelOps.transparentFormat()).image { ctx in
            UIColor.red.setFill()
            let triangle = UIBezierPath()
            triangle.move(to: CGPoint(x: size.width * 0.18, y: size.height * 0.18))
            triangle.addLine(to: CGPoint(x: size.width * 0.48, y: size.height * 0.28))
            triangle.addLine(to: CGPoint(x: size.width * 0.25, y: size.height * 0.52))
            triangle.close(); triangle.fill()
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: size.width * 0.68, y: size.height * 0.72,
                            width: size.width * 0.06, height: size.height * 0.06))
        }
        manager.layers[0].kind = .vector
        manager.layers[0].name = "Backing"
        manager.layers[0].cels[0].bakedImage = backing
        let vector = VectorCanvas.empty(size: size)
        let green = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 18), format: PixelOps.transparentFormat()).image { ctx in
            UIColor.green.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 18, height: 18))
        }
        vector.addImage(VectorImageElement(image: green,
            transform: LayerTransform(position: CGPoint(x: size.width * 0.64, y: size.height * 0.25), scale: 1, rotation: 0)))
        manager.layers[0].cels[0].vector = vector
        manager.addTransformLayer(name: "Pose")
        let affine = CGAffineTransform(scaleX: 0.88, y: 0.88)
            .concatenating(CGAffineTransform(rotationAngle: 0.22))
            .concatenating(CGAffineTransform(translationX: size.width * 0.16, y: size.height * 0.07))
        manager.layers[1].transform = LayerPose(pose: PoseQuad(box: bounds, mappedBy: affine), mode: .move)
        let pose = manager.inkPose(forLayerID: manager.layers[0].id)
        let cel = manager.layers[0].cels[0]
        let derived = manager.derivedCelContent(for: cel, atFrame: 0, inheriting: pose)
        guard let reference = PixelOps.rasterize(cel: cel, canvasSize: size, memoize: false, derived: derived, pose: pose)
        else { preconditionFailure("The posed reference fixture must render before the drive") }
        manager.addLayer(name: "Reference")
        manager.layers[2].cels[0].bakedImage = reference
        manager.layers[2].isVisible = false
        manager.addVectorLayer(name: "Screen")
        let streamCanvas = manager.layers[3].cels[0].vector!
        let stream = VectorStreamElement(naturalSize: CGSize(width: 20, height: 10), host: "fixture.invalid", port: 47301,
            sourceLabel: "fixture", rendersInPlace: true,
            transform: LayerTransform(position: CGPoint(x: size.width * 0.84, y: size.height * 0.8), scale: 1, rotation: 0))
        streamCanvas.elements = [.stream(stream)]
        streamCanvas.bumpVersion()
        let screen = UIGraphicsImageRenderer(size: stream.naturalSize, format: PixelOps.transparentFormat()).image { ctx in
            UIColor.blue.setFill(); ctx.fill(CGRect(origin: .zero, size: stream.naturalSize))
        }
        streamCanvas.setStreamFrame(id: stream.id, image: screen, index: 1)
        manager.currentLayerIndex = 0
        manager.history.removeAll()
    }

    @MainActor
    private static func seedEraser(into manager: CanvasManager, size: CGSize) {
        manager.streamCoordinator.startsClients = false
        let bounds = CGRect(origin: .zero, size: size)
        manager.layers[0].kind = .vector
        manager.layers[0].name = "Stationary backing"
        manager.layers[0].cels[0].bakedImage = UIGraphicsImageRenderer(size: size,
            format: PixelOps.transparentFormat()).image { ctx in
                UIColor.red.setFill()
                for x in [32, 96, 160] { ctx.fill(CGRect(x: x, y: 24, width: 16, height: 120)) }
            }
        let brush = Brush(name: "fixture", tip: .round, size: 8, dab: BrushDabSettings(hardness: 1))
        let stroke = VectorStroke(brush: brush, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
            size: 8, opacity: 1, samples: StrokeSamples([VectorSample(x: 32, y: 80),
                VectorSample(x: 160, y: 80)], channels: .pressureOnly))
        manager.layers[0].cels[0].vector = VectorCanvas(size: size, elements: [.stroke(stroke)])
        manager.layers[0].cels[0].transformTracks[TransformChannelID.cel.id] = TransformTrack(box: bounds,
            curves: [.x: AnimationCurve(keys: [.init(frame: 0, value: Double(bounds.midX + 32))])])
        if ProcessInfo.processInfo.arguments.contains("-uiTestSeedEraserStream") {
            manager.addVectorLayer(name: "Screen")
            let stream = VectorStreamElement(naturalSize: CGSize(width: 12, height: 8),
                host: "fixture.invalid", port: 47301, sourceLabel: "fixture", rendersInPlace: true,
                transform: LayerTransform(position: CGPoint(x: 220, y: 180), scale: 1, rotation: 0))
            let canvas = manager.layers[1].cels[0].vector!
            canvas.elements = [.stream(stream)]; canvas.bumpVersion()
            let image = UIGraphicsImageRenderer(size: stream.naturalSize,
                format: PixelOps.transparentFormat()).image { ctx in
                    UIColor.blue.setFill(); ctx.fill(CGRect(origin: .zero, size: stream.naturalSize))
                }
            canvas.setStreamFrame(id: stream.id, image: image, index: 1)
        }
        manager.currentLayerIndex = 0
        manager.history.removeAll()
    }

}
