import Foundation
import UIKit
import SwiftUI

private extension Color {
    var codable: CodableColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
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
        var thumbnailImage: UIImage?

        for (index, layer) in canvasManager.layers.enumerated() {
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

                celManifests.append(CelManifest(id: cel.id, startFrame: cel.startFrame, frameCount: cel.frameCount,
                                                 rasterFileName: fileName, fillImageFileName: fillFileName, bakedImageFileName: bakedFileName))
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
                cels: celManifests
            ))

            if thumbnailImage == nil, layer.isVisible, let canvasSize = canvasManager.canvasSize,
               let celIdx = canvasManager.activeCelIndex(inLayer: index, atFrame: canvasManager.currentFrame) {
                let cel = layer.cels[celIdx]
                if layer.isObjectLayer {
                    thumbnailImage = layer.objectImage
                } else if cel.bakedImage != nil {
                    thumbnailImage = ThumbnailRenderer.render(PixelOps.rasterize(cel: cel, canvasSize: canvasSize), canvasSize: canvasSize, thumbnailSize: CGSize(width: 320, height: 320))
                } else {
                    thumbnailImage = ThumbnailRenderer.render(cel.raster, fillImage: cel.fillImage, canvasSize: canvasSize, thumbnailSize: CGSize(width: 320, height: 320))
                }
            }
        }

        // TODO(brush-wiring): CanvasManager doesn't have `selectedBrush` on this base yet — Worker
        // B is adding it (see CLAUDE.md worker brief). Once it lands, replace this default with
        // the manager's actual selected brush (and whatever custom-brush list it ends up owning)
        // so the user's brush choice persists too. Using a sensible default in the meantime keeps
        // this compiling and the manifest schema stable regardless of when that property arrives.
        let selectedBrush = BrushLibrary.softRound
        let customBrushes: [Brush] = []
        copyCustomBrushTexturesIntoProject([selectedBrush] + customBrushes, projectURL: url)

        let manifest = ProjectManifest(
            id: canvasManager.projectID,
            name: canvasManager.projectName,
            canvasWidth: Double(canvasManager.canvasSize?.width ?? 0),
            canvasHeight: Double(canvasManager.canvasSize?.height ?? 0),
            fps: canvasManager.fps,
            sceneFrameCount: canvasManager.sceneFrameCount,
            layers: layerManifests,
            modifiedAt: Date(),
            backgroundColor: canvasManager.canvasBackgroundColor.codable,
            isBackgroundVisible: canvasManager.isCanvasBackgroundVisible,
            selectedBrush: selectedBrush,
            customBrushes: customBrushes
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
        manager.fps = manifest.fps
        manager.sceneFrameCount = manifest.sceneFrameCount
        manager.canvasBackgroundColor = manifest.backgroundColor.color
        manager.isCanvasBackgroundVisible = manifest.isBackgroundVisible

        // Restore this project's own custom-brush texture copies into the shared library if a
        // referenced file is missing there (project moved to another device, or the global entry
        // was deleted) — see copyCustomBrushTexturesIntoProject's doc comment for the save side.
        restoreCustomBrushTexturesFromProject([manifest.selectedBrush] + manifest.customBrushes, projectURL: url)
        // TODO(brush-wiring): once Worker B adds `canvasManager.selectedBrush` (and whatever list
        // of custom brushes it ends up owning), wire the decoded values in here, e.g.:
        //   manager.selectedBrush = manifest.selectedBrush
        // Nothing is lost in the meantime — the metadata round-trips correctly and the texture
        // files are restored above — it's just not connected to the UI/tool state yet.

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
                cels.append(Cel(id: celManifest.id, startFrame: celManifest.startFrame, frameCount: celManifest.frameCount,
                                 raster: raster, fillImage: fillImage, bakedImage: bakedImage))
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

            layers.append(Layer(
                id: layerManifest.id,
                name: layerManifest.name,
                opacity: layerManifest.opacity,
                isVisible: layerManifest.isVisible,
                kind: layerManifest.kind,
                isObjectLayer: layerManifest.isObjectLayer,
                objectImage: objectImage,
                objectTransform: transform,
                cels: cels
            ))
        }

        manager.layers = layers
        manager.currentLayerIndex = 0
        manager.regenerateAllThumbnails()
        return manager
    }
}
