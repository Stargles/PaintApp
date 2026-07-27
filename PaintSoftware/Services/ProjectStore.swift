import Foundation
import UIKit
import SwiftUI

private extension Color {
    var codable: CodableColor {
        let c = rgbaComponents
        return CodableColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
}

private extension CodableColor {
    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

struct ProjectSummary: Identifiable {
    let id: UUID
    let url: URL
    let name: String
    let modifiedAt: Date
    let thumbnail: UIImage?
}

enum ProjectStore {
    static var projectsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Projects", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func listProjects() -> [ProjectSummary] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls.compactMap { url -> ProjectSummary? in
            guard url.pathExtension == "paintproj", let manifest = loadManifest(at: url) else { return nil }
            let thumbnail = UIImage(contentsOfFile: url.appendingPathComponent("thumbnail.png").path)
            return ProjectSummary(id: manifest.id, url: url, name: manifest.name, modifiedAt: manifest.modifiedAt, thumbnail: thumbnail)
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    static func createNewProjectURL(name: String) -> URL {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : name
        var candidate = base
        var url = projectsDirectory.appendingPathComponent("\(candidate).paintproj")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            candidate = "\(base) \(suffix)"
            url = projectsDirectory.appendingPathComponent("\(candidate).paintproj")
            suffix += 1
        }
        return url
    }

