import Foundation

struct ProjectManifest: Codable {
    var id: UUID
    var name: String
    var canvasWidth: Double
    var canvasHeight: Double
    /// Light-grey drawable margin around the artwork (see `CanvasManager.canvasPadding`). Folded into
    /// canvasWidth/Height (the buffers are saved at the full padded size), so this only needs restoring
    /// so the paper inset is drawn correctly — no resize happens on load.
    var canvasPadding: Double
    var fps: Int
    var sceneFrameCount: Int
    var layers: [LayerManifest]
    var modifiedAt: Date
    var backgroundColor: CodableColor
    var isBackgroundVisible: Bool
    /// The brush active when the project was last saved, and any custom (imported) brushes
    /// associated with it. `Brush` (see Engine/Brush.swift) is already `Codable`, so this is just
    /// metadata — the actual custom-brush stamp texture image files referenced by
    /// `Brush.customTextureFileName` are copied into this project's own `brushes/` folder
    /// alongside the manifest (see `ProjectStore.save`/`load`) so a saved project stays
    /// self-contained even if the shared `BrushLibrary.customBrushesDirectory` entry is later
    /// renamed/deleted, or the project is moved to another device.
    var selectedBrush: Brush
    var customBrushes: [Brush]
    /// The vector-eraser behaviour active when the project was last saved (see
    /// `CanvasManager.vectorEraserMode` and VECTOR_ERASER_PLAN.md §5). Persisted per project rather
    /// than app-wide because it is bound up with the artwork: a project drawn on vector layers with
    /// `.cutToIntersection` should reopen still cutting to intersections, without the mode leaking
    /// into the next project you open. Meaningless for all-raster projects, which simply save and
    /// reload the default.
    var vectorEraserMode: VectorEraserMode
    var folders: [FolderManifest] = []
    var viewPresets: [ViewPresetManifest] = []
    /// The document-level interpolation registries (see `CanvasManager.motionGroups` /
    /// `.guideStrokes`). They live in the manifest rather than beside a cel precisely because they
    /// are *not* owned by one: a motion group spans layers and a guide is referenced by several
    /// intervals. Both are small — a group is four fields, a guide a polyline — so keeping them
    /// inline here costs the gallery's manifest read nothing, unlike the per-cel recipes, which are
    /// written to their own files.
    var motionGroups: [MotionGroup] = []
    var guideStrokes: [GuideStroke] = []

    init(id: UUID, name: String, canvasWidth: Double, canvasHeight: Double, canvasPadding: Double = 0, fps: Int, sceneFrameCount: Int,
         layers: [LayerManifest], modifiedAt: Date,
         backgroundColor: CodableColor = CodableColor(red: 1, green: 1, blue: 1, alpha: 1), isBackgroundVisible: Bool = true,
         selectedBrush: Brush = BrushLibrary.softRound, customBrushes: [Brush] = [],
         vectorEraserMode: VectorEraserMode = .erase,
         folders: [FolderManifest] = [], viewPresets: [ViewPresetManifest] = [],
         motionGroups: [MotionGroup] = [], guideStrokes: [GuideStroke] = []) {
        self.id = id
        self.name = name
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.canvasPadding = canvasPadding
        self.fps = fps
        self.sceneFrameCount = sceneFrameCount
        self.layers = layers
        self.modifiedAt = modifiedAt
        self.backgroundColor = backgroundColor
        self.isBackgroundVisible = isBackgroundVisible
        self.selectedBrush = selectedBrush
        self.customBrushes = customBrushes
        self.vectorEraserMode = vectorEraserMode
        self.folders = folders
        self.viewPresets = viewPresets
        self.motionGroups = motionGroups
        self.guideStrokes = guideStrokes
    }

    // Custom decoding so projects saved before backgroundColor/isBackgroundVisible (or, more
    // recently, selectedBrush/customBrushes and vectorEraserMode) existed — missing those keys
    // entirely — still load instead of failing to decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        canvasWidth = try container.decode(Double.self, forKey: .canvasWidth)
        canvasHeight = try container.decode(Double.self, forKey: .canvasHeight)
        canvasPadding = try container.decodeIfPresent(Double.self, forKey: .canvasPadding) ?? 0
        fps = try container.decode(Int.self, forKey: .fps)
        sceneFrameCount = try container.decode(Int.self, forKey: .sceneFrameCount)
        layers = try container.decode([LayerManifest].self, forKey: .layers)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        backgroundColor = try container.decodeIfPresent(CodableColor.self, forKey: .backgroundColor)
            ?? CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
        isBackgroundVisible = try container.decodeIfPresent(Bool.self, forKey: .isBackgroundVisible) ?? true
        selectedBrush = try container.decodeIfPresent(Brush.self, forKey: .selectedBrush) ?? BrushLibrary.softRound
        customBrushes = try container.decodeIfPresent([Brush].self, forKey: .customBrushes) ?? []
        vectorEraserMode = try container.decodeIfPresent(VectorEraserMode.self, forKey: .vectorEraserMode) ?? .erase
        folders = try container.decodeIfPresent([FolderManifest].self, forKey: .folders) ?? []
        viewPresets = try container.decodeIfPresent([ViewPresetManifest].self, forKey: .viewPresets) ?? []
        // Absent for every project saved before interpolation existed, which is all of them — and
        // absent for every project that never uses it, since an empty registry is not written.
        motionGroups = try container.decodeIfPresent([MotionGroup].self, forKey: .motionGroups) ?? []
        guideStrokes = try container.decodeIfPresent([GuideStroke].self, forKey: .guideStrokes) ?? []
    }

    /// Written explicitly so the two interpolation registries can be *omitted* when empty: a project
    /// that never interpolates must encode exactly as it did before this existed, and a synthesized
    /// encoder would write `"motionGroups":[]` into every manifest in the world.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(canvasWidth, forKey: .canvasWidth)
        try container.encode(canvasHeight, forKey: .canvasHeight)
        try container.encode(canvasPadding, forKey: .canvasPadding)
        try container.encode(fps, forKey: .fps)
        try container.encode(sceneFrameCount, forKey: .sceneFrameCount)
        try container.encode(layers, forKey: .layers)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encode(backgroundColor, forKey: .backgroundColor)
        try container.encode(isBackgroundVisible, forKey: .isBackgroundVisible)
        try container.encode(selectedBrush, forKey: .selectedBrush)
        try container.encode(customBrushes, forKey: .customBrushes)
        try container.encode(vectorEraserMode, forKey: .vectorEraserMode)
        try container.encode(folders, forKey: .folders)
        try container.encode(viewPresets, forKey: .viewPresets)
        if !motionGroups.isEmpty { try container.encode(motionGroups, forKey: .motionGroups) }
        if !guideStrokes.isEmpty { try container.encode(guideStrokes, forKey: .guideStrokes) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, canvasWidth, canvasHeight, canvasPadding, fps, sceneFrameCount, layers,
             modifiedAt, backgroundColor, isBackgroundVisible, selectedBrush, customBrushes,
             vectorEraserMode, folders, viewPresets, motionGroups, guideStrokes
    }
}

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
}

