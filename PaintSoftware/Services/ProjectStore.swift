import Foundation
import PencilKit
import UIKit
import SwiftUI

private extension Color {
    var codable: CodableColor {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
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

    @MainActor
    static func save(_ canvasManager: CanvasManager, to url: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        let celsDir = url.appendingPathComponent("cels", isDirectory: true)
        let imagesDir = url.appendingPathComponent("images", isDirectory: true)
        try? fm.createDirectory(at: celsDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        var layerManifests: [LayerManifest] = []
        var thumbnailImage: UIImage?

        for (index, layer) in canvasManager.layers.enumerated() {
            var imageFileName: String?
            if layer.isImageLayer, let image = layer.backgroundImage, let data = image.pngData() {
                let fileName = "\(layer.id.uuidString).png"
                try? data.write(to: imagesDir.appendingPathComponent(fileName))
                imageFileName = fileName
            }

            var celManifests: [CelManifest] = []
            for cel in layer.cels {
                let fileName = "\(cel.id.uuidString).drawing"
                let data = cel.drawing.dataRepresentation()
                try? data.write(to: celsDir.appendingPathComponent(fileName))
                celManifests.append(CelManifest(id: cel.id, startFrame: cel.startFrame, frameCount: cel.frameCount, drawingFileName: fileName))
            }

            layerManifests.append(LayerManifest(
                id: layer.id,
                name: layer.name,
                opacity: layer.opacity,
                isVisible: layer.isVisible,
                isImageLayer: layer.isImageLayer,
                backgroundImageFileName: imageFileName,
                cels: celManifests
            ))

            if thumbnailImage == nil, layer.isVisible, let canvasSize = canvasManager.canvasSize,
               let celIdx = canvasManager.activeCelIndex(inLayer: index, atFrame: canvasManager.currentFrame) {
                thumbnailImage = ThumbnailRenderer.render(layer.cels[celIdx].drawing, canvasSize: canvasSize, thumbnailSize: CGSize(width: 320, height: 320))
            }
        }

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
            isBackgroundVisible: canvasManager.isCanvasBackgroundVisible
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

        let celsDir = url.appendingPathComponent("cels", isDirectory: true)
        let imagesDir = url.appendingPathComponent("images", isDirectory: true)

        var layers: [Layer] = []
        for layerManifest in manifest.layers {
            var backgroundImage: UIImage?
            if let fileName = layerManifest.backgroundImageFileName {
                backgroundImage = UIImage(contentsOfFile: imagesDir.appendingPathComponent(fileName).path)
            }

            var cels: [Cel] = []
            for celManifest in layerManifest.cels {
                let drawingURL = celsDir.appendingPathComponent(celManifest.drawingFileName)
                let drawing = (try? Data(contentsOf: drawingURL)).flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
                cels.append(Cel(id: celManifest.id, startFrame: celManifest.startFrame, frameCount: celManifest.frameCount, drawing: drawing))
            }

            layers.append(Layer(
                id: layerManifest.id,
                name: layerManifest.name,
                opacity: layerManifest.opacity,
                isVisible: layerManifest.isVisible,
                isImageLayer: layerManifest.isImageLayer,
                backgroundImage: backgroundImage,
                cels: cels
            ))
        }

        manager.layers = layers
        manager.currentLayerIndex = 0
        manager.regenerateAllThumbnails()
        return manager
    }
}