    static func delete(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func loadManifest(at projectURL: URL) -> ProjectManifest? {
        let manifestURL = projectURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode(ProjectManifest.self, from: data)
    }

    /// Copies any `.custom`-shaped brush's imported stamp texture from the shared
    /// `BrushLibrary.customBrushesDirectory` into this project's own `brushes/` folder, so a saved
    /// project is self-contained: its custom brushes still render correctly even if the global
    /// library entry is later renamed/deleted, or the project is moved to another device. Best
    /// effort — a brush with no matching source file (or a built-in shape) is silently skipped.
    private static func copyCustomBrushTexturesIntoProject(_ brushes: [Brush], projectURL: URL) {
        let customShaped = brushes.filter { $0.shape == .custom }
        guard !customShaped.isEmpty else { return }
        let fm = FileManager.default
        let brushesDir = projectURL.appendingPathComponent("brushes", isDirectory: true)
        try? fm.createDirectory(at: brushesDir, withIntermediateDirectories: true)
        for brush in customShaped {
            guard let fileName = brush.customTextureFileName else { continue }
            let source = BrushLibrary.customBrushesDirectory.appendingPathComponent(fileName)
            guard fm.fileExists(atPath: source.path) else { continue }
            let destination = brushesDir.appendingPathComponent(fileName)
            try? fm.removeItem(at: destination) // overwrite if re-saving
            try? fm.copyItem(at: source, to: destination)
        }
    }

    /// The inverse of the above, run on load: if a custom brush's texture file is missing from the
    /// shared `BrushLibrary.customBrushesDirectory` (project moved to another device, or the
    /// global entry was deleted since this project was last saved), restore it from this
    /// project's own `brushes/` copy so the brush still renders correctly.
    private static func restoreCustomBrushTexturesFromProject(_ brushes: [Brush], projectURL: URL) {
        let customShaped = brushes.filter { $0.shape == .custom }
        guard !customShaped.isEmpty else { return }
        let fm = FileManager.default
        let brushesDir = projectURL.appendingPathComponent("brushes", isDirectory: true)
        for brush in customShaped {
            guard let fileName = brush.customTextureFileName else { continue }
            let destination = BrushLibrary.customBrushesDirectory.appendingPathComponent(fileName)
            guard !fm.fileExists(atPath: destination.path) else { continue }
            let source = brushesDir.appendingPathComponent(fileName)
            guard fm.fileExists(atPath: source.path) else { continue }
            try? fm.copyItem(at: source, to: destination)
        }
    }

    @MainActor
    static func save(_ canvasManager: CanvasManager, to url: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        let imagesDir = url.appendingPathComponent("images", isDirectory: true)
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        var layerManifests: [LayerManifest] = []

        for layer in canvasManager.layers {
            var imageFileName: String?
            if layer.isObjectLayer, let image = layer.objectImage, let data = image.pngData() {
                let fileName = "\(layer.id.uuidString).png"
                try? data.write(to: imagesDir.appendingPathComponent(fileName))
                imageFileName = fileName
            }

            var celManifests: [CelManifest] = []
            for cel in layer.cels {
                let fileName = "\(cel.id.uuidString)_raster.png"
                if let data = cel.raster.renderToUIImage().pngData() {
                    try? data.write(to: imagesDir.appendingPathComponent(fileName))
                }

                var fillFileName: String?
                if let fillImage = cel.fillImage, let fillData = fillImage.pngData() {
                    let name = "\(cel.id.uuidString)-fill.png"
                    try? fillData.write(to: imagesDir.appendingPathComponent(name))
                    fillFileName = name
                }
                var bakedFileName: String?
                if let baked = cel.bakedImage, let bakedData = baked.pngData() {
                    bakedFileName = "\(cel.id.uuidString)_baked.png"
                    try? bakedData.write(to: imagesDir.appendingPathComponent(bakedFileName!))
                }

                // Vector content: write the placed images' PNGs, then a JSON of the strokes + image
                // refs + overall transform (see VectorCanvasData).
                var vectorFileName: String?
                if let vector = cel.vector, !vector.isEmpty {
                    var imageFileNames: [UUID: String] = [:]
                    for element in vector.images {
                        let name = element.fileName ?? "\(cel.id.uuidString)_vec_\(element.id.uuidString).png"
                        if let data = element.image.pngData() {
                            try? data.write(to: imagesDir.appendingPathComponent(name))
                            imageFileNames[element.id] = name
                        }
                    }
                    let payload = VectorCanvasData(from: vector, imageFileNames: imageFileNames)
                    if let data = try? JSONEncoder().encode(payload) {
                        vectorFileName = "\(cel.id.uuidString)_vector.json"
                        try? data.write(to: imagesDir.appendingPathComponent(vectorFileName!))
                    }
                }

                celManifests.append(CelManifest(id: cel.id, startFrame: cel.startFrame, frameCount: cel.frameCount,
                                                 rasterFileName: fileName, fillImageFileName: fillFileName, bakedImageFileName: bakedFileName,
                                                 vectorFileName: vectorFileName))
            }

            let transformManifest = layer.isObjectLayer
                ? ObjectTransformManifest(x: layer.objectTransform.position.x, y: layer.objectTransform.position.y,
                                           scale: layer.objectTransform.scale, rotation: layer.objectTransform.rotation)
                : nil

                layerManifests.append(LayerManifest(
                id: layer.id,
                name: layer.name,
                opacity: layer.opacity,
                isVisible: layer.isVisible,
                kind: layer.kind,
                isObjectLayer: layer.isObjectLayer,
                objectImageFileName: imageFileName,
                objectTransform: transformManifest,
                parentFolderID: layer.parentFolderID?.uuidString,
                cels: celManifests
            ))
        }

        // The composited stack of every visible layer (not just the bottom-most one) at the
        // current frame, downscaled for the gallery tile.
        var thumbnailImage: UIImage?
        if let canvasSize = canvasManager.canvasSize,
           let composited = PixelOps.compositeCanvas(layers: canvasManager.layers, atFrame: canvasManager.currentFrame, canvasSize: canvasSize) {
            thumbnailImage = ThumbnailRenderer.render(composited, canvasSize: canvasSize, thumbnailSize: CGSize(width: 320, height: 320))
        }

        // Persist the user's actual brush choice + imported custom brushes (Worker B's brush engine
        // owns these on CanvasManager) so they survive a save/reload, and copy any custom-brush
        // stamp textures into the project package for self-containment.
        let selectedBrush = canvasManager.selectedBrush
        let customBrushes = canvasManager.customBrushes
        copyCustomBrushTexturesIntoProject([selectedBrush] + customBrushes, projectURL: url)

        let folderManifests = canvasManager.folders.map { folder in
            FolderManifest(id: folder.id, name: folder.name, isExpanded: folder.isExpanded, isVisible: folder.isVisible)
        }
        let viewPresetManifests = canvasManager.viewPresets.map { preset in
            var vis: [String: Bool] = [:]
            for (key, value) in preset.layerVisibility { vis[key.uuidString] = value }
            return ViewPresetManifest(id: preset.id, name: preset.name, layerVisibility: vis)
        }

        let manifest = ProjectManifest(
            id: canvasManager.projectID,
            name: canvasManager.projectName,
            canvasWidth: Double(canvasManager.canvasSize?.width ?? 0),
            canvasHeight: Double(canvasManager.canvasSize?.height ?? 0),
            canvasPadding: Double(canvasManager.canvasPadding),
            fps: canvasManager.fps,
            sceneFrameCount: canvasManager.sceneFrameCount,
            layers: layerManifests,
            modifiedAt: Date(),
            backgroundColor: canvasManager.canvasBackgroundColor.codable,
            isBackgroundVisible: canvasManager.isCanvasBackgroundVisible,
            selectedBrush: selectedBrush,
            customBrushes: customBrushes,
            folders: folderManifests,
            viewPresets: viewPresetManifests
        )
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: url.appendingPathComponent("manifest.json"))
        }

        if let thumbnailImage, let data = thumbnailImage.pngData() {
            try? data.write(to: url.appendingPathComponent("thumbnail.png"))
        }
    }

