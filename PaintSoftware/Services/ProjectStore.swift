import Foundation
import UIKit
import SwiftUI
import os

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
            /// The cel's interpolation recipe, if it is a derived cel. A value type all the way
            /// down, so unlike `vector` it needs no defensive copy.
            let interpolation: InterpolationRecipe?
        }

        struct LayerContent {
            let id: UUID
            let name: String
            /// Whether `name` is the artist's own (`Layer.hasCustomName`). Snapshotted so the save can
            /// write it: a name that survives a reload but comes back auto-nameable is the failure the
            /// flag exists to prevent, arriving one launch late.
            let hasCustomName: Bool
            let opacity: Double
            let isVisible: Bool
            let kind: LayerKind
            let parentFolderID: UUID?
            let blendMode: BlendMode
            let alphaMask: AlphaMask?
            /// A `.value` layer's grade — §4.4's effect mode. A value type, so unlike `vector` it
            /// needs no defensive copy to be safe to encode off main.
            let effect: Effect?
            /// A `.value` layer's flat colour — §4.5's other mode. A value type, for `effect`'s
            /// reason. Both are snapshotted unconditionally: the mode is which one is *live*, and a
            /// layer in effect mode still carries the colour it will go back to (`Layer.valueFill`).
            let fill: ValueFill?
            let fillReferenceOverride: Bool?
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
        let vectorEraserMode: VectorEraserMode
        let folders: [FolderManifest]
        let viewPresets: [ViewPresetManifest]
        let motionGroups: [MotionGroup]
        let guideStrokes: [GuideStroke]
        let layers: [LayerContent]
        let thumbnail: UIImage?

        /// The box the gallery tile fits into — the composite's size hint *and* the renderer's
        /// target, deliberately one constant so the two cannot drift apart. Named rather than
        /// written twice because the whole point of the size hint is that the composite and the tile
        /// agree; two literals is exactly how they would stop agreeing.
        static let thumbnailBounds = CGSize(width: 320, height: 320)

        /// Reads published state and renders the per-cel images; deliberately does no encoding, so it
        /// stays the cheap half. It is a handful of canvas-sized draws over caches this initialiser
        /// has just warmed — nothing like the multi-second PNG encode that is being moved off main.
        ///
        /// The thumbnail composite stays here too, but the reason has changed since the compositor
        /// landed. It used to be forced: `PixelOps.compositeCanvas` read the live
        /// `RasterLayerTexture`/`VectorCanvas` of every visible layer, so running it anywhere but the
        /// main actor would have broken the rule that the background queue sees no shared mutable
        /// state. Now only `makeRenderRequest` reads live objects, and `Compositor.composite` is pure
        /// — so the composite *could* move off main, and stays because the snapshot it needs is built
        /// here anyway and the work is small. LAYER_COMPOSITING.md §9.1 point 3 is what bought that
        /// freedom, and §9.2 is what will eventually spend it.
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
            vectorEraserMode = canvasManager.vectorEraserMode
            folders = canvasManager.folders.map { folder in
                FolderManifest(id: folder.id, name: folder.name, hasCustomName: folder.hasCustomName,
                               isExpanded: folder.isExpanded,
                               isVisible: folder.isVisible, parentFolderID: folder.parentFolderID,
                               opacity: folder.opacity, blendMode: folder.blendMode,
                               isIsolated: folder.isIsolated, alphaMask: folder.alphaMask,
                               compositorRole: folder.compositorRole, effect: folder.effect)
            }
            viewPresets = canvasManager.viewPresets.map { preset in
                var vis: [String: Bool] = [:]
                for (key, value) in preset.layerVisibility { vis[key.uuidString] = value }
                var folderVis: [String: Bool] = [:]
                for (key, value) in preset.folderVisibility { folderVis[key.uuidString] = value }
                return ViewPresetManifest(id: preset.id, name: preset.name, layerVisibility: vis, folderVisibility: folderVis)
            }
            motionGroups = canvasManager.motionGroups
            guideStrokes = canvasManager.guideStrokes
            layers = canvasManager.layers.map { layer in
                LayerContent(id: layer.id, name: layer.name, hasCustomName: layer.hasCustomName,
                             opacity: layer.opacity,
                             isVisible: layer.isVisible, kind: layer.kind,
                             parentFolderID: layer.parentFolderID, blendMode: layer.blendMode,
                             alphaMask: layer.alphaMask, effect: layer.effect, fill: layer.fill,
                             fillReferenceOverride: layer.fillReferenceOverride,
                             cels: layer.cels.map { cel in
                    CelContent(id: cel.id, startFrame: cel.startFrame, frameCount: cel.frameCount,
                               rasterImage: cel.raster.renderToUIImage(),
                               fillImage: cel.fillImage, bakedImage: cel.bakedImage,
                               vector: cel.vector?.makeCopy(),
                               interpolation: cel.interpolation)
                })
            }

            // The composited stack of every visible layer (not just the bottom-most one) at the
            // current frame, downscaled for the gallery tile.
            //
            // `includeBackground: false` is what shipped and is kept deliberately: this thumbnail has
            // always been transparent-backed. That is a real defect — the gallery draws tiles on
            // black, so a default white document shows black around its artwork — but it is a defect
            // about what the thumbnail *should* contain, not about which code composites it, and
            // rolling it into the phase that removes the second compositor would make a behaviour
            // change look like a refactor.
            // **The composite is sized to the tile it becomes, which it was not until 2026-08-20.**
            // It used to render the whole canvas — 2,097,152 pixels at the owner's 2048×1024 to fill
            // the 51,200 a 320-wide tile actually occupies, and 16.8M at 4096² — on the main actor,
            // inside every save. `fittingWithin` is the same box `ThumbnailRenderer` fits into, passed
            // to both, so the composite's aspect and the tile's come from one rule rather than two.
            // The renderer's downscale is then very nearly the identity and is kept: it is what makes
            // this correct for a canvas whose aspect the budget clamp did move, and it costs a copy
            // of a tile-sized image.
            if let size = canvasManager.canvasSize,
               let request = canvasManager.makeRenderRequest(atFrame: canvasManager.currentFrame,
                                                             includeBackground: false,
                                                             fittingWithin: Self.thumbnailBounds),
               let composited = Compositor.composite(request) {
                thumbnail = ThumbnailRenderer.render(UIImage(cgImage: composited, scale: 1, orientation: .up),
                                                     canvasSize: size, thumbnailSize: Self.thumbnailBounds)
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

                // The interpolation recipe, when this cel is a derived one. Its own JSON file for the
                // same reason the vector payload has one: it is unbounded in size (lattices) and the
                // gallery reads every manifest in full.
                var interpolationFileName: String?
                if let recipe = cel.interpolation, let data = try? JSONEncoder().encode(recipe) {
                    interpolationFileName = "\(cel.id.uuidString)_interp.json"
                    try? data.write(to: imagesDir.appendingPathComponent(interpolationFileName!))
                }

                celManifests.append(CelManifest(id: cel.id, startFrame: cel.startFrame, frameCount: cel.frameCount,
                                                 rasterFileName: fileName, fillImageFileName: fillFileName, bakedImageFileName: bakedFileName,
                                                 vectorFileName: vectorFileName,
                                                 interpolationFileName: interpolationFileName))
            }

            layerManifests.append(LayerManifest(
                id: layer.id,
                name: layer.name,
                hasCustomName: layer.hasCustomName,
                opacity: layer.opacity,
                isVisible: layer.isVisible,
                kind: layer.kind,
                parentFolderID: layer.parentFolderID?.uuidString,
                blendMode: layer.blendMode,
                alphaMask: layer.alphaMask,
                effect: layer.effect,
                fill: layer.fill,
                fillReferenceOverride: layer.fillReferenceOverride,
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
            vectorEraserMode: snapshot.vectorEraserMode,
            folders: snapshot.folders,
            viewPresets: snapshot.viewPresets,
            motionGroups: snapshot.motionGroups,
            guideStrokes: snapshot.guideStrokes
        )
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: url.appendingPathComponent("manifest.json"))
        }

        if let thumbnailImage = snapshot.thumbnail, let data = thumbnailImage.pngData() {
            try? data.write(to: url.appendingPathComponent("thumbnail.png"))
        }
    }

    // MARK: - Loading

    /// Where the load path says what it could not read.
    ///
    /// **A log line, not a banner, and that is a decision rather than an omission.** `CanvasNotice`
    /// is the app's one notice mechanism and it is a 2.6-second self-dismissing strip whose own
    /// documentation says it "does not take a tap to get rid of" — built to inform an artist about
    /// something they just tried to do and can immediately retry. A cel that loaded short is neither:
    /// it is not actionable at the moment it happens, and the artist cannot un-drop the element. The
    /// *common* case is also the benign one — an unknown `kind` is a newer file in an older build, by
    /// design — so raising a banner on it at every project open would be noise attached to a
    /// non-event.
    ///
    /// What actually protects the artwork is already here: `ProjectBackupManager` stashes the pre-save
    /// package on **every** save, so the intact original survives a load that dropped something and is
    /// restorable. Whether a partial load should go further and *refuse to overwrite*, or prompt
    /// before it does, is a decision about save semantics and belongs to the owner, not to this fix.
    private static let log = Logger(subsystem: "Starg.PaintSoftware", category: "ProjectLoad")

    /// Says what a per-element decode dropped, keeping the two kinds apart — an unknown discriminator
    /// is an expected version gap and logs at `notice`; a malformed known element is a defect and logs
    /// at `error`. Silent when nothing was dropped, which is every ordinary load.
    private static func report(_ decodeReport: VectorCanvasData.DecodeReport, cel: UUID, file: String) {
        guard !decodeReport.isClean else { return }
        let cel = cel.uuidString
        if !decodeReport.unknownKinds.isEmpty {
            let kinds = Set(decodeReport.unknownKinds).sorted().joined(separator: ", ")
            log.notice("""
                Vector payload \(file, privacy: .public) for cel \(cel, privacy: .public) holds \
                \(decodeReport.unknownKinds.count, privacy: .public) element(s) of unknown kind \
                [\(kinds, privacy: .public)] — written by a newer build, skipped; the rest of the cel loaded
                """)
        }
        if decodeReport.malformedCount > 0 {
            log.error("""
                Vector payload \(file, privacy: .public) for cel \(cel, privacy: .public) holds \
                \(decodeReport.malformedCount, privacy: .public) malformed element(s) of a known kind — \
                skipped; the rest of the cel loaded
                """)
        }
    }

    /// What one `load(from:)` actually spent, split into the two halves PERFORMANCE.md item 9
    /// separates: the per-cel decode fan-out, and `regenerateAllThumbnails()`.
    ///
    /// **This exists because nobody could say whether opening a project costs 200 ms or 4 s.**
    /// PERFORMANCE.md §6 calls that the largest unmeasured quantity in the app, and the spinner that
    /// shipped on 2026-08-20 changed what the wait *looks* like rather than how long it is. Two
    /// `CFAbsoluteTimeGetCurrent()` reads per project open is the whole cost of knowing.
    ///
    /// **`celCount` travels with the timings deliberately.** The decode is driven by cel count, not
    /// by canvas area — the manifest's layer/cel tree is the loop bound — so a millisecond figure
    /// without it cannot be scaled to the document the artist actually has, which is the mistake
    /// PERFORMANCE.md §1 exists to record.
    struct LoadProfile: Equatable {
        var layerCount: Int
        var celCount: Int
        /// Manifest decode plus the per-cel PNG decode and `RasterLayerTexture` build — everything
        /// up to but not including the thumbnail walk.
        var decodeSeconds: Double
        /// `regenerateAllThumbnails()`. Guaranteed cache-cold: every texture the decode just built
        /// is a new object identity at version 0, so nothing memoized on cel identity can hit.
        var thumbnailSeconds: Double
        var totalSeconds: Double
        /// `CanvasManager.thumbnailRegenerationCount` at the end of the load. An integer about the
        /// calls rather than a millisecond about a machine, which is the more durable half of this
        /// instrument — see `CompositeProbe` for the same reasoning one subsystem over.
        var thumbnailRegenerations: Int

        /// Milliseconds per cel — the figure that scales to a document of another size, and the one
        /// worth quoting.
        var millisecondsPerCel: Double { celCount > 0 ? totalSeconds * 1000 / Double(celCount) : 0 }

        /// The thumbnail walk's share of the whole open, 0...1.
        var thumbnailShare: Double { totalSeconds > 0 ? thumbnailSeconds / totalSeconds : 0 }
    }

    /// The profile of the most recent `load(from:)`, or nil if none has run. Read by
    /// `PerfBaselineTests`; nothing in the app reads it, and nothing branches on it.
    @MainActor private(set) static var lastLoadProfile: LoadProfile?

    @MainActor
    static func load(from url: URL) -> CanvasManager? {
        let loadStarted = CFAbsoluteTimeGetCurrent()
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
        // Assigned directly rather than through a `select…` helper: unlike a brush, the vector-eraser
        // mode carries no size/opacity to re-baseline, so there is nothing for such a helper to do.
        manager.vectorEraserMode = manifest.vectorEraserMode
        // Document-level interpolation state. Both default to empty for every project that predates
        // the feature or simply never used it.
        manager.motionGroups = manifest.motionGroups
        manager.guideStrokes = manifest.guideStrokes

        // Restore folders.
        manager.folders = manifest.folders.map { f in
            LayerFolder(id: f.id, name: f.name, hasCustomName: f.hasCustomName,
                        isExpanded: f.isExpanded, isVisible: f.isVisible,
                        parentFolderID: f.parentFolderID, opacity: f.opacity,
                        blendMode: f.blendMode, isIsolated: f.isIsolated, alphaMask: f.alphaMask,
                        compositorRole: f.compositorRole, effect: f.effect)
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
                //
                // **Three outcomes, kept apart deliberately**, because collapsing them into one `try?`
                // chain is exactly what made this a silent data-loss path. No file (nothing was saved);
                // a file that will not parse *as a payload* (unsalvageable, and loud); and a file that
                // parses with some entries unreadable — which now costs those entries alone, because
                // `VectorCanvasData` decodes element by element. An unrecognised `kind` written by a
                // newer build therefore costs one element rather than every stroke, fill and image on
                // the cel, which is the same reasoning the interpolation recipe below already applies.
                var vector: VectorCanvas?
                if let vectorFileName = celManifest.vectorFileName {
                    let vectorURL = imagesDir.appendingPathComponent(vectorFileName)
                    if let data = try? Data(contentsOf: vectorURL) {
                        do {
                            let payload = try JSONDecoder().decode(VectorCanvasData.self, from: data)
                            let elements = payload.elements { ref in
                                UIImage(contentsOfFile: imagesDir.appendingPathComponent(ref.fileName).path)
                            }
                            vector = VectorCanvas(size: canvasSize, elements: elements, transform: payload.affineTransform)
                            report(payload.decodeReport, cel: celManifest.id, file: vectorFileName)
                        } catch {
                            log.error("""
                                Vector payload \(vectorFileName, privacy: .public) for cel \
                                \(celManifest.id.uuidString, privacy: .public) is not readable as a payload — \
                                the cel loads empty: \(String(describing: error), privacy: .public)
                                """)
                        }
                    } else {
                        log.error("""
                            Vector payload \(vectorFileName, privacy: .public) for cel \
                            \(celManifest.id.uuidString, privacy: .public) is missing or unreadable on disk — \
                            the cel loads empty
                            """)
                    }
                }
                if vector == nil, layerManifest.kind == .vector {
                    vector = .empty(size: canvasSize)
                }

                // The interpolation recipe. A cel whose recipe file is missing or unreadable loads as
                // an ordinary cel rather than failing the whole project: the recipe *derives*
                // content, so losing it costs the link, not the drawing.
                var interpolation: InterpolationRecipe?
                if let interpolationFileName = celManifest.interpolationFileName,
                   let data = try? Data(contentsOf: imagesDir.appendingPathComponent(interpolationFileName)) {
                    interpolation = try? JSONDecoder().decode(InterpolationRecipe.self, from: data)
                }

                cels.append(Cel(id: celManifest.id, startFrame: celManifest.startFrame, frameCount: celManifest.frameCount,
                                 raster: raster, fillImage: fillImage, bakedImage: bakedImage, vector: vector,
                                 interpolation: interpolation))
            }

            let parentID = layerManifest.parentFolderID.flatMap { UUID(uuidString: $0) }
            layers.append(Layer(
                id: layerManifest.id,
                name: layerManifest.name,
                hasCustomName: layerManifest.hasCustomName,
                opacity: layerManifest.opacity,
                isVisible: layerManifest.isVisible,
                fillReferenceOverride: layerManifest.fillReferenceOverride,
                kind: layerManifest.kind,
                effect: layerManifest.effect,
                fill: layerManifest.fill,
                blendMode: layerManifest.blendMode,
                alphaMask: layerManifest.alphaMask,
                parentFolderID: parentID,
                cels: cels
            ))
        }

        manager.layers = layers
        migrateGroupVisibility(manager, folders: manifest.folders)
        manager.currentLayerIndex = 0
        let decodeFinished = CFAbsoluteTimeGetCurrent()
        manager.regenerateAllThumbnails()
        let loadFinished = CFAbsoluteTimeGetCurrent()
        lastLoadProfile = LoadProfile(
            layerCount: layers.count,
            celCount: layers.reduce(0) { $0 + $1.cels.count },
            decodeSeconds: decodeFinished - loadStarted,
            thumbnailSeconds: loadFinished - decodeFinished,
            totalSeconds: loadFinished - loadStarted,
            thumbnailRegenerations: manager.thumbnailRegenerationCount)
        return manager
    }

    /// The one-time §4.1 / §10.3 visibility migration, run on load and only for projects that
    /// predate phase 4.
    ///
    /// Until phase 4, hiding a folder *wrote through* to every descendant, so a saved hidden group
    /// is a group whose children are each independently flagged hidden. Now the folder's own flag
    /// gates its subtree instead, and those two states are no longer the same document: the old one
    /// still renders correctly on load — everything under the group is hidden either way — but the
    /// first time the artist un-hides that group, nothing comes back, because every child is still
    /// hidden in its own right. Nothing on screen explains why.
    ///
    /// So a pre-phase-4 folder that is hidden has its descendants — layers *and* subfolders — shown.
    /// **Nothing is lost that the old behaviour had not already lost**: the write-through clobbered
    /// per-child visibility at the moment the folder was hidden, reaching subfolders as well, so
    /// "everything under a hidden group is visible" is exactly the state the old code would itself
    /// have restored on re-show. Fill reference comes back with it for free, since a layer with no
    /// explicit answer derives it from visibility (§6.6). The hidden folder itself stays hidden —
    /// that flag is the one piece of the old state that was the artist's own decision rather than a
    /// side effect.
    ///
    /// It cannot fire twice and cannot fire on anything this build wrote: the signal is the absence
    /// of `opacity` from the folder's JSON, and every save from here on writes it (see
    /// `FolderManifest.init(from:)`).
    /// **The saved view presets need the same treatment, which §4.1 does not say.** It notes that
    /// restoring an old preset "still works, since presets snapshot both layer and folder visibility
    /// already" — true of what it renders, but a preset written under the write-through records every
    /// child of a hidden group as hidden, so applying one re-creates on demand exactly the state this
    /// migration exists to clear. Fixing the document and leaving the presets alone would mean the
    /// group comes back once and then empties again the next time the artist flips views.
    @MainActor
    private static func migrateGroupVisibility(_ manager: CanvasManager, folders: [FolderManifest]) {
        guard folders.contains(where: \.wasSavedBeforeGroupProperties) else { return }

        for folder in folders where !folder.isVisible {
            let descendantFolders = manager.folderSubtree(folder.id).subtracting([folder.id])
            let descendantLayerIDs = Set(manager.descendantLayerIndices(ofFolder: folder.id).map { manager.layers[$0].id })

            for index in manager.layers.indices where descendantLayerIDs.contains(manager.layers[index].id) {
                manager.layers[index].isVisible = true
            }
            for index in manager.folders.indices where descendantFolders.contains(manager.folders[index].id) {
                manager.folders[index].isVisible = true
            }

            for index in manager.viewPresets.indices where manager.viewPresets[index].folderVisibility[folder.id] == false {
                for id in descendantLayerIDs where manager.viewPresets[index].layerVisibility[id] != nil {
                    manager.viewPresets[index].layerVisibility[id] = true
                }
                for id in descendantFolders where manager.viewPresets[index].folderVisibility[id] != nil {
                    manager.viewPresets[index].folderVisibility[id] = true
                }
            }
        }
    }
}
