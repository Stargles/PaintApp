import Foundation

struct ProjectManifest: Codable {
    var id: UUID
    var name: String
    var canvasWidth: Double
    var canvasHeight: Double
    /// Light-grey drawable margin around the artwork. Folded into canvasWidth/Height (buffers save
    /// at the full padded size); restoring it just redraws the paper inset — no resize on load.
    var canvasPadding: Double
    var fps: Int
    var sceneFrameCount: Int
    var layers: [LayerManifest]
    var modifiedAt: Date
    var backgroundColor: CodableColor
    var isBackgroundVisible: Bool
    /// The brush active when the project was last saved, and any custom (imported) brushes
    /// associated with it. The actual custom-brush stamp texture image files are copied into this
    /// project's own `brushes/` folder alongside the manifest so a saved project stays
    /// self-contained even if the shared `BrushLibrary.customBrushesDirectory` entry is later
    /// renamed/deleted, or the project moves to another device.
    var selectedBrush: Brush
    var customBrushes: [Brush]
    /// The vector-eraser behaviour active when the project was last saved. Persisted per project
    /// rather than app-wide since it's bound up with the artwork: a project drawn with
    /// `.cutToIntersection` should reopen still cutting to intersections, without leaking into the
    /// next project. Meaningless for all-raster projects, which just save/reload the default.
    var vectorEraserMode: VectorEraserMode
    var folders: [FolderManifest] = []
    var viewPresets: [ViewPresetManifest] = []
    /// The document-level interpolation registries. Live in the manifest rather than beside a cel
    /// because they are *not* owned by one: a motion group spans layers and a guide is referenced
    /// by several intervals. Both are small, so keeping them inline costs the gallery's manifest
    /// read nothing, unlike the per-cel recipes, which get their own files.
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
        // Absent for pre-interpolation projects and any project that never uses it (an empty
        // registry is not written).
        motionGroups = try container.decodeIfPresent([MotionGroup].self, forKey: .motionGroups) ?? []
        guideStrokes = try container.decodeIfPresent([GuideStroke].self, forKey: .guideStrokes) ?? []
    }

    /// Written explicitly so the two interpolation registries can be *omitted* when empty — a
    /// synthesized encoder would write `"motionGroups":[]` into every manifest in the world.
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

    /// The §4.1 group properties, each defaulted to its identity so a project saved before phase 4
    /// decodes into folders that composite exactly as they did.
    var opacity: Double = 1
    var blendMode: BlendMode = .normal
    var isIsolated: Bool = true

    /// The group's own alpha mask (§6.2). Absent for every project saved before phase 6 and for
    /// every group nobody has masked, which is the same thing as far as decoding is concerned: nil
    /// means "no mask". Written only when it exists, so an unmasked document's manifest is byte-for
    /// byte what it was — unlike `opacity`, which has to be written unconditionally because the
    /// §10.3 migration reads its *absence* as a signal.
    var alphaMask: AlphaMask? = nil

    /// The folder's compositor role (§4.3) — node, input slot, or absent for an ordinary group.
    /// Absent is what every project saved before phase 8 carries and what every folder nobody has
    /// built a node out of carries, which is one meaning rather than two: see `alphaMask` above for
    /// the same argument, and `opacity` below for the one field that cannot be written this way.
    var compositorRole: CompositorRole? = nil

    /// The folder's grade (§4.4's second wrapper, phase 9b), written only when there is one —
    /// `LayerManifest.effect` above settles the recipe (`Effect`'s persistence note), and it is
    /// `alphaMask`'s: nil is what every project saved before 9b says, so absence is the whole
    /// migration this field needs.
    var effect: Effect? = nil

    /// **Not persisted, and derived at decode time.** True when this folder arrived without the
    /// group-property keys — which is to say it was written while `toggleFolderVisibility` still
    /// wrote through to every descendant. `ProjectStore.load` is the only reader; see the §10.3
    /// migration there for what it does with it.
    var wasSavedBeforeGroupProperties = false

    init(id: UUID, name: String, isExpanded: Bool, isVisible: Bool, parentFolderID: UUID? = nil,
         opacity: Double = 1, blendMode: BlendMode = .normal, isIsolated: Bool = true,
         alphaMask: AlphaMask? = nil, compositorRole: CompositorRole? = nil, effect: Effect? = nil) {
        self.id = id
        self.name = name
        self.isExpanded = isExpanded
        self.isVisible = isVisible
        self.parentFolderID = parentFolderID
        self.opacity = opacity
        self.blendMode = blendMode
        self.isIsolated = isIsolated
        self.alphaMask = alphaMask
        self.compositorRole = compositorRole
        self.effect = effect
    }

    // Custom decoding for the same reason `LayerManifest` has one: a synthesized decoder demands
    // every non-optional key, so a property's default value is not a fallback for a missing one.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isExpanded = try container.decode(Bool.self, forKey: .isExpanded)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
        parentFolderID = try container.decodeIfPresent(UUID.self, forKey: .parentFolderID)
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        blendMode = try container.decodeIfPresent(BlendMode.self, forKey: .blendMode) ?? .normal
        isIsolated = try container.decodeIfPresent(Bool.self, forKey: .isIsolated) ?? true
        alphaMask = try container.decodeIfPresent(AlphaMask.self, forKey: .alphaMask)
        // Swallowed rather than propagated: a role this build cannot read — a future op, a truncated
        // slot tag — degrades the folder to an ordinary one, which is exactly what §4.3's storage
        // decision makes it anyway. Throwing here would cost the artist the whole document to save
        // a graph edge, and a document that renders is the standing preference (see `canMask`).
        compositorRole = (try? container.decodeIfPresent(CompositorRole.self, forKey: .compositorRole)) ?? nil
        effect = try container.decodeIfPresent(Effect.self, forKey: .effect)
        // `opacity` stands in for the whole group-property set, so **it must keep being written
        // unconditionally**. Omitting it when it happens to be 1 — the trick `ProjectManifest.encode`
        // plays with the interpolation registries — would make every untouched folder in every
        // future save look pre-phase-4 and re-arm a one-time migration.
        wasSavedBeforeGroupProperties = !container.contains(.opacity)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isExpanded, isVisible, parentFolderID, opacity, blendMode, isIsolated, alphaMask
        case compositorRole, effect
    }
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
    /// Mirrors `Layer.kind` (raster/vector/compositing). Persisted now (defaulting missing values
    /// to `.raster`) so future layer kinds need no migration of already-saved projects.
    var kind: LayerKind
    /// The folder this layer belongs to, if any. Stored as a UUID string for forward compat.
    var parentFolderID: String? = nil
    /// Defaulted like `kind`, so a project saved before layers could blend loads as all-normal.
    var blendMode: BlendMode = .normal
    /// The layer's alpha mask (§6.2), written only when there is one — see `FolderManifest.alphaMask`
    /// for why absence is the whole migration this field needs.
    var alphaMask: AlphaMask? = nil
    /// A `.compositing` layer's grade (§4.4), written only when there is one — `Effect`'s persistence
    /// note settles the recipe, and it is `alphaMask`'s: nil is what every project saved before
    /// effects existed says, so absence is the whole migration this field needs.
    var effect: Effect? = nil
    /// `Layer.fillReferenceOverride` (§6.6), written only when the artist has actually answered.
    /// Absence is the whole point rather than a gap: it is what "follow the default" *is*, so every
    /// project saved before this key — where fill reference was derived from visibility at load —
    /// decodes to exactly the behaviour it had.
    var fillReferenceOverride: Bool? = nil
    var cels: [CelManifest]

    init(id: UUID, name: String, opacity: Double, isVisible: Bool, kind: LayerKind = .raster,
         parentFolderID: String? = nil, blendMode: BlendMode = .normal,
         alphaMask: AlphaMask? = nil, effect: Effect? = nil,
         fillReferenceOverride: Bool? = nil, cels: [CelManifest]) {
        self.id = id
        self.name = name
        self.opacity = opacity
        self.isVisible = isVisible
        self.kind = kind
        self.parentFolderID = parentFolderID
        self.blendMode = blendMode
        self.alphaMask = alphaMask
        self.effect = effect
        self.fillReferenceOverride = fillReferenceOverride
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
        blendMode = try container.decodeIfPresent(BlendMode.self, forKey: .blendMode) ?? .normal
        alphaMask = try container.decodeIfPresent(AlphaMask.self, forKey: .alphaMask)
        effect = try container.decodeIfPresent(Effect.self, forKey: .effect)
        fillReferenceOverride = try container.decodeIfPresent(Bool.self, forKey: .fillReferenceOverride)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, opacity, isVisible, kind, parentFolderID, blendMode, alphaMask, effect
        case fillReferenceOverride, cels
    }
}

struct CelManifest: Codable {
    var id: UUID
    var startFrame: Int
    var frameCount: Int
    /// PNG file holding this cel's live-stroke raster (`Cel.raster`, native canvas resolution).
    /// Projects from the previous PencilKit engine have no `rasterFileName` key and fail to decode
    /// gracefully (skipped in the gallery list) rather than crash.
    var rasterFileName: String
    var fillImageFileName: String?
    /// Raster content baked into this cel by a select/move/fill/clear operation (`Cel.bakedImage`).
    var bakedImageFileName: String? = nil
    /// JSON file holding this cel's vector content (`Cel.vector` → `VectorCanvasData`) for
    /// `.vector` layers. Optional so raster-only and pre-vector saves load unchanged.
    var vectorFileName: String? = nil
    /// JSON file holding this cel's `InterpolationRecipe`, when it has one. Its own file rather
    /// than inline in the manifest because a recipe carries lattices (vertex arrays per motion
    /// group per keyframe) and `manifest.json` is read in full for every gallery tile.
    var interpolationFileName: String? = nil
}
