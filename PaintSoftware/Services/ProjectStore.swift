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
    /// True when the package failed manifest decode or integrity validation (missing/truncated
    /// files). Such projects are *surfaced* in the gallery (with a recovery affordance) rather
    /// than silently dropped — see ProjectBackupManager.
    var isCorrupted: Bool = false
}

enum ProjectStore {
    static var projectsDirectory: URL {
        // Single source of truth for the Projects/Backups/Trash layout lives in
        // ProjectBackupManager so the two can never drift apart.
        ProjectBackupManager.projectsDirectory
    }

    static func listProjects() -> [ProjectSummary] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls.compactMap { url -> ProjectSummary? in
            guard url.pathExtension == "paintproj" else { return nil }
            if let manifest = loadManifest(at: url), ProjectBackupManager.validateProject(at: url) {
                let thumbnail = UIImage(contentsOfFile: url.appendingPathComponent("thumbnail.png").path)
                return ProjectSummary(id: manifest.id, url: url, name: manifest.name, modifiedAt: manifest.modifiedAt, thumbnail: thumbnail)
            }
            // Damaged package (bad manifest or missing/truncated files): show it as damaged with a
            // recovery affordance instead of letting it vanish from the gallery.
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let modified = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
            return ProjectSummary(id: ProjectBackupManager.manifestID(at: url) ?? UUID(), url: url,
                                  name: url.deletingPathExtension().lastPathComponent,
                                  modifiedAt: modified, thumbnail: nil, isCorrupted: true)
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

    /// "Delete" never destroys data: the package moves to Trash (auto-purged only after
    /// `ProjectBackupManager.trashRetentionInterval`), and its version history in Backups/
    /// survives until then too.
    static func delete(at url: URL) {
        _ = ProjectBackupManager.moveToTrash(url, tag: "deleted")
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

    // MARK: - Saving

    /// Everything `writePackage` reads out of `@MainActor` state, captured as immutable values.
    ///
    /// This is what lets the encode-and-write half of a save run off the main thread while touching
    /// no live app state at all: the background queue works from `UIImage`s already rendered on main,
    /// value-type manifests, and `VectorCanvas` copies it owns outright. Nothing here is a view into
    /// something the user can still be drawing on, so a stroke landing mid-save can neither race the
    /// write nor contend with it for `RasterLayerTexture`'s lock.
    private struct SaveSnapshot {
        struct CelContent {
            let id: UUID
            let startFrame: Int
            let frameCount: Int
            /// Rendered on the main thread. `RasterLayerTexture` memoizes this per `version`, so for a
            /// cel that hasn't changed since it was last displayed it's a cache read, not a re-render.
            let rasterImage: UIImage
            let fillImage: UIImage?
            let bakedImage: UIImage?
            /// A `makeCopy()`, so the write owns it and live drawing can't mutate it underneath.
            let vector: VectorCanvas?
        }

        struct LayerContent {
            let id: UUID
            let name: String
            let opacity: Double
            let isVisible: Bool
            let kind: LayerKind
            let parentFolderID: UUID?
            let cels: [CelContent]
        }

        let projectID: UUID
        let projectName: String
        let canvasSize: CGSize
        let canvasPadding: Double
        let fps: Int
        let sceneFrameCount: Int
        let backgroundColor: CodableColor
        let isBackgroundVisible: Bool
        let selectedBrush: Brush
        let customBrushes: [Brush]
        let folders: [FolderManifest]
        let viewPresets: [ViewPresetManifest]
        let layers: [LayerContent]
        let thumbnail: UIImage?

        /// Reads published state and renders the per-cel images; deliberately does no encoding, so it
        /// stays the cheap half. The thumbnail composite stays here too rather than moving to the
        /// background queue: it goes through `PixelOps.compositeCanvas`, which reads the live
        /// `RasterLayerTexture`/`VectorCanvas` of every visible layer, and running it here keeps the
        /// rule that the background queue sees no shared mutable state. It is a handful of
        /// canvas-sized draws over caches this initialiser has just warmed — nothing like the
        /// multi-second PNG encode that is being moved off main.
        @MainActor
        init(_ canvasManager: CanvasManager) {
            projectID = canvasManager.projectID
            projectName = canvasManager.projectName
            canvasSize = canvasManager.canvasSize ?? .zero
            canvasPadding = Double(canvasManager.canvasPadding)
            fps = canvasManager.fps
            sceneFrameCount = canvasManager.sceneFrameCount
            backgroundColor = canvasManager.canvasBackgroundColor.codable
            isBackgroundVisible = canvasManager.isCanvasBackgroundVisible
            selectedBrush = canvasManager.selectedBrush
            customBrushes = canvasManager.customBrushes
            folders = canvasManager.folders.map { folder in
                FolderManifest(id: folder.id, name: folder.name, isExpanded: folder.isExpanded,
                               isVisible: folder.isVisible, parentFolderID: folder.parentFolderID)
            }
            viewPresets = canvasManager.viewPresets.map { preset in
                var vis: [String: Bool] = [:]
                for (key, value) in preset.layerVisibility { vis[key.uuidString] = value }
                var folderVis: [String: Bool] = [:]
                for (key, value) in preset.folderVisibility { folderVis[key.uuidString] = value }
                return ViewPresetManifest(id: preset.id, name: preset.name, layerVisibility: vis, folderVisibility: folderVis)
            }
            layers = canvasManager.layers.map { layer in
                LayerContent(id: layer.id, name: layer.name, opacity: layer.opacity,
                             isVisible: layer.isVisible, kind: layer.kind,
                             parentFolderID: layer.parentFolderID,
                             cels: layer.cels.map { cel in
                    CelContent(id: cel.id, startFrame: cel.startFrame, frameCount: cel.frameCount,
                               rasterImage: cel.raster.renderToUIImage(),
                               fillImage: cel.fillImage, bakedImage: cel.bakedImage,
                               vector: cel.vector?.makeCopy())
                })
            }

            // The composited stack of every visible layer (not just the bottom-most one) at the
            // current frame, downscaled for the gallery tile.
            if let size = canvasManager.canvasSize,
               let composited = PixelOps.compositeCanvas(layers: canvasManager.layers, atFrame: canvasManager.currentFrame, canvasSize: size) {
                thumbnail = ThumbnailRenderer.render(composited, canvasSize: size, thumbnailSize: CGSize(width: 320, height: 320))
            } else {
                thumbnail = nil
            }
        }
    }

    /// Serialises the encode-and-write half of every save. While that ran synchronously on the main
    /// actor, two saves could not interleave; now that it runs off main, this queue is what preserves
    /// that. Two overlapping saves — an autosave from `scenePhase` racing the user leaving the editor
    /// — must not interleave their stage/validate/stash/rename steps, or one could rename its package
    /// into place while the other is stashing what it believes is the live one.
    private static let saveQueue = DispatchQueue(label: "com.paintapp.ProjectStore.save", qos: .userInitiated)

    /// Saves atomically: the new package is fully written and validated at a temp path before the
    /// live package is touched, the live package is stashed as a backup (never destroyed), and the
    /// swap is a same-volume rename — so a crash/kill at ANY point leaves either the complete old
    /// package or the complete new one, plus restore points in Backups/ either way.
    ///
    /// Only the `SaveSnapshot` read is synchronous on the main actor; the PNG encoding, the JSON
    /// encoding and every file operation happen on `saveQueue`. Doing all of it on main blocked the
    /// UI for multiple seconds on a multi-layer, multi-cel project.
    ///
    /// `completion` runs on the main actor once the package is on disk — or once the save has failed,
    /// which it does not distinguish, matching the old signature's silence about failure. Callers that
    /// read the package back immediately must wait for it instead of racing the write: the gallery
    /// re-lists projects from disk in a one-shot `onAppear`, so navigating there before the rename
    /// lands would show the project as missing or stale.
    @MainActor
    static func save(_ canvasManager: CanvasManager, to url: URL, completion: (@MainActor () -> Void)? = nil) {
        let snapshot = SaveSnapshot(canvasManager)

        // A save is usually triggered by the app being backgrounded (see ContentView's scenePhase
        // handler). While it ran on main, iOS's "finish what you were doing" window covered it; work
        // dispatched to a background queue has to ask for that time explicitly or the process can be
        // suspended mid-write. The staged-then-renamed design means a suspended save loses the new
        // package rather than damaging the old one, but losing the user's last edits is still worth
        // avoiding. `.invalid` (assertion refused) is handled rather than assumed away.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ProjectStore.save")

        saveQueue.async {
            writeAtomically(snapshot, to: url)
            Task { @MainActor in
                completion?()
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                }
            }
        }
    }

    /// The staged-write-then-atomic-swap half of `save`, run off the main thread on `saveQueue` and
    /// working purely from `snapshot`.
    ///
    /// The step order here **is** the atomic-save guarantee built in session 34 and must not be
    /// rearranged: write the whole package to a temp path, validate it, stash the live package as a
    /// restore point rather than deleting it, then swap by same-volume rename. Moving this off the
    /// main thread changes which thread executes the steps, not their order or their all-or-nothing
    /// character — a crash or kill at any point still leaves either the complete old package or the
    /// complete new one on disk, never a partial one.
    private static func writeAtomically(_ snapshot: SaveSnapshot, to url: URL) {
        let fm = FileManager.default

        // Stage the new package beside the live one.
        let stageURL = projectsDirectory.appendingPathComponent(".saving-\(UUID().uuidString)", isDirectory: true)
        try? fm.removeItem(at: stageURL)
        writePackage(snapshot, to: stageURL)

        // Only replace the live package once the staged one is provably complete (e.g. a PNG that
        // failed to encode must not clobber the last-known-good save). The broken stage is kept
        // in Trash for diagnosis.
        guard ProjectBackupManager.validateProject(at: stageURL) else {
            _ = ProjectBackupManager.moveToTrash(stageURL, tag: "failedsave")
            return
        }

        // Stash the live package as an autosave restore point, then swap in the new one.
        guard ProjectBackupManager.stashLiveProjectForSave(projectURL: url, projectID: snapshot.projectID) else {
            try? fm.removeItem(at: stageURL)
            return
        }
        do {
            try fm.moveItem(at: stageURL, to: url)
        } catch {
            // Swap failed: put the stashed package back so the project is never missing.
            _ = ProjectBackupManager.restoreNewestValidBackup(forProjectAt: url, trashTag: "corrupt")
            try? fm.removeItem(at: stageURL)
            return
        }

        // Restore points: `latest` = exact copy of this save; autos rotated by count.
        ProjectBackupManager.refreshLatestSnapshot(projectURL: url, projectID: snapshot.projectID)
        ProjectBackupManager.pruneBackups(forProjectID: snapshot.projectID)
    }

    /// Writes the complete project package at `url` (used by `writeAtomically` to stage the package
    /// before the atomic swap). Runs on `saveQueue`, entirely from the snapshot — this is where the
    /// PNG and JSON encoding that used to block the main thread actually happens.
    private static func writePackage(_ snapshot: SaveSnapshot, to url: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        let imagesDir = url.appendingPathComponent("images", isDirectory: true)
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        var layerManifests: [LayerManifest] = []

        for layer in snapshot.layers {
            var celManifests: [CelManifest] = []
            for cel in layer.cels {
                let fileName = "\(cel.id.uuidString)_raster.png"
                if let data = cel.rasterImage.pngData() {
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
                // `cel.vector` is this save's own copy (see `SaveSnapshot.CelContent`), so reading its
                // strokes/fills/images here cannot race live drawing on the original.
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

            layerManifests.append(LayerManifest(
                id: layer.id,
                name: layer.name,
                opacity: layer.opacity,
                isVisible: layer.isVisible,
                kind: layer.kind,
                parentFolderID: layer.parentFolderID?.uuidString,
                cels: celManifests
            ))
        }

        // Persist the user's actual brush choice + imported custom brushes (Worker B's brush engine
        // owns these on CanvasManager) so they survive a save/reload, and copy any custom-brush
        // stamp textures into the project package for self-containment.
        copyCustomBrushTexturesIntoProject([snapshot.selectedBrush] + snapshot.customBrushes, projectURL: url)

        let manifest = ProjectManifest(
            id: snapshot.projectID,
            name: snapshot.projectName,
            canvasWidth: Double(snapshot.canvasSize.width),
            canvasHeight: Double(snapshot.canvasSize.height),
            canvasPadding: snapshot.canvasPadding,
            fps: snapshot.fps,
            sceneFrameCount: snapshot.sceneFrameCount,
            layers: layerManifests,
            modifiedAt: Date(),
            backgroundColor: snapshot.backgroundColor,
            isBackgroundVisible: snapshot.isBackgroundVisible,
            selectedBrush: snapshot.selectedBrush,
            customBrushes: snapshot.customBrushes,
            folders: snapshot.folders,
            viewPresets: snapshot.viewPresets
        )
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: url.appendingPathComponent("manifest.json"))
        }

        if let thumbnailImage = snapshot.thumbnail, let data = thumbnailImage.pngData() {
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
            LayerFolder(id: f.id, name: f.name, isExpanded: f.isExpanded, isVisible: f.isVisible,
                        parentFolderID: f.parentFolderID)
        }

        // Restore view presets.
        manager.viewPresets = manifest.viewPresets.map { vp in
            var vis: [UUID: Bool] = [:]
            for (key, value) in vp.layerVisibility {
                if let uuid = UUID(uuidString: key) { vis[uuid] = value }
            }
            var folderVis: [UUID: Bool] = [:]
            for (key, value) in vp.folderVisibility {
                if let uuid = UUID(uuidString: key) { folderVis[uuid] = value }
            }
            return ViewPreset(id: vp.id, name: vp.name, layerVisibility: vis, folderVisibility: folderVis)
        }

        let imagesDir = url.appendingPathComponent("images", isDirectory: true)
        let canvasSize = manager.canvasSize ?? CGSize(width: 1, height: 1)

        var layers: [Layer] = []
        for layerManifest in manifest.layers {
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

                // Vector content: decode the JSON (the ordered display list + image refs + transform)
                // and reload each placed image's PNG. A `.vector` layer with no saved payload (never
                // drawn) still gets an empty VectorCanvas so it stays a working vector layer.
                //
                // The list is restored in its saved order, which is what preserves z-position between
                // strokes, fills, images and erase elements. A legacy payload that predates the display
                // list has no order to restore, so `VectorCanvasData.init(from:)` reconstructs the one
                // the old renderer used (fills, then images, then strokes) while decoding.
                var vector: VectorCanvas?
                if let vectorFileName = celManifest.vectorFileName,
                   let data = try? Data(contentsOf: imagesDir.appendingPathComponent(vectorFileName)),
                   let payload = try? JSONDecoder().decode(VectorCanvasData.self, from: data) {
                    let elements = payload.elements { ref in
                        UIImage(contentsOfFile: imagesDir.appendingPathComponent(ref.fileName).path)
                    }
                    vector = VectorCanvas(size: canvasSize, elements: elements, transform: payload.affineTransform)
                } else if layerManifest.kind == .vector {
                    vector = .empty(size: canvasSize)
                }

                cels.append(Cel(id: celManifest.id, startFrame: celManifest.startFrame, frameCount: celManifest.frameCount,
                                 raster: raster, fillImage: fillImage, bakedImage: bakedImage, vector: vector))
            }

            let parentID = layerManifest.parentFolderID.flatMap { UUID(uuidString: $0) }
            layers.append(Layer(
                id: layerManifest.id,
                name: layerManifest.name,
                opacity: layerManifest.opacity,
                isVisible: layerManifest.isVisible,
                kind: layerManifest.kind,
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