struct FolderManifest: Codable {
    var id: UUID
    var name: String
    var isExpanded: Bool
    var isVisible: Bool
    /// Set when this folder is nested inside another. Optional so projects saved before folders
    /// could nest still decode.
    var parentFolderID: UUID? = nil
}

struct ViewPresetManifest: Codable {
    var id: UUID
    var name: String
    /// UUID string -> isVisible, because JSON dictionaries require String keys.
    var layerVisibility: [String: Bool]
    /// Folder UUID string -> isVisible. Defaults to empty so presets saved before folders had
    /// their own visibility snapshot still decode.
    var folderVisibility: [String: Bool] = [:]
}

struct LayerManifest: Codable {
    var id: UUID
    var name: String
    var opacity: Double
    var isVisible: Bool
    /// Mirrors `Layer.kind` (raster/vector/compositing — see CanvasManager.swift). Only `.raster`
    /// is actually produced by the app today; this persists the field now (defaulting missing
    /// values to `.raster`) so that if/when vector or compositing layers land, no further
    /// migration of already-saved projects is needed — see the project's vector-layer roadmap.
    var kind: LayerKind
    /// The folder this layer belongs to, if any. Stored as a UUID string for forward compat.
    var parentFolderID: String? = nil
    var cels: [CelManifest]

    init(id: UUID, name: String, opacity: Double, isVisible: Bool, kind: LayerKind = .raster,
         parentFolderID: String? = nil, cels: [CelManifest]) {
        self.id = id
        self.name = name
        self.opacity = opacity
        self.isVisible = isVisible
        self.kind = kind
        self.parentFolderID = parentFolderID
        self.cels = cels
    }

    // Custom decoding so projects saved before `kind` existed still load: a missing key just means
    // "saved before layer kinds existed", i.e. an ordinary raster layer.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        opacity = try container.decode(Double.self, forKey: .opacity)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
        kind = try container.decodeIfPresent(LayerKind.self, forKey: .kind) ?? .raster
        cels = try container.decode([CelManifest].self, forKey: .cels)
        parentFolderID = try container.decodeIfPresent(String.self, forKey: .parentFolderID)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, opacity, isVisible, kind, parentFolderID, cels
    }
}

struct CelManifest: Codable {
    var id: UUID
    var startFrame: Int
    var frameCount: Int
    /// PNG file holding this cel's live-stroke raster (`Cel.raster`, native canvas resolution) —
    /// replaces the old PKDrawing-based `.drawing` file format. Not migrated: a project saved by
    /// the previous PencilKit engine has no `rasterFileName` key and fails to decode gracefully
    /// (skipped in the gallery list) rather than crash — see BUGS.md's engine-rewrite notes.
    var rasterFileName: String
    var fillImageFileName: String?
    /// Raster content baked into this cel by a select/move/fill/clear operation (see
    /// `Cel.bakedImage`). A plain optional: Swift's synthesized `Codable` already decodes a missing
    /// key as `nil`, so projects saved before this feature existed still load fine.
    var bakedImageFileName: String? = nil
    /// JSON file holding this cel's vector content (`Cel.vector` → `VectorCanvasData`: strokes,
    /// image element refs, and the overall transform) for `.vector` layers. Optional/decodeIfPresent-
    /// friendly so raster-only projects (and pre-vector saves) load unchanged.
    var vectorFileName: String? = nil
    /// JSON file holding this cel's `InterpolationRecipe`, when it has one. Its own file rather than
    /// inline in the manifest because a recipe carries lattices — one array of vertices per motion
    /// group per keyframe — and `manifest.json` is read in full for every tile in the gallery. A
    /// plain optional: a missing key decodes as `nil`, i.e. "an ordinary, non-interpolated cel".
    var interpolationFileName: String? = nil
}
