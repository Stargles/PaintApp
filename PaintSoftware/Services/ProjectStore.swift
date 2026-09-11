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
        listProjects(in: projectsDirectory)
    }

    /// The projects **directly inside** one directory of the tree — TODO (36). Sub-folders are
    /// `listFolders`' business, so that the gallery draws one row of tiles per level rather than a
    /// flattened list in which two files called "Shot 1" are indistinguishable.
    static func listProjects(in directory: URL) -> [ProjectSummary] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
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
        createNewProjectURL(name: name, in: projectsDirectory)
    }

    /// A free package name inside `directory`. The uniqueness is per-folder on purpose: two shots
    /// both called "Rough" in different scenes is the ordinary case once there are folders, and
    /// forcing "Rough 2" on the second would be the app renaming the artist's work for no reason.
    static func createNewProjectURL(name: String, in directory: URL) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // **Sanitised, which it was not** — TODO (57). This trimmed and fell back to "Untitled" and
        // did nothing else, so a brand-new project titled `Boat/Race` was handed to
        // `appendingPathComponent("Boat/Race.paintproj")`, where the embedded separator silently made
        // a real subfolder `Boat/` and filed the project inside it — permanently, because a rename
        // never moves a project between folders. A 300-character or heavy-emoji title was equally
        // unbounded. See `ProjectPackageName.stem(forTitle:)`.
        let base = ProjectPackageName.stem(forTitle: name)
        var candidate = base
        var url = directory.appendingPathComponent("\(candidate).paintproj")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            candidate = "\(base) \(suffix)"
            url = directory.appendingPathComponent("\(candidate).paintproj")
            suffix += 1
        }
        return url
    }

    // MARK: - Folders — TODO (36)

    /// One sub-folder of the project tree, as the gallery draws it.
    struct ProjectFolder: Identifiable, Equatable {
        let url: URL
        let name: String
        /// Projects anywhere beneath it, however deep. The count is what makes a folder tile mean
        /// something before you open it, and it is what the delete confirmation counts.
        let projectCount: Int
        var id: String { url.path }
    }

    /// The sub-folders of one directory, alphabetically.
    static func listFolders(in directory: URL) -> [ProjectFolder] {
        ProjectBackupManager.subfolders(of: directory).map {
            ProjectFolder(url: $0, name: $0.lastPathComponent,
                          projectCount: ProjectBackupManager.allProjectPackages(in: $0).count)
        }
    }

    /// Every folder in the tree, depth-first, each with how deep it sits — what a "move to…" picker
    /// needs to draw an indented list. The root is not included; callers offer it themselves.
    static func allFolders(under directory: URL? = nil, depth: Int = 0) -> [(folder: ProjectFolder, depth: Int)] {
        let root = directory ?? projectsDirectory
        var out: [(ProjectFolder, Int)] = []
        for folder in listFolders(in: root) {
            out.append((folder, depth))
            out.append(contentsOf: allFolders(under: folder.url, depth: depth + 1))
        }
        return out
    }

    enum FolderError: LocalizedError {
        case emptyName
        case nameTaken(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .emptyName: return "Give the folder a name."
            case .nameTaken(let name): return "There is already something called “\(name)” here."
            case .failed(let why): return why
            }
        }
    }

    /// Turns what the artist typed into something a filesystem will take, without silently accepting
    /// a different folder than they asked for. `/` and `:` are the two characters that would either
    /// create a nested path or be rewritten by the system, so they become spaces; a leading dot is
    /// dropped because a dot-folder is invisible to `subfolders` and the artist would never see it
    /// again.
    static func sanitizedFolderName(_ raw: String) -> String {
        var name = raw.replacingOccurrences(of: "/", with: " ")
                      .replacingOccurrences(of: ":", with: " ")
                      .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    static func createFolder(named raw: String, in directory: URL) throws -> URL {
        let name = sanitizedFolderName(raw)
        guard !name.isEmpty else { throw FolderError.emptyName }
        let url = directory.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw FolderError.nameTaken(name) }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            throw FolderError.failed(error.localizedDescription)
        }
        return url
    }

    @discardableResult
    static func renameFolder(at url: URL, to raw: String) throws -> URL {
        let name = sanitizedFolderName(raw)
        guard !name.isEmpty else { throw FolderError.emptyName }
        let destination = url.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
        if destination.standardizedFileURL == url.standardizedFileURL { return url }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw FolderError.nameTaken(name) }
        do {
            try FileManager.default.moveItem(at: url, to: destination)
        } catch {
            throw FolderError.failed(error.localizedDescription)
        }
        return destination
    }

    /// **Deleting a folder trashes the projects in it one by one, then removes the empty shell.**
    ///
    /// Not `removeItem` on the folder, which would be the obvious implementation and would destroy
    /// artwork outright — the one thing this app's storage layer has never done. Every package inside
    /// goes to Trash under its own name, so all of it is listed in Recently Deleted and restorable for
    /// seven days by machinery that already exists. Returns how many projects were trashed, which is
    /// the number the confirmation warned about.
    @discardableResult
    static func deleteFolder(at url: URL) -> Int {
        let packages = ProjectBackupManager.allProjectPackages(in: url)
        for package in packages { _ = ProjectBackupManager.moveToTrash(package, tag: "deleted") }
        // Whatever is left is folders and staging husks — no artwork, because the walk above found
        // every `.paintproj` beneath this point.
        try? FileManager.default.removeItem(at: url)
        return packages.count
    }

    /// Moves a project into another folder of the tree, keeping its name unless that name is taken.
    /// Returns the new URL, or nil if the move failed — a package left exactly where it was.
    @discardableResult
    static func moveProject(at url: URL, into directory: URL) -> URL? {
        let fm = FileManager.default
        guard url.deletingLastPathComponent().standardizedFileURL != directory.standardizedFileURL else { return url }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = url.deletingPathExtension().lastPathComponent
        var destination = directory.appendingPathComponent("\(base).paintproj")
        var suffix = 2
        while fm.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(base) \(suffix).paintproj")
            suffix += 1
        }
        return (try? fm.moveItem(at: url, to: destination)).map { destination }
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

    /// **Which imported tip files a saved package has to carry**, and it is two populations rather
    /// than one — BUGS.md's *"copied by the palette, not by what is drawn"*, fixed here.
    ///
    ///   * **The document's brush table** — every brush the ink in this file is actually made of. This
    ///     is the half that was missing. It was invisible while `addCustomBrush` only ever appended,
    ///     because the palette was then a superset of what any stroke could reference; BRUSH.md §2.10
    ///     ends that on purpose by minting a table entry per edit, so a document routinely holds
    ///     brushes no picker lists.
    ///   * **The palette** — `selectedBrush` and `customBrushes`, which `manifest.json` persists in
    ///     their own right (§8.1: the library and the table are different collections). A custom brush
    ///     the artist has imported but not yet drawn with is in no stroke's table and still has to
    ///     travel, or the picker comes back on another device pointing at a file that is not there.
    ///
    /// Neither subsumes the other, which is why this takes the union rather than choosing. What the
    /// two have in common is the *filter*, and that has one statement:
    /// `Brush.importedTextureFileNames` is empty for a built-in tip (it travels inside the binary)
    /// and for a round one (it is arithmetic), and since BRUSH.md §2.25 it answers for the brush's
    /// **paper** as well as its tip — a textured brush whose sheet did not travel is the same defect
    /// this method was written to close, one field along.
    private static func importedTextureFileNames(table: BrushTable, palette: [Brush]) -> Set<String> {
        palette.reduce(into: table.importedTextureFileNames) { $0.formUnion($1.importedTextureFileNames) }
    }

    /// Copies every imported stamp texture the given file names refer to out of the brush library
    /// (`BrushStorage.shared`) into this project's own `brushes/` folder, so a saved project is
    /// self-contained: its custom brushes still render correctly even if the library entry is later
    /// renamed/deleted, or the project is moved to another device. Best effort — a brush with no
    /// matching source file is silently skipped.
    ///
    /// **The library side goes through `BrushStorage` and the package side does not**, which is
    /// BRUSH.md §2.27's third requirement drawing exactly the line it means to: the package is this
    /// document's own folder and moves with the document, while the library is the thing that may
    /// one day be an external folder needing a security-scoped bracket around every read.
    private static func copyCustomBrushTexturesIntoProject(_ fileNames: Set<String>, projectURL: URL) {
        guard !fileNames.isEmpty else { return }
        let fm = FileManager.default
        let brushesDir = projectURL.appendingPathComponent("brushes", isDirectory: true)
        try? fm.createDirectory(at: brushesDir, withIntermediateDirectories: true)
        for fileName in fileNames {
            guard let data = BrushStorage.shared.read(fileName) else { continue }
            // `.atomic` rather than remove-then-copy: the same overwrite-if-re-saving, without a
            // window in which the package holds no file at all.
            try? data.write(to: brushesDir.appendingPathComponent(fileName), options: .atomic)
        }
    }

    /// The inverse of the above, run on load: if a custom brush's texture file is missing from the
    /// brush library (project moved to another device, or the library entry was deleted since this
    /// project was last saved), restore it from this project's own `brushes/` copy so the brush
    /// still renders correctly. Same union as the save side, from the same one function, so the two
    /// cannot walk different populations again.
    private static func restoreCustomBrushTexturesFromProject(_ fileNames: Set<String>, projectURL: URL) {
        guard !fileNames.isEmpty else { return }
        let brushesDir = projectURL.appendingPathComponent("brushes", isDirectory: true)
        for fileName in fileNames {
            guard !BrushStorage.shared.contains(fileName) else { continue }
            guard let data = try? Data(contentsOf: brushesDir.appendingPathComponent(fileName)) else { continue }
            try? BrushStorage.shared.write(data, to: fileName)
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
            ///
            /// **Nil when the texture has no backing bitmap at all**, which is every cel of a vector
            /// document and every cel of a raster layer nobody has drawn on yet. That nil is not
            /// merely an encode this save skips — asking a blank texture for its image is what
            /// *creates* the cost: `renderToUIImage()` has a non-optional return, so with no context
            /// it mints a canvas-sized transparent `UIImage` (16 MiB at the owner's 2048²) and
            /// memoizes it in `cachedImage`, where nothing ever drops it again. Deciding here, on the
            /// main actor, from `hasContent` rather than from a rendered image is what keeps that
            /// allocation from happening at all.
            let rasterImage: UIImage?
            let fillImage: UIImage?
            let bakedImage: UIImage?
            /// A `makeCopy()`, so the write owns it and live drawing can't mutate it underneath.
            let vector: VectorCanvas?
            /// The cel's interpolation recipe, if it is a derived cel. A value type all the way
            /// down, so unlike `vector` it needs no defensive copy.
            let interpolation: InterpolationRecipe?
            /// The cel's pose channels and any held baseline — KEYFRAMES.md §3.5. Value types all
            /// the way down, so like `interpolation` they need no defensive copy.
            let transformTracks: [String: TransformTrack]
            let pendingPoseBaselines: [String: PoseQuad]
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
            /// `Layer.effectTracks` — KEYFRAMES.md stage 2's keyframe tracks on that grade. A value
            /// type all the way down, so like `effect` it needs no defensive copy to be safe to
            /// encode off main. Snapshotted whole and unconditionally; deciding whether to *write* a
            /// key is `writePackage`'s job one level down, for the reason `LayerManifest.effectTracks`
            /// gives.
            let effectTracks: [String: AnimationCurve]
            /// `Layer.channelTracks` and `Layer.channelBaselines` — TODO (21)'s second channel kind.
            /// Value types, snapshotted whole and unconditionally for `effectTracks`' reason; empty
            /// maps to absent in `writePackage`.
            let channelTracks: [String: AnimationCurve]
            let channelBaselines: [String: Double]
            /// `Layer.keyframeMarks` and `Layer.pendingBaselines` — §2.26's bare marks and the value
            /// each channel is holding between two of them. Value types, snapshotted whole and
            /// unconditionally for `effectTracks`' reason; empty maps to absent in `writePackage`.
            let keyframeMarks: [Int]
            let pendingBaselines: [String: Double]
            /// A `.value` layer's flat colour — §4.5's other mode. A value type, for `effect`'s
            /// reason. Both are snapshotted unconditionally: the mode is which one is *live*, and a
            /// layer in effect mode still carries the colour it will go back to (`Layer.valueFill`).
            let fill: ValueFill?
            let fillReferenceOverride: Bool?
            /// `Layer.transform` — §4.4's transformation layer, the third of the `.value` layer's
            /// three payloads. A value type all the way down (`PoseQuad` and `TransformTrack` both
            /// are), so like `effect` and `fill` it needs no defensive copy to be safe off main, and
            /// it is snapshotted unconditionally for the same reason they are.
            let transform: LayerPose?
            /// `Layer.rotateSpeed` and `Layer.parallaxShare` — TRANSFORM_LAYER.md §5's two scalar
            /// rows. Plain values, snapshotted unconditionally; zero-to-absent for the speed is
            /// `writePackage`'s line, and the share is optional on both sides.
            let rotateSpeed: Double
            let parallaxShare: Double?
            /// §5.4's three shake amplitudes, the speed's twins: plain values, zero-to-absent on write.
            let shakeX: Double
            let shakeY: Double
            let shakeRotation: Double
            let cels: [CelContent]
        }

        let projectID: UUID
        let projectName: String
        let canvasSize: CGSize
        let canvasPadding: Double
        let fps: Int
        let backgroundColor: CodableColor
        let isBackgroundVisible: Bool
        let selectedBrush: Brush
        let customBrushes: [Brush]
        let vectorEraserMode: VectorEraserMode
        let folders: [FolderManifest]
        let viewPresets: [ViewPresetManifest]
        let motionGroups: [MotionGroup]
        let animationGroups: [AnimationGroup]
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
                               compositorRole: folder.compositorRole, effect: folder.effect,
                               // Empty maps to absent — §3.5's field-presence versioning, and the same
                               // line `writePackage` applies to `LayerManifest.effectTracks` one level
                               // down. It is here rather than there only because a folder is already a
                               // `FolderManifest` by the time the snapshot exists, while a layer is
                               // still a `LayerContent`; the rule is one rule.
                               effectTracks: folder.effectTracks.isEmpty ? nil : folder.effectTracks,
                               // The same empty-to-absent line on TODO (21)'s channel kind.
                               channelTracks: folder.channelTracks.isEmpty ? nil : folder.channelTracks,
                               channelBaselines: folder.channelBaselines.isEmpty ? nil : folder.channelBaselines,
                               keyframeMarks: folder.keyframeMarks.isEmpty ? nil : folder.keyframeMarks,
                               pendingBaselines: folder.pendingBaselines.isEmpty ? nil : folder.pendingBaselines,
                               // §4.4's container pose. Already optional in the model, so there is
                               // no empty-to-absent line to write: a folder nobody has posed carries
                               // nil and the synthesized encoder omits the key.
                               transform: folder.transform,
                               // TRANSFORM_LAYER.md §5's scalar rows: zero-to-absent for the speed,
                               // and the share is optional on both sides.
                               rotateSpeed: folder.rotateSpeed == 0 ? nil : folder.rotateSpeed,
                               parallaxShare: folder.parallaxShare,
                               shakeX: folder.shakeX == 0 ? nil : folder.shakeX,
                               shakeY: folder.shakeY == 0 ? nil : folder.shakeY,
                               shakeRotation: folder.shakeRotation == 0 ? nil : folder.shakeRotation)
            }
            viewPresets = canvasManager.viewPresets.map { preset in
                var vis: [String: Bool] = [:]
                for (key, value) in preset.layerVisibility { vis[key.uuidString] = value }
                var folderVis: [String: Bool] = [:]
                for (key, value) in preset.folderVisibility { folderVis[key.uuidString] = value }
                return ViewPresetManifest(id: preset.id, name: preset.name, layerVisibility: vis, folderVisibility: folderVis)
            }
            motionGroups = canvasManager.motionGroups
            animationGroups = canvasManager.animationGroups
            guideStrokes = canvasManager.guideStrokes
            layers = canvasManager.layers.map { layer in
                LayerContent(id: layer.id, name: layer.name, hasCustomName: layer.hasCustomName,
                             opacity: layer.opacity,
                             isVisible: layer.isVisible, kind: layer.kind,
                             parentFolderID: layer.parentFolderID, blendMode: layer.blendMode,
                             alphaMask: layer.alphaMask, effect: layer.effect,
                             effectTracks: layer.effectTracks,
                             channelTracks: layer.channelTracks,
                             channelBaselines: layer.channelBaselines,
                             keyframeMarks: layer.keyframeMarks,
                             pendingBaselines: layer.pendingBaselines,
                             fill: layer.fill,
                             fillReferenceOverride: layer.fillReferenceOverride,
                             transform: layer.transform,
                             rotateSpeed: layer.rotateSpeed,
                             parallaxShare: layer.parallaxShare,
                             shakeX: layer.shakeX, shakeY: layer.shakeY, shakeRotation: layer.shakeRotation,
                             cels: layer.cels.map { cel in
                    CelContent(id: cel.id, startFrame: cel.startFrame, frameCount: cel.frameCount,
                               rasterImage: cel.raster.hasContent ? cel.raster.renderToUIImage() : nil,
                               fillImage: cel.fillImage, bakedImage: cel.bakedImage,
                               vector: cel.vector?.makeCopy(),
                               interpolation: cel.interpolation,
                               transformTracks: cel.transformTracks,
                               pendingPoseBaselines: cel.pendingPoseBaselines)
                })
            }

            // The composited stack of every visible layer (not just the bottom-most one) at the
            // current frame, downscaled for the gallery tile.
            //
            // `includeBackground: true` — fixed 2026-08-27 (EFFECT_BACKDROP.md §5.3). Before, this
            // thumbnail was always transparent-backed, which was a real defect: the gallery draws
            // tiles on black, so a default white document showed black around its artwork. Now that
            // the canvas paper is a real, addressable background input (§1) rather than a `UIView`
            // painted behind the composite, `makeRenderRequest` can hand it to `Compositor` the same
            // way a live canvas already does, and the tile reads with the paper as the artist sees it.
            // Not a migration: existing tiles keep their old transparent look until that project is
            // next saved, so the gallery reads as mixed for a while — an eager regeneration pass was
            // ruled out (cost measured at 17% of a resize) and nothing here adds one back.
            // **The composite is sized to the tile it becomes, which it was not until 2026-08-20.**
            // It used to render the whole canvas — 2,097,152 pixels at the owner's 2048×1024 to fill
            // the 51,200 a 320-wide tile actually occupies, and 16.8M at 4096² — on the main actor,
            // inside every save. `RenderSizing.fitting` takes the same box `ThumbnailRenderer` fits
            // into, so the composite's aspect and the tile's come from one rule rather than two.
            // The renderer's downscale is then very nearly the identity and is kept: it is what makes
            // this correct for a canvas whose aspect the budget clamp did move, and it costs a copy
            // of a tile-sized image.
            // **A recipe composited chunk-wise, since RENDER.md stage 3.** The tile is small enough
            // that the plan is one chunk on any device, so nothing about this save's cost moves; what
            // moves is that there is one way for a whole frame to become an image (§2.15) rather than
            // a second path beside it.
            if let size = canvasManager.canvasSize,
               let recipe = canvasManager.makeFrameRecipe(atFrame: canvasManager.currentFrame,
                                                          includeBackground: true,
                                                          sizing: .fitting(Self.thumbnailBounds)),
               let composited = recipe.composite() {
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

    /// What one `save(_:to:)` actually spent, split into the phases PERFORMANCE.md §2 item 3 names.
    ///
    /// **This exists because "leaving to the gallery takes ~3 s" had never been measured at any
    /// resolution.** §1 says the wait is not the thumbnail but the whole-document PNG re-encode that
    /// navigation gates on, and that its cost scales with cel count rather than with canvas area —
    /// a claim nothing had tested. `LoadProfile` is the counterpart on the way in, and this is
    /// deliberately the same shape: a handful of `CFAbsoluteTimeGetCurrent()` reads, plus counts.
    ///
    /// **`celCount` and `pngsEncoded` travel with the timings deliberately, and they are the more
    /// durable half.** "How many cels did this save re-encode" survives a machine change, a contended
    /// run and a Debug/Release swap in a way a millisecond does not — the same reasoning
    /// `LoadProfile.thumbnailRegenerations` records one subsystem over. A save that stopped
    /// re-encoding unchanged cels would show up here as a count, whatever the clock said.
    struct SaveProfile: Equatable {
        var layerCount: Int
        var celCount: Int
        /// `SaveSnapshot.init` on the main actor. **The only part of a save that blocks the artist's
        /// thread** — everything below runs on `saveQueue` — so it and `totalSeconds` answer two
        /// different questions: what froze, and what the gallery waited for.
        var snapshotSeconds: Double
        /// Every `pngData()` and `JSONEncoder.encode` in the per-cel walk, **summed across whatever
        /// threads ran them**. Against `celWalkSeconds` below, the sum over the wall clock is the
        /// fan-out's speedup, which is why it is a sum rather than an elapsed time.
        var encodeSeconds: Double
        /// Every `Data.write(to:)` in the per-cel walk, summed the same way.
        var writeSeconds: Double
        /// Wall clock of the per-cel walk itself — the phase `encodeSeconds`/`writeSeconds` are the
        /// summed contents of.
        var celWalkSeconds: Double
        /// `writePackage` end to end: the per-cel walk, the custom-brush copy, the manifest, the
        /// thumbnail PNG.
        var packageSeconds: Double
        /// `writeAtomically` minus `writePackage` — validate, stash, rename, refresh, prune. The
        /// atomic-save machinery, kept separate because it is O(cel count) in *file opens* while the
        /// walk above is O(cel count) in pixels, and the two would otherwise be one number.
        var swapSeconds: Double
        /// `save` being called to the package being on disk. What `ContentView.returnToGallery`
        /// waits on before it shows the gallery.
        var totalSeconds: Double
        /// How many PNG encodes this save attempted. One per raster cel, plus fills, baked images and
        /// placed vector images — so it is ≥ `celCount` on a real document and exactly `celCount` on
        /// a raster-only one.
        var pngsEncoded: Int
        /// How many PNG encodes something answered without running the encoder. Zero today; the
        /// field exists because it is the count a memoizing save would move, and PERFORMANCE.md §5
        /// names that memo as the one permitted intermediate on this path.
        var pngsReused: Int
        var bytesWritten: Int
        /// Whether the encode-and-write half ran on the main thread. False is what `saveQueue` is
        /// *for*, and this is the flag that would notice if it silently stopped being true — the
        /// same role `LoadProfile.decodedOnMainThread` plays on the way in.
        var encodedOnMainThread: Bool
        /// How many distinct threads the per-cel walk ran on. **An integer about the fan-out rather
        /// than a millisecond about a machine**: 1 is a serial walk and >1 is a spread one, and no
        /// amount of host load changes which.
        var encodeThreads: Int

        /// Milliseconds per cel — the figure that scales to a document of another size, and the one
        /// worth quoting. The loop bound is the cel tree, so this is what makes a 32-cel reading say
        /// something about the artist's hundred-cel project.
        var millisecondsPerCel: Double { celCount > 0 ? totalSeconds * 1000 / Double(celCount) : 0 }

        /// The per-cel walk's share of the whole save, 0...1. If this is not most of it, the
        /// re-encode is not the story and §1's ranking is wrong.
        var celWalkShare: Double { totalSeconds > 0 ? celWalkSeconds / totalSeconds : 0 }
    }

    /// Accumulates what one `writePackage` spent, across however many threads run it.
    ///
    /// A lock-guarded class rather than `inout` counters because the per-cel walk is spread over
    /// cores: several workers add to the same sums at once, and one uncontended lock acquisition per
    /// cel is nothing beside the PNG encode it is measuring.
    private final class WriteTally: @unchecked Sendable {
        private let lock = NSLock()
        private var encode = 0.0
        private var write = 0.0
        private var encoded = 0
        private var reused = 0
        private var bytes = 0
        private var threads = Set<ObjectIdentifier>()

        func record(encodeSeconds: Double, writeSeconds: Double,
                    pngsEncoded: Int, pngsReused: Int, bytesWritten: Int) {
            lock.lock()
            encode += encodeSeconds
            write += writeSeconds
            encoded += pngsEncoded
            reused += pngsReused
            bytes += bytesWritten
            threads.insert(ObjectIdentifier(Thread.current))
            lock.unlock()
        }

        var totals: (encode: Double, write: Double, encoded: Int, reused: Int, bytes: Int, threads: Int) {
            lock.lock()
            defer { lock.unlock() }
            return (encode, write, encoded, reused, bytes, threads.count)
        }
    }

    /// Where the most recent save's profile lives.
    ///
    /// A box rather than a plain static because this one is written from `saveQueue` — `lastLoadProfile`
    /// can be `@MainActor` since a load ends on the main actor and a save does not. Read by
    /// `PerfBaselineTests` and `ProjectSaveLogicTests`; nothing in the app reads it, and nothing
    /// branches on it.
    private final class SaveProfileBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: SaveProfile?
        var value: SaveProfile? {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
        }
    }
    private static let saveProfileBox = SaveProfileBox()
    static var lastSaveProfile: SaveProfile? { saveProfileBox.value }

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
    /// which it does not distinguish, matching the callers that only care that the attempt is over
    /// (the gallery re-lists projects from disk in a one-shot `onAppear`, so navigating there before
    /// the rename lands would show the project as missing or stale — `completion` is "the wait is
    /// over", not "it worked"). `onSaveFailed` is the channel that does distinguish: it runs first,
    /// also on the main actor, only when `writeAtomically`'s three formerly-silent failure returns
    /// fire (ARCHITECTURE_REVIEW.md finding 3). `ContentView` is the only caller that passes it, and
    /// raises the existing `CanvasNotice.Kind.saveFailed` banner from it.
    /// `intent` defaults to `.artist` because that is the direction it is safe to be wrong in. A new
    /// call site that forgets it gets the visible behaviour — a banner the artist can answer — rather
    /// than the quiet one, where the project file is left alone and the work goes to a version slot
    /// nobody was told about. The two real call sites in `ContentView` both pass it explicitly.
    ///
    /// The return value says what the save *did*, and `.ask` is the case worth reading: nothing was
    /// written and `completion` did **not** run, because the caller's completion is "now show the
    /// gallery" and the artist has not finished answering yet.
    @MainActor
    @discardableResult
    static func save(_ canvasManager: CanvasManager, to url: URL,
                     intent: SaveIntent = .artist,
                     onSaveFailed: (@MainActor () -> Void)? = nil,
                     completion: (@MainActor () -> Void)? = nil) -> SaveDecision {
        let decision = SaveDamageGate.decide(damage: canvasManager.loadDamage,
                                             answered: canvasManager.damagedSaveAnswered,
                                             intent: intent)
        guard decision != .ask else { return .ask }

        // The clock starts here rather than on `saveQueue`, because the question this instrument
        // exists to answer — "how long does leaving to the gallery take" — is about the wait
        // `returnToGallery` imposes, and the snapshot below is part of that wait *and* the only part
        // of it that is on the artist's own thread. See `SaveProfile`.
        let saveStarted = CFAbsoluteTimeGetCurrent()
        let snapshot = SaveSnapshot(canvasManager)
        let snapshotSeconds = CFAbsoluteTimeGetCurrent() - saveStarted

        // A save is usually triggered by the app being backgrounded (see ContentView's scenePhase
        // handler). While it ran on main, iOS's "finish what you were doing" window covered it; work
        // dispatched to a background queue has to ask for that time explicitly or the process can be
        // suspended mid-write. The staged-then-renamed design means a suspended save loses the new
        // package rather than damaging the old one, but losing the user's last edits is still worth
        // avoiding. `.invalid` (assertion refused) is handled rather than assumed away.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ProjectStore.save")
        // **The artist has this package open** — TODO (57) part 2. Registered here rather than in
        // `writeAtomically` so it is on the main actor and ordered against the artist's own actions,
        // and it is what stops the launch pass renaming a package out from under a save in flight.
        PackageRenameGate.noteOpen(url)

        saveQueue.async {
            let landed = writeAtomically(snapshot, to: url,
                            destination: decision == .writeAside ? .versionSlot : .liveProject,
                            startedAt: saveStarted, snapshotSeconds: snapshotSeconds)
            Task { @MainActor in
                if landed == nil {
                    onSaveFailed?()
                }
                // **Before `completion`, which is "now show the gallery"** — TODO (57) part 2. A save
                // that renamed the package to follow its title has left `canvasManager.projectURL`
                // naming a directory that no longer exists; the next save would then stage beside the
                // new name and swap into the *old* one, resurrecting an orphan. `.versionSlot` is
                // excluded because its landing is a backup slot, not the project.
                //
                // **Compared against the URL this call was given, not the one it wrote to**, which is
                // what makes this the repair as well as the update: a save whose target
                // `writeAtomically` had to forward off a stale address lands somewhere the caller
                // never named, and this is where the caller is told.
                if let landed, landed != url, decision != .writeAside {
                    canvasManager.projectURL = landed
                }
                completion?()
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                }
            }
        }
        return decision
    }

    /// Where a save lands.
    ///
    /// **The whole difference is what else the write is allowed to touch**, which is why it is one
    /// enum rather than two entry points: a version slot is written by exactly the same stage,
    /// validate, rename sequence, and only the three steps that reach *outside* the destination —
    /// stashing the live package, refreshing `latest`, and putting the stash back if the swap fails —
    /// are conditional on it. Duplicating the sequence to omit three lines would put the atomic-save
    /// guarantee in two places, and session 34's comment on `writeAtomically` is explicit that its
    /// step order must not be rearranged.
    private enum WriteDestination {
        /// The project package itself: the ordinary save.
        case liveProject
        /// A fresh slot in the project's version history, leaving the project package untouched. See
        /// `SaveDamageGate` for when and `ProjectBackupManager.unsavedChangesSlotURL` for where.
        case versionSlot
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
    ///
    /// Returns **the URL the package actually landed at**, or nil if it did not land. It used to
    /// return `Bool`; the three `nil`s below used to be bare `return`s — the save silently did
    /// nothing and `save`'s completion ran regardless, which is ARCHITECTURE_REVIEW.md finding 3.
    /// The URL is TODO (57) part 2: a save may now rename the package to follow its title, and
    /// `CanvasManager.projectURL` has to learn where it went in the same stroke (see `save`).
    @discardableResult
    private static func writeAtomically(_ snapshot: SaveSnapshot, to url: URL,
                                        destination: WriteDestination = .liveProject,
                                        startedAt saveStarted: CFAbsoluteTime,
                                        snapshotSeconds: Double) -> URL? {
        let fm = FileManager.default
        // **Where the package actually is, not where the caller last saw it** — TODO (57) part 2, and
        // it is the first line of the function because every other line below reads `url`.
        //
        // `ContentView.saveIfNeeded` reads `canvasManager.projectURL` on the main actor and hands it
        // here; the property is corrected from inside a save's own `Task { @MainActor }` completion,
        // which cannot have run for a save queued in the same turn. So two saves arrive carrying the
        // same pre-rename URL — a scene-phase save and `returnToGallery`'s, say — and MEASURED
        // 2026-09-09, before this line existed, the second one forked the project: `loadManifest`
        // found nothing at the vacated address, `titleChanged` came out false rather than true (`nil
        // == true`), the rename branch was skipped entirely, and `commitSwap` rebuilt a whole valid
        // package under the old name with the artist's *newer* edits in it — invisible beside the
        // one the gallery shows.
        //
        // Resolved **here, on `saveQueue`**, rather than where the save is issued: the queue is
        // serial, so this line runs after any earlier save's rename has finished. The same question
        // asked on the main actor would be asked before that rename and would answer the stale
        // address, which is why narrowing the window was never the fix.
        let url = PackageRenameGate.currentLocation(of: url, projectID: snapshot.projectID)
        // Minted here rather than by the caller so it is chosen on `saveQueue` — it lists a directory
        // to pick a free name, and the caller is the artist's own thread.
        let stagedTarget: URL
        switch destination {
        case .liveProject: stagedTarget = url
        case .versionSlot: stagedTarget = ProjectBackupManager.unsavedChangesSlotURL(projectURL: url,
                                                                                     projectID: snapshot.projectID)
        }
        // **Did the title change in *this* save?** — TODO (57) part 2, the narrow trigger, and it is
        // narrow on purpose. The owner's complaint is exactly "the folder does not change when the
        // project name is changed", so the event to catch is the change: the name in the package's
        // own on-disk manifest against the name in the snapshot. A first save has no on-disk manifest
        // and needs no rename (the name was just minted from the title by `createNewProjectURL`), and
        // a save that did not retitle anything renames nothing — which is also what keeps this out of
        // the forty-odd existing tests that save a manager titled "Untitled" to a URL called
        // `Damaged.paintproj` and then read that path back.
        //
        // The *broad* question — "is the stem an acceptable rendering of the title today?" — belongs
        // to the launch pass, which has to ask it because a project retitled under an older build has
        // no change event left to catch. See `ProjectPackageLayout.tidy` step 3.
        let titleChanged = destination == .liveProject
            && loadManifest(at: url).map { $0.name != snapshot.projectName } == true
        // Read here rather than inside the walk, for `decodeCels`' reason one direction over: the
        // walk may recruit its caller as a worker, so asking inside an iteration would sometimes
        // answer for a pool thread, and the question is about the caller.
        let startedOnMainThread = Thread.isMainThread
        let tally = WriteTally()

        // Stage the new package beside the live one — **beside**, meaning in the target's own
        // directory rather than at the top of `Projects/`, since TODO (36) let a project live in a
        // sub-folder. The swap below is a rename, and a rename is only cheap and atomic within one
        // directory; staging at the root and renaming into `Projects/Scene 3/` would still work on
        // one volume but stops being a guarantee the moment it is not.
        // A (57) rename never leaves the package's own parent directory, so staging beside `url` is
        // still staging beside wherever the swap will aim.
        let stageURL = stagedTarget.deletingLastPathComponent()
            .appendingPathComponent(".saving-\(UUID().uuidString)", isDirectory: true)
        try? fm.removeItem(at: stageURL)
        let packageStarted = CFAbsoluteTimeGetCurrent()
        let celWalkSeconds = writePackage(snapshot, to: stageURL, tally: tally)
        let packageEnded = CFAbsoluteTimeGetCurrent()

        // Published on every exit, including the three failure returns below: a save that bailed on a
        // failed validate still spent its encode, and a profile that only ever describes the happy
        // path would quietly under-report exactly the runs worth looking at.
        defer {
            let finished = CFAbsoluteTimeGetCurrent()
            let totals = tally.totals
            saveProfileBox.value = SaveProfile(
                layerCount: snapshot.layers.count,
                celCount: snapshot.layers.reduce(0) { $0 + $1.cels.count },
                snapshotSeconds: snapshotSeconds,
                encodeSeconds: totals.encode,
                writeSeconds: totals.write,
                celWalkSeconds: celWalkSeconds,
                packageSeconds: packageEnded - packageStarted,
                swapSeconds: finished - packageEnded,
                totalSeconds: finished - saveStarted,
                pngsEncoded: totals.encoded,
                pngsReused: totals.reused,
                bytesWritten: totals.bytes,
                encodedOnMainThread: startedOnMainThread,
                encodeThreads: totals.threads)
        }

        // Only replace the live package once the staged one is provably complete (e.g. a PNG that
        // failed to encode must not clobber the last-known-good save). The broken stage is kept
        // in Trash for diagnosis.
        guard ProjectBackupManager.validateProject(at: stageURL) else {
            _ = ProjectBackupManager.moveToTrash(stageURL, tag: "failedsave")
            return nil
        }

        /// Stash the live package as an autosave restore point, then swap in the new one, returning
        /// where it landed. A version slot skips the stash: it is a name nothing occupies, and the
        /// live package — which is the damaged original the artist has not yet ruled on — is
        /// precisely what this write exists not to touch.
        func commitSwap(to target: URL) -> URL? {
            if destination == .liveProject {
                guard ProjectBackupManager.stashLiveProjectForSave(projectURL: url, projectID: snapshot.projectID) else {
                    try? fm.removeItem(at: stageURL)
                    return nil
                }
                // **The rename's own restore point, and it is not decoration** — TODO (57) part 2.
                // `reconciled` may aim this save at a name something already occupies — its own
                // prior landing spot, which `ProjectPackageName.isFree` allows deliberately — and
                // this line makes that occupant a restore point instead of something the `moveItem`
                // below destroys.
                if target != url, fm.fileExists(atPath: target.path) {
                    _ = ProjectBackupManager.stashLiveProjectForSave(projectURL: target,
                                                                     projectID: snapshot.projectID)
                }
                // **`origin.name` before the move**, which is `ProjectPackageLayout.tidy` step 5's
                // rule and now the save's too. The marker is `backupDirectory(forProjectAt:)`'s
                // fallback for a package whose manifest has gone unreadable — the one case where the
                // primary manifest-id lookup cannot answer — and a crash between the two lines is
                // better spent naming a package about to appear than one already gone.
                // A review reported the save's rename as leaving the marker stale until the project's
                // next save, and that is **refuted**: `refreshLatestSnapshot` rewrites it a few
                // lines below, against the URL the package landed at. MEASURED 2026-09-09 by
                // deleting each write in turn — with only this one, the suite is green; with only
                // that one, the suite is green; so **no test in this repo can catch a mutation of
                // this line**, and it stays anyway, because the end state is not what it is for. It
                // is for the kill *inside* the rename, where the two orders differ and nothing on
                // disk records which happened. The end state the pair produces is pinned by
                // `ProjectPackageRenameLogicTests`' backup-of-a-renamed-project test, driven all the
                // way through `listBackups` with an unreadable manifest rather than read off the
                // marker's own bytes.
                if target != url {
                    ProjectBackupManager.noteProjectRenamed(projectID: snapshot.projectID,
                                                            to: target.lastPathComponent)
                }
            }
            do {
                try fm.moveItem(at: stageURL, to: target)
            } catch {
                // Swap failed: put the stashed package back so the project is never missing. Nothing
                // was stashed for a version slot, and the project package was never moved out of the
                // way, so there is nothing to undo — restoring here would move a *backup* over a live
                // project that is perfectly fine.
                if destination == .liveProject {
                    // The marker first, and it is load-bearing rather than tidy: `url` no longer
                    // holds a package, so `backupDirectory(forProjectAt:)` cannot read a manifest id
                    // there and falls through to exactly this string. Pointed at a name that never
                    // appeared, the restore below would find no backup folder at all.
                    if target != url {
                        ProjectBackupManager.noteProjectRenamed(projectID: snapshot.projectID,
                                                                to: url.lastPathComponent)
                    }
                    _ = ProjectBackupManager.restoreNewestValidBackup(forProjectAt: url, trashTag: "corrupt")
                }
                try? fm.removeItem(at: stageURL)
                return nil
            }
            return target
        }

        let landed: URL?
        switch destination {
        case .liveProject:
            // **Under `PackageRenameGate`, and the reconcile is re-run here rather than reused** —
            // TODO (57) part 2. The answer computed before `writePackage` is potentially seconds old
            // by now (the encode is cel-count-scaled), and in that time another save can have taken
            // the name this one was aiming at. The gate is the part that matters: it is the shared
            // mutual-exclusion point between this rename and the launch pass's, and it is what makes
            // the registry follow the package to its new name in the same critical section as the
            // `moveItem`. See that type for the two-package fork neither check alone prevents.
            landed = PackageRenameGate.renamingOpenPackage(from: url, projectID: snapshot.projectID) {
                guard titleChanged,
                      let renamed = ProjectPackageName.reconciled(url, title: snapshot.projectName,
                                                                  projectID: snapshot.projectID) else {
                    return commitSwap(to: url)
                }
                return commitSwap(to: renamed)
            }
        case .versionSlot:
            // No gate and no rename: a version slot leaves the live package exactly where it is, so
            // there is nothing here for the launch pass to race with and nothing for the registry to
            // follow.
            landed = commitSwap(to: stagedTarget)
        }
        guard let landed else { return nil }

        // Restore points: `latest` = exact copy of this save; autos rotated by count. `latest` means
        // "the last state the project file was actually in", so a version slot must not refresh it —
        // the project file did not change. **`landed`, not `url`**: after a rename the project file
        // is the one that just appeared under the new name.
        if destination == .liveProject {
            ProjectBackupManager.refreshLatestSnapshot(projectURL: landed, projectID: snapshot.projectID)
        }
        ProjectBackupManager.pruneBackups(forProjectID: snapshot.projectID)
        return landed
    }

    /// Writes the complete project package at `url` (used by `writeAtomically` to stage the package
    /// before the atomic swap). Runs on `saveQueue`, entirely from the snapshot — this is where the
    /// PNG and JSON encoding that used to block the main thread actually happens.
    ///
    /// Returns the wall clock of the per-cel walk alone, which is the term PERFORMANCE.md §1 claims
    /// the whole gallery wait is made of; `tally` collects what that walk spent inside itself.
    @discardableResult
    private static func writePackage(_ snapshot: SaveSnapshot, to url: URL,
                                     tally: WriteTally = WriteTally()) -> Double {
        let fm = FileManager.default
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        // **Exactly the content directories this document needs, created once, before the fan-out** —
        // TODO (57). Before, so no worker ever races another to `createDirectory`; exactly, so a
        // pure-vector document (the owner's own) stops shipping an empty `images/` folder beside its
        // `drawings/`, which is the next question they would have asked. The conditions below mirror
        // `writeCel`'s own, one for one — a directory that is not created is a file that silently
        // does not get written.
        var roles: Set<ProjectPackageLayout.Role> = []
        for layer in snapshot.layers {
            for cel in layer.cels {
                if cel.rasterImage != nil { roles.insert(.raster) }
                if cel.fillImage != nil { roles.insert(.fill) }
                if cel.bakedImage != nil { roles.insert(.baked) }
                if cel.interpolation != nil { roles.insert(.interpolation) }
                if !cel.transformTracks.isEmpty || !cel.pendingPoseBaselines.isEmpty { roles.insert(.animation) }
                if let vector = cel.vector, !vector.isEmpty {
                    roles.insert(.drawing)
                    if !vector.images.isEmpty { roles.insert(.placedImage) }
                    if !vector.videos.isEmpty { roles.insert(.video) }
                }
            }
        }
        ProjectPackageLayout.createDirectories(roles, in: url)

        var layerManifests: [LayerManifest] = []

        // **The per-cel walk, spread over cores — the save's mirror of item 9(b).** MEASURED
        // 2026-08-20 before this landed: 15.2 ms a cel at 2048x1024, of which 95.6% was `pngData()`,
        // flat from 8 cels to 32 — so the whole gallery-exit wait is one embarrassingly parallel
        // encode loop, and the file I/O it was assumed to be bounded by is 2% of it.
        //
        // **Flattened across the whole tree rather than run per layer**, for `decodeCels`' reason
        // exactly: an animator's document is a handful of layers with many cels each, and a
        // per-layer fan-out leaves most of the machine idle while the longest layer finishes.
        //
        // **Order is reconstructed from the job list, not from completion order.** `parallelMap`
        // returns results in index order and the regrouping walks that array once appending in
        // order, so each layer's cels are written to the manifest exactly as the snapshot listed
        // them — which is the order `activeCelIndex` scans on the way back in, and the one property
        // here that would be quiet if it were wrong.
        //
        // **Nothing about *what* gets written changes**, which is what makes this the safe half of
        // PERFORMANCE.md §5's entry on this path: the same bytes go to the same files, and the
        // memo that would skip an unchanged cel entirely is a separate change with a separate risk.
        let celWalkStarted = CFAbsoluteTimeGetCurrent()
        let jobs: [(layerIndex: Int, cel: SaveSnapshot.CelContent)] =
            snapshot.layers.enumerated().flatMap { layerIndex, layer in
                layer.cels.map { (layerIndex, $0) }
            }
        let written = PixelOps.parallelMap(jobs.count) { index in
            writeCel(jobs[index].cel, to: url, canvasSize: snapshot.canvasSize, tally: tally)
        }
        var celManifestsByLayer = [[CelManifest]](repeating: [], count: snapshot.layers.count)
        for (index, celManifest) in written.enumerated() {
            celManifestsByLayer[jobs[index].layerIndex].append(celManifest)
        }
        let celWalkSeconds = CFAbsoluteTimeGetCurrent() - celWalkStarted

        for (layerIndex, layer) in snapshot.layers.enumerated() {
            let celManifests = celManifestsByLayer[layerIndex]

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
                // Empty maps to absent, which is the whole of §3.5's field-presence versioning here:
                // a document nobody has animated writes no `effectTracks` key and stays byte-for-byte
                // the manifest it was. See `LayerManifest.effectTracks`.
                effectTracks: layer.effectTracks.isEmpty ? nil : layer.effectTracks,
                // Same line for the same reason, on TODO (21)'s channel kind.
                channelTracks: layer.channelTracks.isEmpty ? nil : layer.channelTracks,
                channelBaselines: layer.channelBaselines.isEmpty ? nil : layer.channelBaselines,
                // Same line for the same reason, on §2.26's two fields.
                keyframeMarks: layer.keyframeMarks.isEmpty ? nil : layer.keyframeMarks,
                pendingBaselines: layer.pendingBaselines.isEmpty ? nil : layer.pendingBaselines,
                fill: layer.fill,
                fillReferenceOverride: layer.fillReferenceOverride,
                // §4.4's transformation layer. Optional in the model as well, so this needs no
                // empty-to-absent mapping — `effect` one field up is the same shape.
                transform: layer.transform,
                // TRANSFORM_LAYER.md §5's scalar rows: zero-to-absent for the speed, for the
                // field-presence rule above; the share is optional on both sides.
                rotateSpeed: layer.rotateSpeed == 0 ? nil : layer.rotateSpeed,
                parallaxShare: layer.parallaxShare,
                shakeX: layer.shakeX == 0 ? nil : layer.shakeX,
                shakeY: layer.shakeY == 0 ? nil : layer.shakeY,
                shakeRotation: layer.shakeRotation == 0 ? nil : layer.shakeRotation,
                cels: celManifests
            ))
        }

        // **The document's brush table, and the sweep that keeps it honest** — BRUSH.md §5.4.
        //
        // Collected from this snapshot's own content, so what gets written is exactly the brushes the
        // ink references and an entry nothing references is never offered a slot. That is the whole of
        // §5.4's *"a sweep on save drops entries no stroke references"*: there is no stored numbering
        // to renumber and no second pass to half-apply, because a stroke's number is a `BrushRef` into
        // the process pool and this table is the list of the ones this document redeems.
        //
        // Both element sources are walked. A cel's display list is the obvious one; a derived cel's
        // `InterpolationRecipe` carries `LocalEdit` strokes that are reachable from nothing else, and
        // a table missing those would fail that recipe's decode on the next load.
        var collector = BrushTable.Collector()
        for layer in snapshot.layers {
            for cel in layer.cels {
                if let vector = cel.vector { collector.add(elements: vector.elements) }
                collector.add(recipe: cel.interpolation)
            }
        }
        let brushTable = collector.table
        var brushTableFileName: String?
        if !brushTable.isEmpty {
            // Beside `brushes/` in the package root rather than inside `manifest.json`: the manifest is
            // decoded in full for every gallery tile, and §2.10 makes this the least bounded thing that
            // could live there — it grows with every brush the artist edits and then draws with. The
            // same argument `CelManifest` already makes about per-cel vector data. §13's first open
            // item, settled.
            //
            // Not `try?`, for `writeCel`'s reason wearing a worse consequence: a table that failed to
            // encode and said nothing would leave `brushTableFileName` nil, the package would validate,
            // and **every stroke in the document** would fail to resolve on the next load. Nothing here
            // throws today; the point is that if something starts to, it says so.
            do {
                let name = "brushtable.json"
                try JSONEncoder().encode(brushTable).write(to: url.appendingPathComponent(name))
                brushTableFileName = name
            } catch {
                log.error("""
                    The brush table for \(snapshot.projectName, privacy: .public) could not be written, \
                    so this package's strokes name brushes nothing can resolve: \
                    \(String(describing: error), privacy: .public)
                    """)
            }
        }

        // Persist the user's actual brush choice + imported custom brushes (Worker B's brush engine
        // owns these on CanvasManager) so they survive a save/reload, and copy the stamp textures
        // both the drawing and the palette need into the project package for self-containment.
        copyCustomBrushTexturesIntoProject(
            importedTextureFileNames(table: brushTable,
                                     palette: [snapshot.selectedBrush] + snapshot.customBrushes),
            projectURL: url)

        let manifest = ProjectManifest(
            id: snapshot.projectID,
            name: snapshot.projectName,
            canvasWidth: Double(snapshot.canvasSize.width),
            canvasHeight: Double(snapshot.canvasSize.height),
            canvasPadding: snapshot.canvasPadding,
            fps: snapshot.fps,
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
            guideStrokes: snapshot.guideStrokes,
            animationGroups: snapshot.animationGroups,
            brushTableFileName: brushTableFileName
        )
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: url.appendingPathComponent("manifest.json"))
        }

        if let thumbnailImage = snapshot.thumbnail, let data = thumbnailImage.pngData() {
            try? data.write(to: url.appendingPathComponent("thumbnail.png"))
        }

        // **The last word on lazy directories, and the reason the role scan above is not enough** —
        // TODO (57)'s sweep. That scan reads the snapshot and says which directories the document
        // *should* fill; every one of the writes it authorises can still fail on its own. A PNG that
        // will not encode, a JSON that throws, a clip whose `assetURL` has gone — each leaves the
        // directory created and nothing in it, and the artist is then looking at an empty `videos/`
        // in a package that was saved without a word of complaint.
        //
        // Here, at the end, rather than beside each failure: the stage is a directory nothing else
        // can see (`writeAtomically` swaps it into place afterwards by rename), so this runs with no
        // reader and no other writer, which is the cheapest correctness argument available anywhere
        // on this path. `rmdir(2)` refuses a non-empty directory in the kernel, so it cannot reach a
        // file that was written.
        ProjectPackageLayout.pruneEmptyContentDirectories(in: url)

        return celWalkSeconds
    }

    /// One cel's PNGs and JSON, encoded and written, with what each half cost recorded in `tally`.
    ///
    /// **Extracted from `writePackage`'s loop so the per-cel walk has a name and a boundary**, which
    /// is what lets `SaveProfile` say how much of a save is this and how much is everything else.
    /// The body is the old loop verbatim; the only additions are the two clocks.
    ///
    /// It reads this cel's own snapshot content and writes only files named after this cel's id, so
    /// two cels share nothing — the same property that makes the load's `decodeCel` safe to fan out,
    /// and the reason `writePackage` now runs this over cores.
    ///
    /// **What a wrong answer here would look like, since that is what ranks the risk.** Every path
    /// out of this function names its file after `cel.id`, which is a UUID, so two workers cannot
    /// target the same path; `UIImage` is immutable and each worker holds a different one; the
    /// `JSONEncoder` is per-call. The failure mode a fan-out could introduce is a *manifest* whose
    /// cels came back in completion order, and `writePackage` reconstructs that order from the job
    /// list rather than from completion — see its comment.
    private static func writeCel(_ cel: SaveSnapshot.CelContent, to packageURL: URL,
                                 canvasSize: CGSize, tally: WriteTally) -> CelManifest {
        var encodeSeconds = 0.0
        var writeSeconds = 0.0
        var encoded = 0
        var bytes = 0

        func png(_ image: UIImage) -> Data? {
            let started = CFAbsoluteTimeGetCurrent()
            let data = image.pngData()
            encodeSeconds += CFAbsoluteTimeGetCurrent() - started
            encoded += 1
            return data
        }
        // TODO item (8): the centre of *this* canvas is what stored sample coordinates are measured
        // from, and it is the one thing the encoder needs that the payload cannot work out for
        // itself. `PackedSampleRun` writes the origin it was given into the file, so a decoder needs
        // no matching context and a forgotten origin here costs addressable range, never a wrong
        // coordinate — `SampleCodingLogicTests` pins that by saving near the edge of a canvas too
        // wide to encode about the origin.
        let sampleOrigin = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        func json<T: Encodable>(_ value: T) -> Data? {
            let started = CFAbsoluteTimeGetCurrent()
            let encoder = JSONEncoder()
            encoder.userInfo[.sampleQuantisationOrigin] = sampleOrigin
            // Not `try?`. An encode that throws used to leave `vectorFileName` nil and save the cel
            // **empty**, which is the same silent-loss shape `VectorCanvasData`'s per-element decode
            // was built to end, arriving from the other direction. Nothing in the tree throws here
            // today; the point is that if something starts to, it says so.
            do {
                let data = try encoder.encode(value)
                encodeSeconds += CFAbsoluteTimeGetCurrent() - started
                return data
            } catch {
                encodeSeconds += CFAbsoluteTimeGetCurrent() - started
                log.error("""
                    Encoding \(String(describing: T.self), privacy: .public) for cel \
                    \(cel.id.uuidString, privacy: .public) failed, so that content is not written: \
                    \(String(describing: error), privacy: .public)
                    """)
                return nil
            }
        }
        /// Writes one file at the address its **role** gives it — TODO (57). `name` is what the
        /// manifest records: bare for a PNG, package-relative (`drawings/…`) for the three JSON
        /// sidecars, and `ProjectPackageLayout.writeURL` reads the difference off the name.
        func write(_ data: Data, _ name: String, _ role: ProjectPackageLayout.Role) {
            let started = CFAbsoluteTimeGetCurrent()
            try? data.write(to: ProjectPackageLayout.writeURL(named: name, role: role, in: packageURL))
            writeSeconds += CFAbsoluteTimeGetCurrent() - started
            bytes += data.count
        }
        /// Copies one imported asset into the staged package — VIDEO.md §6's *"the source file is
        /// copied into the project whole"*, which is why it is a file copy rather than a re-encode:
        /// a video-only asset would discard the audio track for good.
        ///
        /// **It reads the element's `assetURL`, and that is safe only because of where this runs in
        /// `writeAtomically`'s step order.** After a load, `assetURL` names a file inside the *live*
        /// package; the save then stages a whole new package and swaps by rename, so the live one is
        /// moved aside. This copy happens during the stage, before that move — so every re-save of a
        /// video copies the live package's own asset into the new one, and the path stays valid
        /// because the swap puts the new package at the same URL. Reorder those steps and a second
        /// save writes a package with no asset in it, which the next load would report as damage.
        /// `VideoElementLogicTests.testASecondSaveKeepsTheAssetEvenWithTheImportSourceGone` is what
        /// notices.
        ///
        /// `copyItem` rather than `Data(contentsOf:)` + `write`: a clip is unbounded in size and has
        /// no business passing through memory. Its bytes are not added to `bytes`, which counts what
        /// this save *encoded*.
        func copyAsset(named name: String, from source: URL) {
            let fm = FileManager.default
            // `videos/` since TODO (57)'s sweep — an `.mp4` inside a folder called `images` is the
            // owner's own complaint one door over. **No migration moves an existing clip and none is
            // needed**: a clip's name lives inside the vector payload rather than the manifest, so
            // moving one would mean parsing every payload — and it does not have to, because this
            // copy reads the runtime `assetURL` the reader resolved, which already knows both
            // addresses. An old package keeps its clip in `images/` and opens forever.
            let destination = ProjectPackageLayout.writeURL(named: name, role: .video, in: packageURL)
            guard !fm.fileExists(atPath: destination.path) else { return }
            let started = CFAbsoluteTimeGetCurrent()
            defer { writeSeconds += CFAbsoluteTimeGetCurrent() - started }
            do {
                try fm.copyItem(at: source, to: destination)
            } catch {
                log.error("""
                    Copying asset \(name, privacy: .public) for cel \
                    \(cel.id.uuidString, privacy: .public) from \(source.path, privacy: .public) \
                    failed, so the staged package will not contain it: \
                    \(String(describing: error), privacy: .public)
                    """)
            }
        }

        // The raster tier. A cel whose texture never had a bitmap gets no PNG and says so in the
        // manifest — `fileName` is still the name the file *would* have, so the cel's identity on
        // disk does not change if it is drawn into and saved again. See `CelManifest.rasterOmitted`
        // for why the name stays non-optional, and `ProjectBackupManager.validateProject` for the
        // half of this change without which every such save would be rejected and trashed.
        // **The four PNG names are untouched by (57)**, deliberately. The one family that *cannot* be
        // renamed is the placed images, whose names live inside the payload — so renaming the others
        // would buy a different inconsistency while multiplying the migration from at most three
        // renames per cel to every file in the package, and a UUID filename reads no better either
        // way. Note `-fill.png` uses a dash where the rest use an underscore; that predates this and
        // is why nothing here pattern-matches a cel's files by a single separator convention.
        let fileName = "\(cel.id.uuidString)_raster.png"
        var rasterOmitted: Bool? = nil
        if let rasterImage = cel.rasterImage {
            if let data = png(rasterImage) { write(data, fileName, .raster) }
        } else {
            rasterOmitted = true
        }

        var fillFileName: String?
        if let fillImage = cel.fillImage, let fillData = png(fillImage) {
            let name = "\(cel.id.uuidString)-fill.png"
            write(fillData, name, .fill)
            fillFileName = name
        }
        var bakedFileName: String?
        if let baked = cel.bakedImage, let bakedData = png(baked) {
            let name = "\(cel.id.uuidString)_baked.png"
            write(bakedData, name, .baked)
            bakedFileName = name
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
                if let data = png(element.image) {
                    write(data, name, .placedImage)
                    imageFileNames[element.id] = name
                }
            }
            // A video's bytes are copied rather than encoded — see `copyAsset`. Its name is the
            // element's own field rather than one minted here, because a video element cannot exist
            // without the file it names (`VectorVideoElement.assetFileName`).
            for element in vector.videos {
                copyAsset(named: element.assetFileName, from: element.assetURL)
            }
            let payload = VectorCanvasData(from: vector, imageFileNames: imageFileNames)
            if let data = json(payload) {
                // `drawings/<celID>.json` since TODO (57) — recorded in the manifest as the
                // package-relative path it is, which is the whole of the format version: a bare name
                // in this field means a package written before (57), and the reader resolves either.
                let name = ProjectPackageLayout.recordedName(for: .drawing, cel: cel.id)
                write(data, name, .drawing)
                vectorFileName = name
            }
        }

        // The interpolation recipe, when this cel is a derived one. Its own JSON file for the
        // same reason the vector payload has one: it is unbounded in size (lattices) and the
        // gallery reads every manifest in full.
        var interpolationFileName: String?
        if let recipe = cel.interpolation, let data = json(recipe) {
            let name = ProjectPackageLayout.recordedName(for: .interpolation, cel: cel.id)
            write(data, name, .interpolation)
            interpolationFileName = name
        }

        // The pose channels, when this cel has any — KEYFRAMES.md §3.5, and its own JSON file for
        // the two reasons above: unbounded size, and a manifest the gallery reads in full.
        // §2.27's held baseline rides in the same file, because it is the state *between* two
        // keyframes and that gap can span exactly this save.
        var animationFileName: String?
        if !cel.transformTracks.isEmpty || !cel.pendingPoseBaselines.isEmpty,
           let data = json(CelAnimationData(tracks: cel.transformTracks,
                                            baselines: cel.pendingPoseBaselines)) {
            let name = ProjectPackageLayout.recordedName(for: .animation, cel: cel.id)
            write(data, name, .animation)
            animationFileName = name
        }

        tally.record(encodeSeconds: encodeSeconds, writeSeconds: writeSeconds,
                     pngsEncoded: encoded, pngsReused: 0, bytesWritten: bytes)

        return CelManifest(id: cel.id, startFrame: cel.startFrame, frameCount: cel.frameCount,
                           rasterFileName: fileName, rasterOmitted: rasterOmitted,
                           fillImageFileName: fillFileName,
                           bakedImageFileName: bakedFileName,
                           vectorFileName: vectorFileName,
                           interpolationFileName: interpolationFileName,
                           animationFileName: animationFileName)
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
    /// restorable.
    ///
    /// **The save-semantics question this comment used to leave open has been answered.** The owner
    /// ruled on 2026-08-21: prompt once, then remember. The log lines below still say everything they
    /// said before — they are the diagnostic record, and they cover the benign unknown-`kind` case the
    /// artist is deliberately never asked about — while the *artist-facing* half now travels as
    /// `ProjectLoadDamage` to `SaveDamageGate`, which is where the "should this overwrite" decision
    /// lives. Nothing here decides anything; that was the right half of the old reasoning and it
    /// stands.
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
        /// Whether the per-cel decode fan-out started on the main thread. False is what
        /// `loadInBackground` is *for*, and true is what `load(from:)` promises its synchronous
        /// callers — so a test can assert the difference instead of trusting a doc comment. Item
        /// 9(b) is the kind of change that would go on passing every functional test if it silently
        /// stopped happening; this is the flag that would not.
        var decodedOnMainThread: Bool

        /// Milliseconds per cel — the figure that scales to a document of another size, and the one
        /// worth quoting.
        var millisecondsPerCel: Double { celCount > 0 ? totalSeconds * 1000 / Double(celCount) : 0 }

        /// The thumbnail walk's share of the whole open, 0...1.
        var thumbnailShare: Double { totalSeconds > 0 ? thumbnailSeconds / totalSeconds : 0 }
    }

    /// The profile of the most recent `load(from:)`, or nil if none has run. Read by
    /// `PerfBaselineTests`; nothing in the app reads it, and nothing branches on it.
    @MainActor private(set) static var lastLoadProfile: LoadProfile?

    /// Opens the package at `url`, blocking the caller.
    ///
    /// **The decode fan-out inside it is parallel as of item 9(b)** — see `decodeCels` — but this
    /// entry point still runs it on the calling thread, because `concurrentPerform` recruits its
    /// caller as a worker rather than releasing it. That is right for the twenty-odd tests and the
    /// one-shot paths that call this and then immediately read the result. The gallery wants
    /// `loadInBackground(from:)` instead, which is the same load with the fan-out on a queue of its
    /// own so the main thread is free to draw the spinner it was given on 2026-08-20.
    @MainActor
    static func load(from url: URL) -> CanvasManager? {
        let loadStarted = CFAbsoluteTimeGetCurrent()
        // TODO (57) part 2: the artist is opening this package, so the launch rename pass must
        // leave its directory name alone for the rest of this process. Registered before the
        // manifest read, which is the earliest this call knows which URL it is about to work on.
        PackageRenameGate.noteOpen(url)
        guard let manifest = loadManifest(at: url) else { return nil }
        let canvasSize = CGSize(width: manifest.canvasWidth, height: manifest.canvasHeight)
        let decoded = decodeCels(manifest: manifest, projectURL: url, canvasSize: canvasSize)
        return assemble(manifest: manifest, decoded: decoded, url: url, startedAt: loadStarted)
    }

    /// The same open with the per-cel decode on `loadQueue` instead of on the main thread — the
    /// gallery's path, and item 9(b).
    ///
    /// **What actually moves, and what deliberately does not.** The decode is the half that touches
    /// nothing shared: a `CelManifest` in, a `Cel` out, per cel, reading files this project owns and
    /// building objects nobody else has a reference to yet. That is now off main *and* spread over
    /// cores. Everything after it — the `CanvasManager`, its `@Published` layers, the thumbnails —
    /// stays on the main actor, because that state is what SwiftUI observes and moving it would be a
    /// change to the app's isolation model rather than to a load.
    ///
    /// **A wrong answer here is loud, which is the property that made it worth doing.** If a decode
    /// were not in fact independent, the failure is a cel with the wrong pixels or none — a blank or
    /// scrambled drawing the artist sees the instant the project opens — not a subtly slower app. The
    /// assembly order is preserved explicitly (see `decodeCels`) rather than left to completion order,
    /// so "the layers came back shuffled" is not among the ways it can go wrong.
    ///
    /// `loadManifest` stays on the calling side: it is one small JSON read, and hopping a queue for it
    /// would cost more than it saves.
    static func loadInBackground(from url: URL) async -> CanvasManager? {
        let loadStarted = CFAbsoluteTimeGetCurrent()
        // TODO (57) part 2: the artist is opening this package, so the launch rename pass must
        // leave its directory name alone for the rest of this process. Registered before the
        // manifest read, which is the earliest this call knows which URL it is about to work on.
        PackageRenameGate.noteOpen(url)
        guard let manifest = loadManifest(at: url) else { return nil }
        let canvasSize = CGSize(width: manifest.canvasWidth, height: manifest.canvasHeight)
        let decoded: Transfer<DecodedCels> = await withCheckedContinuation { continuation in
            loadQueue.async {
                continuation.resume(returning: Transfer(decodeCels(manifest: manifest, projectURL: url,
                                                                   canvasSize: canvasSize)))
            }
        }
        return await MainActor.run {
            let manager = assemble(manifest: manifest, decoded: decoded.value, url: url,
                                   startedAt: loadStarted, generatingThumbnails: false)
            // Item 9(c). The thumbnails are a third of what an open used to cost (MEASURED: 96.3 ms
            // of 303.6 ms) and none of it is needed to show the artwork, so the open no longer waits
            // on it — see `CanvasManager.backfillMissingThumbnails`, which also explains why the
            // placeholder is `nil` and why a stale thumbnail is the failure this is arranged around.
            manager.startThumbnailBackfill()
            return manager
        }
    }

    /// Hands one value from the queue that made it to the actor that will own it.
    ///
    /// `Cel` holds `RasterLayerTexture` and `UIImage`, neither of which is `Sendable`, and neither
    /// should be: they are mutable buffers whose thread-safety is their owners' business. What the
    /// compiler cannot see is that these particular ones are *newly built and unreferenced* — the
    /// decode is the only thing that has ever touched them, it has finished, and it keeps nothing. So
    /// this is a transfer of ownership rather than sharing, which is exactly what the annotation
    /// claims and exactly as much as it claims.
    private struct Transfer<Value>: @unchecked Sendable {
        let value: Value
        init(_ value: Value) { self.value = value }
    }

    /// Serialises nothing and owns nothing; it exists so `loadInBackground` has a named place to run
    /// that is not the main thread and not a global queue whose QoS is somebody else's. Concurrent
    /// rather than serial because `decodeCels` fans out with `concurrentPerform` on whatever thread it
    /// lands on, and a serial queue would be a needless funnel in front of that.
    private static let loadQueue = DispatchQueue(label: "com.paintapp.ProjectStore.load",
                                                 qos: .userInitiated, attributes: .concurrent)

    /// Every cel in the document, decoded in parallel and regrouped by layer in manifest order.
    ///
    /// **Flattened across the whole tree rather than run per layer**, which is the difference between
    /// parallelising and appearing to: an animator's document is often a handful of layers with many
    /// cels each, and a per-layer fan-out over six layers leaves most of the machine idle while the
    /// longest layer finishes. Flattened, the unit of work is one cel and the tree's shape stops
    /// mattering.
    ///
    /// **Order is reconstructed from the job list, not from completion order.** `parallelMap` returns
    /// results in index order, and the regrouping walks that array once appending in order, so each
    /// layer's cels come back exactly as the manifest listed them. Cel order is not cosmetic — it is
    /// what `activeCelIndex` scans and what `addCel` maintains with an explicit sort — so this is the
    /// one property of the change that would be quiet if it were wrong, and it is therefore the one
    /// that is arranged rather than assumed.
    private static func decodeCels(manifest: ProjectManifest, projectURL: URL, canvasSize: CGSize) -> DecodedCels {
        // Read before the fan-out, because `concurrentPerform` recruits its caller as one of the
        // workers: asking inside an iteration would sometimes answer for the caller's thread and
        // sometimes for a pool thread, and the question is about the caller.
        let startedOnMainThread = Thread.isMainThread
        // Read once, before the fan-out, and interned into this process's pool here rather than in
        // each worker: `BrushPool.intern` is lock-guarded, and a hundred cels racing to intern the
        // same five brushes would be a hundred acquires for one answer. What travels to the workers is
        // the finished `Remap`, which is immutable.
        let brushTable = loadBrushTable(manifest: manifest, projectURL: projectURL)
        let brushes = brushTable.resolvingIntoPool()
        let jobs: [(layerIndex: Int, cel: CelManifest, kind: LayerKind)] =
            manifest.layers.enumerated().flatMap { layerIndex, layerManifest in
                layerManifest.cels.map { (layerIndex, $0, layerManifest.kind) }
            }
        let decoded = PixelOps.parallelMap(jobs.count) { index in
            decodeCel(jobs[index].cel, layerKind: jobs[index].kind,
                      projectURL: projectURL, canvasSize: canvasSize, brushes: brushes)
        }
        var celsByLayer = [[Cel]](repeating: [], count: manifest.layers.count)
        // **The layer's name is attached here, not in `decodeCel`.** A cel does not know which layer
        // it belongs to — that is the manifest's structure, and this is the loop that already walks
        // it. Attaching it downstream would mean either passing a name into a function that has no
        // other use for one, or asking the assembled `CanvasManager` afterwards, by which point the
        // per-cel reports have already been merged and the association is gone.
        var damageByLayer = [ProjectLoadDamage.LayerDamage](repeating: .init(), count: manifest.layers.count)
        for (index, result) in decoded.enumerated() {
            let layerIndex = jobs[index].layerIndex
            celsByLayer[layerIndex].append(result.cel)
            damageByLayer[layerIndex].merge(result.damage)
        }
        var damage = ProjectLoadDamage()
        for (layerIndex, layerManifest) in manifest.layers.enumerated() {
            var layerDamage = damageByLayer[layerIndex]
            layerDamage.layerName = layerManifest.name
            damage.add(layerDamage)
        }
        return DecodedCels(celsByLayer: celsByLayer, damage: damage,
                           startedOnMainThread: startedOnMainThread, brushTable: brushTable)
    }

    /// What `decodeCels` hands back: the cels, what the decode could not read, and which thread asked
    /// for them.
    private struct DecodedCels {
        let celsByLayer: [[Cel]]
        /// The load's own account of what it dropped, per layer. Empty on every ordinary open. This is
        /// the value that used to die in `report(_:cel:file:)` as a log line — see `ProjectLoadDamage`
        /// for why it now travels.
        let damage: ProjectLoadDamage
        let startedOnMainThread: Bool
        /// This document's brush table, carried rather than re-read: `assemble` needs it to know which
        /// imported tip files the *drawing* depends on, and reading the file twice would be two answers
        /// to one question with a window between them.
        let brushTable: BrushTable
    }

    /// One decoded cel and what decoding it cost. A pair rather than two parallel returns because the
    /// fan-out below hands back one array, and the damage has to stay beside the cel it came from long
    /// enough for `decodeCels` to know which layer that was.
    private struct DecodedCel {
        let cel: Cel
        let damage: ProjectLoadDamage.LayerDamage
    }

    /// One cel's pixels and geometry, off any particular thread.
    ///
    /// Reads files and builds objects; touches no `CanvasManager`, no `@Published` state and nothing
    /// another iteration can see. That is what makes `decodeCels` safe to fan out, and it is why this
    /// is a free function over a manifest entry rather than a method on anything.
    /// This package's brush table — BRUSH.md §5.4. Empty when the manifest names none, which is a
    /// document with no vector ink.
    ///
    /// **A named-but-unreadable table is loud and costs the ink**, deliberately. Every stroke's brush
    /// is a number redeemed against this file; with the file gone there is no honest answer, and the
    /// alternative — substituting a default brush — would put the artist's line back in a brush they
    /// never chose with nothing saying so. `validateProject` refuses such a package before a normal
    /// open reaches here; this is the path for a load that skipped it.
    private static func loadBrushTable(manifest: ProjectManifest, projectURL: URL) -> BrushTable {
        guard let fileName = manifest.brushTableFileName else { return BrushTable() }
        guard let data = try? Data(contentsOf: projectURL.appendingPathComponent(fileName)),
              let table = try? JSONDecoder().decode(BrushTable.self, from: data) else {
            log.error("""
                Brush table \(fileName, privacy: .public) is missing or unreadable — every stroke in \
                this project names a brush that can no longer be resolved, and the cels load empty
                """)
            return BrushTable()
        }
        return table
    }

    private static func decodeCel(_ celManifest: CelManifest, layerKind: LayerKind,
                                  projectURL: URL, canvasSize: CGSize,
                                  brushes: BrushTable.Remap) -> DecodedCel {
        var damage = ProjectLoadDamage.LayerDamage()
        /// Where one of this cel's files actually is — TODO (57). Every read below goes through it,
        /// **including the four whose answer never changes**: one rule, asked one way, is what stops
        /// the writer, the reader and the validator drifting apart, which is the failure this item's
        /// survey named as the one that would silently trash every save.
        func fileURL(_ name: String, _ role: ProjectPackageLayout.Role) -> URL {
            ProjectPackageLayout.existingURL(named: name, role: role, cel: celManifest.id, in: projectURL)
        }
        /// Every decoder this cel uses, so none of them can be built without the brush table. The key
        /// is set even when the remap is empty, and that is the point: with it absent a stroke's stored
        /// number would be read as an address into *this process's* pool — right for an in-memory round
        /// trip and silently wrong for a file an earlier launch wrote. See `BrushPool.resolve`.
        func decoder() -> JSONDecoder {
            let decoder = JSONDecoder()
            decoder.userInfo[.brushTable] = brushes
            return decoder
        }
        // **Three ways to end up with a blank raster tier, and only one of them touches the disk.**
        //
        //  * `rasterOmitted` — this save knew the tier held nothing and wrote no PNG. Straight to
        //    `.empty`, which allocates no bitmap, without so much as a `stat`.
        //  * no file — a package written by an older build that omitted the key, or one whose PNG is
        //    genuinely gone. The existing `?? .empty` covers both; note that a *missing* PNG on a cel
        //    that claims one cannot reach a normal open, because `validateProject` refuses the
        //    package first (see `SaveDamageGate`).
        //  * a PNG that is there and is fully transparent — the legacy case, and the one worth
        //    healing. Every package written before this change carries one per undrawn cel, so
        //    loading the owner's own project materialises a 16 MiB `CGContext` at 2048² per cel and
        //    the save above would faithfully write it back out forever. The exact alpha scan in
        //    `releaseBitmapIfFullyTransparent()` drops it, and the cel becomes as cheap as one
        //    written by the new save — which is what lets a document that exists today heal itself
        //    on the next open-and-save rather than staying expensive for its whole life.
        //
        // The heal also puts `strokeCount` back to 0. `load` defaults it to 1 (a flattened bitmap
        // cannot recover a real count), and that 1 is the reason `Cel.isCertainlyBlank` answers
        // false for every cel of every reopened project today. A cel that has just been *proved*
        // pixel-blank should answer true: the onion skin (`OnionSkinSource`) then skips a
        // canvas-sized draw for it instead of compositing nothing, which is the correct behaviour
        // and was simply unreachable while every reloaded cel claimed a stroke.
        let raster: RasterLayerTexture
        if celManifest.rasterOmitted == true {
            raster = .empty(size: canvasSize)
        } else {
            let rasterURL = fileURL(celManifest.rasterFileName, .raster)
            if let image = UIImage(contentsOfFile: rasterURL.path) {
                let loaded = RasterLayerTexture.load(from: image, size: canvasSize)
                if loaded.releaseBitmapIfFullyTransparent() { loaded.setStrokeCount(0) }
                raster = loaded
            } else {
                raster = .empty(size: canvasSize)
            }
        }
        var fillImage: UIImage?
        if let fillFileName = celManifest.fillImageFileName {
            fillImage = UIImage(contentsOfFile: fileURL(fillFileName, .fill).path)
        }
        var bakedImage: UIImage?
        if let bakedFileName = celManifest.bakedImageFileName {
            bakedImage = UIImage(contentsOfFile: fileURL(bakedFileName, .baked).path)
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
            let vectorURL = fileURL(vectorFileName, .drawing)
            if let data = try? Data(contentsOf: vectorURL) {
                do {
                    let payload = try decoder().decode(VectorCanvasData.self, from: data)
                    // A placed image whose PNG is not in the package is dropped by
                    // `canvasSpaceElements(resolvingImages:)` and always has been. It is counted here
                    // rather than there because the resolver is the one place that knows a ref failed,
                    // and because `VectorCanvasData` is deliberately free of any notion of a project
                    // directory.
                    // **`validateProject` cannot catch this one**: image refs live inside the vector
                    // JSON, not in the manifest, so the integrity check never sees their file names.
                    let elements = payload.canvasSpaceElements(resolvingImages: { ref in
                        guard let image = UIImage(contentsOfFile: fileURL(ref.fileName, .placedImage).path) else {
                            damage.images += 1
                            log.error("""
                                Placed image \(ref.fileName, privacy: .public) for cel \
                                \(celManifest.id.uuidString, privacy: .public) is missing from the package — \
                                the image is dropped and the rest of the cel loaded
                                """)
                            return nil
                        }
                        return image
                    }, resolvingVideos: { ref in
                        // The placed image's story one door over: a video's payload is a file rather
                        // than a decoded picture, so what "resolves" is a path, and the existence
                        // check here is the whole of the missing-asset degradation. Existence rather
                        // than readability, deliberately — deciding a file is not a *video* needs a
                        // decoder, and VIDEO.md stage 3 owns that; a file that is present and
                        // unplayable is a stage-3 failure to report at the frame, not a stage-2
                        // reason to throw the element away at load.
                        let url = fileURL(ref.fileName, .video)
                        guard FileManager.default.fileExists(atPath: url.path) else {
                            damage.videos += 1
                            log.error("""
                                Video asset \(ref.fileName, privacy: .public) for cel \
                                \(celManifest.id.uuidString, privacy: .public) is missing from the package — \
                                the video is dropped and the rest of the cel loaded
                                """)
                            return nil
                        }
                        return url
                    })
                    // No `transform:`. The accessor above has already baked whatever the file carried
                    // into the geometry, so a cel loads in canvas coordinates and its own transform is
                    // identity — TODO item (12) stage 3.
                    vector = VectorCanvas(size: canvasSize, elements: elements)
                    report(payload.decodeReport, cel: celManifest.id, file: vectorFileName)
                    // Only the malformed half is damage. An unknown `kind` is a newer build's element
                    // in an older binary — see `ProjectLoadDamage` for why that is deliberately not
                    // counted, and where the thing that protects it actually lives.
                    var named = payload.decodeReport.malformedKinds.makeIterator()
                    for _ in 0..<payload.decodeReport.malformedCount {
                        damage.countMalformed(kind: named.next())
                    }
                } catch {
                    // The whole cel's vector content, gone: the file is present (so `validateProject`
                    // passed it) but is not a payload at all. The largest of the three losses, and the
                    // one the artist is most owed a sentence about.
                    damage.drawings += 1
                    log.error("""
                        Vector payload \(vectorFileName, privacy: .public) for cel \
                        \(celManifest.id.uuidString, privacy: .public) is not readable as a payload — \
                        the cel loads empty: \(String(describing: error), privacy: .public)
                        """)
                }
            } else {
                damage.drawings += 1
                log.error("""
                    Vector payload \(vectorFileName, privacy: .public) for cel \
                    \(celManifest.id.uuidString, privacy: .public) is missing or unreadable on disk — \
                    the cel loads empty
                    """)
            }
        }
        if vector == nil, layerKind == .vector {
            vector = .empty(size: canvasSize)
        }

        // The interpolation recipe. A cel whose recipe file is missing or unreadable loads as
        // an ordinary cel rather than failing the whole project: the recipe *derives*
        // content, so losing it costs the link, not the drawing.
        var interpolation: InterpolationRecipe?
        if let interpolationFileName = celManifest.interpolationFileName,
           let data = try? Data(contentsOf: fileURL(interpolationFileName, .interpolation)) {
            interpolation = try? decoder().decode(InterpolationRecipe.self, from: data)
        }

        // The pose channels. A cel whose animation file is missing or unreadable loads with its ink
        // where it stores it rather than failing the project — the same "the link, not the drawing"
        // rule the recipe above follows, and the reason both are sidecars.
        var animation = CelAnimationData()
        if let animationFileName = celManifest.animationFileName,
           let data = try? Data(contentsOf: fileURL(animationFileName, .animation)),
           let decoded = try? decoder().decode(CelAnimationData.self, from: data) {
            animation = decoded
        }

        return DecodedCel(
            cel: Cel(id: celManifest.id, startFrame: celManifest.startFrame, frameCount: celManifest.frameCount,
                     raster: raster, fillImage: fillImage, bakedImage: bakedImage, vector: vector,
                     interpolation: interpolation,
                     transformTracks: animation.tracks,
                     pendingPoseBaselines: animation.baselines),
            damage: damage)
    }

    /// The main-actor half: everything that touches `@Published` state, given cels somebody else
    /// already decoded.
    ///
    /// **`generatingThumbnails` is the one place the two entry points genuinely differ in what they
    /// hand back, so it is a parameter rather than a hidden branch.** `load(from:)` returns a
    /// fully-formed manager because its callers read it on the next line — twenty-odd tests, and every
    /// path that reloads a package to check it. `loadInBackground` returns one whose cel thumbnails
    /// are nil and arriving, because the only caller that path has is a gallery tap, where a third of
    /// the wait is worth more than a timeline that is already populated on the first frame.
    @MainActor
    private static func assemble(manifest: ProjectManifest, decoded: DecodedCels,
                                 url: URL, startedAt loadStarted: CFAbsoluteTime,
                                 generatingThumbnails: Bool = true) -> CanvasManager {
        let celsByLayer = decoded.celsByLayer
        let manager = CanvasManager()
        manager.projectID = manifest.id
        manager.projectName = manifest.name
        manager.projectURL = url
        manager.canvasSize = CGSize(width: manifest.canvasWidth, height: manifest.canvasHeight)
        // No resize on load: the buffers were saved at the full padded canvasSize; padding only drives
        // the paper inset that reveals the grey margin.
        manager.canvasPadding = CGFloat(manifest.canvasPadding)
        manager.fps = manifest.fps
        manager.canvasBackgroundColor = manifest.backgroundColor.color
        manager.isCanvasBackgroundVisible = manifest.isBackgroundVisible

        // Restore this project's own custom-brush texture copies into the shared library if a
        // referenced file is missing there (project moved to another device, or the global entry
        // was deleted) — see copyCustomBrushTexturesIntoProject's doc comment for the save side.
        restoreCustomBrushTexturesFromProject(
            importedTextureFileNames(table: decoded.brushTable,
                                     palette: [manifest.selectedBrush] + manifest.customBrushes),
            projectURL: url)
        manager.customBrushes = manifest.customBrushes
        // BRUSH.md §8.1: the library is app-level and the manifest's list is this *document's*.
        // A project made on another device carries brushes this library has never seen, and the two
        // lines above make them drawable; this is what makes them pickable.
        manager.adoptRestoredBrushesIntoLibrary()
        manager.selectBrush(manifest.selectedBrush)
        // Assigned directly rather than through a `select…` helper: unlike a brush, the vector-eraser
        // mode carries no size/opacity to re-baseline, so there is nothing for such a helper to do.
        manager.vectorEraserMode = manifest.vectorEraserMode
        // Document-level interpolation state. Both default to empty for every project that predates
        // the feature or simply never used it.
        manager.motionGroups = manifest.motionGroups
        manager.animationGroups = manifest.animationGroups
        manager.guideStrokes = manifest.guideStrokes

        // Restore folders.
        manager.folders = manifest.folders.map { f in
            LayerFolder(id: f.id, name: f.name, hasCustomName: f.hasCustomName,
                        isExpanded: f.isExpanded, isVisible: f.isVisible,
                        parentFolderID: f.parentFolderID, opacity: f.opacity,
                        blendMode: f.blendMode, isIsolated: f.isIsolated, alphaMask: f.alphaMask,
                        compositorRole: f.compositorRole, effect: f.effect,
                        // Absent means "nothing animated", which is what every document saved before
                        // §2.21 says and what a folder nobody has keyed says — one meaning, so the
                        // model's non-optional dictionary takes them both as empty.
                        effectTracks: f.effectTracks ?? [:],
                        // Absent means "nothing animated" here too — one meaning in both
                        // directions, so the model's non-optional dictionary takes both as empty.
                        channelTracks: f.channelTracks ?? [:],
                        channelBaselines: f.channelBaselines ?? [:],
                        // Absent means "none", one meaning in both directions — §2.26's marks and
                        // baselines follow `effectTracks`' rule exactly.
                        keyframeMarks: f.keyframeMarks ?? [],
                        pendingBaselines: f.pendingBaselines ?? [:],
                        // Optional on both sides — absent means "not posed", which is the same one
                        // meaning `alphaMask` and `effect` above carry.
                        transform: f.transform,
                        rotateSpeed: f.rotateSpeed ?? 0,
                        parallaxShare: f.parallaxShare,
                        shakeX: f.shakeX ?? 0, shakeY: f.shakeY ?? 0, shakeRotation: f.shakeRotation ?? 0)
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

        var layers: [Layer] = []
        for (layerIndex, layerManifest) in manifest.layers.enumerated() {
            let cels = celsByLayer[layerIndex]

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
                effectTracks: layerManifest.effectTracks ?? [:],
                channelTracks: layerManifest.channelTracks ?? [:],
                channelBaselines: layerManifest.channelBaselines ?? [:],
                keyframeMarks: layerManifest.keyframeMarks ?? [],
                pendingBaselines: layerManifest.pendingBaselines ?? [:],
                transform: layerManifest.transform,
                rotateSpeed: layerManifest.rotateSpeed ?? 0,
                parallaxShare: layerManifest.parallaxShare,
                shakeX: layerManifest.shakeX ?? 0,
                shakeY: layerManifest.shakeY ?? 0,
                shakeRotation: layerManifest.shakeRotation ?? 0,
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
        // What this open could not read, carried on the document rather than logged and forgotten.
        // `SaveDamageGate` is the only thing that reads it; `CanvasManager` merely holds it, which is
        // the smallest seam that gets a value produced in the vector decode to the save path.
        manager.loadDamage = decoded.damage
        let decodeFinished = CFAbsoluteTimeGetCurrent()
        if generatingThumbnails { manager.regenerateAllThumbnails() }
        let loadFinished = CFAbsoluteTimeGetCurrent()
        lastLoadProfile = LoadProfile(
            layerCount: layers.count,
            celCount: layers.reduce(0) { $0 + $1.cels.count },
            decodeSeconds: decodeFinished - loadStarted,
            thumbnailSeconds: loadFinished - decodeFinished,
            totalSeconds: loadFinished - loadStarted,
            thumbnailRegenerations: manager.thumbnailRegenerationCount,
            decodedOnMainThread: decoded.startedOnMainThread)
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