    @MainActor
    static func load(from url: URL) -> CanvasManager? {
        guard let manifest = loadManifest(at: url) else { return nil }

        let manager = CanvasManager()
        manager.projectID = manifest.id
        manager.projectName = manifest.name
        manager.projectURL = url
        manager.canvasSize = CGSize(width: manifest.canvasWidth, height: manifest.canvasHeight)
        // No resize on load: the buffers were saved at the full padded canvasSize; padding only drives
        // the paper inset that reveals the grey margin.
        manager.canvasPadding = CGFloat(manifest.canvasPadding)
        manager.fps = manifest.fps
        manager.sceneFrameCount = manifest.sceneFrameCount
        manager.canvasBackgroundColor = manifest.backgroundColor.color
        manager.isCanvasBackgroundVisible = manifest.isBackgroundVisible

        // Restore this project's own custom-brush texture copies into the shared library if a
        // referenced file is missing there (project moved to another device, or the global entry
        // was deleted) — see copyCustomBrushTexturesIntoProject's doc comment for the save side.
        restoreCustomBrushTexturesFromProject([manifest.selectedBrush] + manifest.customBrushes, projectURL: url)
        manager.customBrushes = manifest.customBrushes
        manager.selectBrush(manifest.selectedBrush)

        // Restore folders.
        manager.folders = manifest.folders.map { f in
            LayerFolder(id: f.id, name: f.name, isExpanded: f.isExpanded, isVisible: f.isVisible)
        }

        // Restore view presets.
        manager.viewPresets = manifest.viewPresets.map { vp in
            var vis: [UUID: Bool] = [:]
            for (key, value) in vp.layerVisibility {
                if let uuid = UUID(uuidString: key) { vis[uuid] = value }
            }
            return ViewPreset(id: vp.id, name: vp.name, layerVisibility: vis)
        }

        let imagesDir = url.appendingPathComponent("images", isDirectory: true)
        let canvasSize = manager.canvasSize ?? CGSize(width: 1, height: 1)

        var layers: [Layer] = []
        for layerManifest in manifest.layers {
            var objectImage: UIImage?
            if let fileName = layerManifest.objectImageFileName {
                objectImage = UIImage(contentsOfFile: imagesDir.appendingPathComponent(fileName).path)
            }

            var cels: [Cel] = []
            for celManifest in layerManifest.cels {
                let rasterURL = imagesDir.appendingPathComponent(celManifest.rasterFileName)
                let raster = UIImage(contentsOfFile: rasterURL.path).map { RasterLayerTexture.load(from: $0, size: canvasSize) }
                    ?? .empty(size: canvasSize)
                var fillImage: UIImage?
                if let fillFileName = celManifest.fillImageFileName {
                    fillImage = UIImage(contentsOfFile: imagesDir.appendingPathComponent(fillFileName).path)
                }
                var bakedImage: UIImage?
                if let bakedFileName = celManifest.bakedImageFileName {
                    bakedImage = UIImage(contentsOfFile: imagesDir.appendingPathComponent(bakedFileName).path)
                }

                // Vector content: decode the JSON (strokes + image refs + transform) and reload each
                // placed image's PNG. A `.vector` layer with no saved payload (never drawn) still gets
                // an empty VectorCanvas so it stays a working vector layer.
                var vector: VectorCanvas?
                if let vectorFileName = celManifest.vectorFileName,
                   let data = try? Data(contentsOf: imagesDir.appendingPathComponent(vectorFileName)),
                   let payload = try? JSONDecoder().decode(VectorCanvasData.self, from: data) {
                    let images: [VectorImageElement] = payload.images.compactMap { ref in
                        guard let img = UIImage(contentsOfFile: imagesDir.appendingPathComponent(ref.fileName).path) else { return nil }
                        return VectorImageElement(image: img,
                                                  transform: LayerTransform(position: CGPoint(x: ref.x, y: ref.y), scale: ref.scale, rotation: ref.rotation),
                                                  fileName: ref.fileName)
                    }
                    vector = VectorCanvas(size: canvasSize, strokes: payload.strokes, fills: payload.fills, images: images, transform: payload.affineTransform)
                } else if layerManifest.kind == .vector {
                    vector = .empty(size: canvasSize)
                }

                cels.append(Cel(id: celManifest.id, startFrame: celManifest.startFrame, frameCount: celManifest.frameCount,
                                 raster: raster, fillImage: fillImage, bakedImage: bakedImage, vector: vector))
            }

            let transform: LayerTransform
            if let m = layerManifest.objectTransform {
                transform = LayerTransform(position: CGPoint(x: m.x, y: m.y), scale: m.scale, rotation: m.rotation)
            } else if let objectImage, let canvasSize = manager.canvasSize, objectImage.size.width > 0 {
                // Pre-object-layer project: reproduce the old full-bleed appearance as a starting
                // transform (covering the canvas, centered, unrotated) that the user can adjust.
                let coverScale = max(canvasSize.width / objectImage.size.width, canvasSize.height / objectImage.size.height)
                transform = LayerTransform(position: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2), scale: coverScale, rotation: 0)
            } else {
                transform = .identity
            }

            let parentID = layerManifest.parentFolderID.flatMap { UUID(uuidString: $0) }
            layers.append(Layer(
                id: layerManifest.id,
                name: layerManifest.name,
                opacity: layerManifest.opacity,
                isVisible: layerManifest.isVisible,
                kind: layerManifest.kind,
                isObjectLayer: layerManifest.isObjectLayer,
                objectImage: objectImage,
                objectTransform: transform,
                parentFolderID: parentID,
                cels: cels
            ))
        }

        manager.layers = layers
        manager.currentLayerIndex = 0
        manager.regenerateAllThumbnails()
        return manager
    }
}
