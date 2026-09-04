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
    /// The keyframe feature's own group registry — KEYFRAMES.md §2.11. Beside `motionGroups` and
    /// written only when non-empty, the same absence-is-the-migration idiom every field here follows.
    var animationGroups: [AnimationGroup] = []
    /// **The document's brush table** — BRUSH.md §5.4, and the file every stroke's `brush` number is
    /// redeemed against. A sidecar in the package root beside `brushes/` rather than a key here, for
    /// the reason `CelManifest` pulls per-cel vector data out: this manifest is decoded in full for
    /// every gallery tile, and §2.10 makes the table grow with every brush the artist edits and draws
    /// with. Named here rather than assumed by filename so `ProjectBackupManager.validateProject` can
    /// refuse a package whose ink has lost the only thing that says what it was drawn with.
    ///
    /// Nil for a document with no vector ink at all, which is the one case where there is nothing to
    /// redeem.
    var brushTableFileName: String? = nil

    init(id: UUID, name: String, canvasWidth: Double, canvasHeight: Double, canvasPadding: Double = 0, fps: Int, sceneFrameCount: Int,
         layers: [LayerManifest], modifiedAt: Date,
         backgroundColor: CodableColor = CodableColor(red: 1, green: 1, blue: 1, alpha: 1), isBackgroundVisible: Bool = true,
         selectedBrush: Brush = BrushLibrary.softRound, customBrushes: [Brush] = [],
         vectorEraserMode: VectorEraserMode = .erase,
         folders: [FolderManifest] = [], viewPresets: [ViewPresetManifest] = [],
         motionGroups: [MotionGroup] = [], guideStrokes: [GuideStroke] = [],
         animationGroups: [AnimationGroup] = [], brushTableFileName: String? = nil) {
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
        self.animationGroups = animationGroups
        self.brushTableFileName = brushTableFileName
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
        animationGroups = try container.decodeIfPresent([AnimationGroup].self,
                                                        forKey: .animationGroups) ?? []
        brushTableFileName = try container.decodeIfPresent(String.self, forKey: .brushTableFileName)
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
        if !animationGroups.isEmpty { try container.encode(animationGroups, forKey: .animationGroups) }
        // Absent means "this document has no vector ink", the same absence-is-the-meaning idiom every
        // optional key here follows.
        try container.encodeIfPresent(brushTableFileName, forKey: .brushTableFileName)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, canvasWidth, canvasHeight, canvasPadding, fps, sceneFrameCount, layers,
             modifiedAt, backgroundColor, isBackgroundVisible, selectedBrush, customBrushes,
             vectorEraserMode, folders, viewPresets, motionGroups, guideStrokes,
             animationGroups, brushTableFileName
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
    /// `LayerFolder.hasCustomName` — `LayerManifest.hasCustomName`'s twin, argued there.
    var hasCustomName: Bool = false
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

    /// The folder's compositor role (§4.3) — node, or absent for an ordinary group. Absent is what
    /// every project saved before phase 8 carries and what every folder nobody has built a node out
    /// of carries, which is one meaning rather than two: see `alphaMask` above for the same argument,
    /// and `opacity` below for the one field that cannot be written this way. A third meaning — the
    /// retired `"slot"` tag — joins them at decode time; see `CompositorRole.decodeIfSupported`.
    var compositorRole: CompositorRole? = nil

    /// The folder's grade (§4.4's second wrapper, phase 9b), written only when there is one —
    /// `LayerManifest.effect` above settles the recipe (`Effect`'s persistence note), and it is
    /// `alphaMask`'s: nil is what every project saved before 9b says, so absence is the whole
    /// migration this field needs.
    var effect: Effect? = nil

    /// `LayerFolder.effectTracks` — KEYFRAMES.md §2.21's folder-scoped tracks on that grade, **written
    /// only when there are any**, keyed by `EffectParameter.id` and in absolute document frames.
    ///
    /// `LayerManifest.effectTracks` carries the whole argument for the optional-here /
    /// non-optional-in-the-model shape and for absence being the entire migration; this is that field
    /// on the other of the two grade homes, and the two must stay the same shape or a document would
    /// answer "is anything animated" differently depending on which one the artist reached for.
    var effectTracks: [String: AnimationCurve]? = nil

    /// `LayerFolder.keyframeMarks` — §2.26's marks that no channel keys, **written only when there
    /// are any**.
    /// `LayerManifest.keyframeMarks` carries the argument for the optional-here / non-optional-in-the-
    /// model shape; this is that field on the folder.
    var keyframeMarks: [Int]? = nil

    /// `LayerFolder.pendingBaselines` — the held pre-edit values, **written only when there are any**.
    /// `LayerManifest.pendingBaselines` carries the argument for persisting them at all.
    var pendingBaselines: [String: Double]? = nil

    /// **Not persisted, and derived at decode time.** True when this folder arrived without the
    /// group-property keys — which is to say it was written while `toggleFolderVisibility` still
    /// wrote through to every descendant. `ProjectStore.load` is the only reader; see the §10.3
    /// migration there for what it does with it.
    var wasSavedBeforeGroupProperties = false

    /// `LayerFolder.transform` — KEYFRAMES.md §4.4's container pose, **written only when there is
    /// one**. `alphaMask`'s recipe: absence is what every project saved before this field carries and
    /// what every folder nobody has posed carries, which is one meaning rather than two.
    var transform: LayerPose? = nil

    init(id: UUID, name: String, hasCustomName: Bool = false, isExpanded: Bool, isVisible: Bool,
         parentFolderID: UUID? = nil,
         opacity: Double = 1, blendMode: BlendMode = .normal, isIsolated: Bool = true,
         alphaMask: AlphaMask? = nil, compositorRole: CompositorRole? = nil, effect: Effect? = nil,
         effectTracks: [String: AnimationCurve]? = nil,
         keyframeMarks: [Int]? = nil, pendingBaselines: [String: Double]? = nil,
         transform: LayerPose? = nil) {
        self.id = id
        self.name = name
        self.hasCustomName = hasCustomName
        self.isExpanded = isExpanded
        self.isVisible = isVisible
        self.parentFolderID = parentFolderID
        self.opacity = opacity
        self.blendMode = blendMode
        self.isIsolated = isIsolated
        self.alphaMask = alphaMask
        self.compositorRole = compositorRole
        self.effect = effect
        self.effectTracks = effectTracks
        self.keyframeMarks = keyframeMarks
        self.pendingBaselines = pendingBaselines
        self.transform = transform
    }

    // Custom decoding for the same reason `LayerManifest` has one: a synthesized decoder demands
    // every non-optional key, so a property's default value is not a fallback for a missing one.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        hasCustomName = try container.decodeIfPresent(Bool.self, forKey: .hasCustomName) ?? false
        isExpanded = try container.decode(Bool.self, forKey: .isExpanded)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
        parentFolderID = try container.decodeIfPresent(UUID.self, forKey: .parentFolderID)
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        blendMode = try container.decodeIfPresent(BlendMode.self, forKey: .blendMode) ?? .normal
        isIsolated = try container.decodeIfPresent(Bool.self, forKey: .isIsolated) ?? true
        alphaMask = try container.decodeIfPresent(AlphaMask.self, forKey: .alphaMask)
        // Two different "no role" answers, kept apart on purpose.
        //
        // `decodeIfSupported` is the *migration*: a `"slot"` tag from a document saved while nodes
        // had input-slot folders decodes as an ordinary folder, so the node's operands become its
        // plain children in the order they already sat in (§4.3). Stated as a call rather than left
        // to the `try?` below, which would have produced the same result by accident.
        //
        // The `try?` is the *tolerance*: a role this build genuinely cannot read — an op from a
        // future version — degrades the folder to an ordinary one rather than costing the artist the
        // whole document to save a graph edge. A document that renders is the standing preference
        // (see `canMask`).
        compositorRole = (try? CompositorRole.decodeIfSupported(from: container, forKey: .compositorRole)) ?? nil
        effect = try container.decodeIfPresent(Effect.self, forKey: .effect)
        effectTracks = try container.decodeIfPresent([String: AnimationCurve].self, forKey: .effectTracks)
        keyframeMarks = try container.decodeIfPresent([Int].self, forKey: .keyframeMarks)
        pendingBaselines = try container.decodeIfPresent([String: Double].self, forKey: .pendingBaselines)
        transform = try container.decodeIfPresent(LayerPose.self, forKey: .transform)
        // `opacity` stands in for the whole group-property set, so **it must keep being written
        // unconditionally**. Omitting it when it happens to be 1 — the trick `ProjectManifest.encode`
        // plays with the interpolation registries — would make every untouched folder in every
        // future save look pre-phase-4 and re-arm a one-time migration.
        wasSavedBeforeGroupProperties = !container.contains(.opacity)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, hasCustomName, isExpanded, isVisible, parentFolderID, opacity, blendMode
        case isIsolated, alphaMask, compositorRole, effect, effectTracks
        case keyframeMarks, pendingBaselines, transform
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
    /// `Layer.hasCustomName` — **persisted, and that is the whole reason the field is worth having.**
    /// A name the artist chose that survived a save and then started being auto-clobbered after the
    /// reload would be worse than never renaming at all: the loss would arrive later, detached from
    /// anything they did. Absent decodes to false, which is what every project saved before this key
    /// says and what a layer nobody has renamed says — one meaning, `alphaMask`'s argument.
    var hasCustomName: Bool = false
    var opacity: Double
    var isVisible: Bool
    /// Mirrors `Layer.kind` (raster/vector/value). Persisted (defaulting missing values to `.raster`)
    /// so *added* layer kinds need no migration of already-saved projects — which is exactly what
    /// `.value` needed on arrival, since no document written before it contains the string and every
    /// one of them still decodes to the raster layer it was.
    ///
    /// A **removed** kind is the other half of that bargain and does need one: documents already
    /// contain the retired `"compositing"` string. `LayerKind.decodeMigratingEffectLayers`, used
    /// below, is the whole of it.
    var kind: LayerKind
    /// The folder this layer belongs to, if any. Stored as a UUID string for forward compat.
    var parentFolderID: String? = nil
    /// Defaulted like `kind`, so a project saved before layers could blend loads as all-normal.
    var blendMode: BlendMode = .normal
    /// The layer's alpha mask (§6.2), written only when there is one — see `FolderManifest.alphaMask`
    /// for why absence is the whole migration this field needs.
    var alphaMask: AlphaMask? = nil
    /// A `.value` layer's grade — §4.4's effect mode — written only when there is one. `Effect`'s
    /// persistence note settles the recipe, and it is `alphaMask`'s: nil is what every project saved
    /// before effects existed says, so absence is the whole migration this field needs.
    ///
    /// **Unchanged by the retirement of the `.compositing` kind, and that is what makes that
    /// migration one line.** An effect layer's grade was always written here, decoded here
    /// unconditionally by `init(from:)` below regardless of `kind`, and non-nil on a `.value` layer
    /// now *means* effect mode — so remapping the kind string is the only thing left to do.
    var effect: Effect? = nil
    /// `Layer.effectTracks` — KEYFRAMES.md §3.5's layer-scoped tracks, **written only when there are
    /// any**, keyed by `EffectParameter.id` and in absolute document frames.
    ///
    /// Optional here where the model's is a plain (possibly empty) dictionary, and the two shapes are
    /// answering different questions. In the model "no tracks" and "an empty dictionary of tracks" are
    /// the same state and there is no third one to distinguish, so a non-optional field with an empty
    /// default keeps every `Layer(...)` call site unchanged. On disk the question is whether to write
    /// a key at all: §3.5's idiom is that the format is versioned **by field presence**, so a document
    /// with nothing animated must be byte-for-byte the manifest it was before this key existed, and
    /// `{"effectTracks":{}}` would not be. `ProjectStore` maps empty to nil on the way out and the
    /// synthesized encoder then omits it, exactly as `alphaMask`, `effect` and `fill` are omitted.
    ///
    /// Absence is the whole migration this field needs, in both directions: it is what every project
    /// saved before keyframes says, and an older build reading a manifest that *does* carry it ignores
    /// the unknown key and opens the document with its grades static.
    var effectTracks: [String: AnimationCurve]? = nil
    /// `Layer.keyframeMarks` — §2.26's keyframe marks no channel keys, in absolute document frames, **written only
    /// when there are any**.
    ///
    /// Optional here and non-optional in the model for `effectTracks`' reason above, which applies
    /// word for word: "no marks" and "an empty array of marks" are one state in the model and there is
    /// no third, while on disk the question is whether to write a key at all — and §3.5's idiom is that
    /// the format is versioned by field presence, so a document nobody has keyframed must stay
    /// byte-for-byte the manifest it was.
    var keyframeMarks: [Int]? = nil
    /// `Layer.pendingBaselines` — the pre-edit value each channel is holding, **written only when
    /// there are any**.
    ///
    /// **Why an authoring transient is on disk at all.** It is the state between keyframe A and
    /// keyframe B, and that gap can span a save: an artist who marks A, moves a slider, and closes the
    /// document would come back with the old value gone, so placing B would write two identical keys
    /// and produce no animation — a wrong result with nothing on screen to explain it. `effectTracks`'
    /// field-presence rule covers the cost: a document in no such gap writes no key.
    var pendingBaselines: [String: Double]? = nil
    /// A `.value` layer's flat colour (§4.5), written only when there is one — `ValueFill`'s
    /// persistence note settles the recipe, and it is `effect`'s and `alphaMask`'s: nil is what every
    /// project saved before value layers existed says, so absence is the whole migration this field
    /// needs.
    var fill: ValueFill? = nil
    /// `Layer.fillReferenceOverride` (§6.6), written only when the artist has actually answered.
    /// Absence is the whole point rather than a gap: it is what "follow the default" *is*, so every
    /// project saved before this key — where fill reference was derived from visibility at load —
    /// decodes to exactly the behaviour it had.
    var fillReferenceOverride: Bool? = nil
    /// `Layer.transform` — KEYFRAMES.md §4.4's transformation layer, **written only when there is
    /// one**. `effect`'s recipe one field up, and it carries the same discriminant meaning on the
    /// way back in: a `.value` layer whose manifest has this key and no `effect` is in transform
    /// mode. Absence is the whole migration.
    var transform: LayerPose? = nil
    var cels: [CelManifest]

    init(id: UUID, name: String, hasCustomName: Bool = false, opacity: Double, isVisible: Bool,
         kind: LayerKind = .raster,
         parentFolderID: String? = nil, blendMode: BlendMode = .normal,
         alphaMask: AlphaMask? = nil, effect: Effect? = nil,
         effectTracks: [String: AnimationCurve]? = nil,
         keyframeMarks: [Int]? = nil, pendingBaselines: [String: Double]? = nil,
         fill: ValueFill? = nil,
         fillReferenceOverride: Bool? = nil, transform: LayerPose? = nil,
         cels: [CelManifest]) {
        self.id = id
        self.name = name
        self.hasCustomName = hasCustomName
        self.opacity = opacity
        self.isVisible = isVisible
        self.kind = kind
        self.parentFolderID = parentFolderID
        self.blendMode = blendMode
        self.alphaMask = alphaMask
        self.effect = effect
        self.effectTracks = effectTracks
        self.keyframeMarks = keyframeMarks
        self.pendingBaselines = pendingBaselines
        self.fill = fill
        self.fillReferenceOverride = fillReferenceOverride
        self.transform = transform
        self.cels = cels
    }

    // Custom decoding so projects saved before `kind` existed still load: a missing key just means
    // "saved before layer kinds existed", i.e. an ordinary raster layer.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        hasCustomName = try container.decodeIfPresent(Bool.self, forKey: .hasCustomName) ?? false
        opacity = try container.decode(Double.self, forKey: .opacity)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
        // Not `decodeIfPresent(LayerKind.self, …)`: that substitutes `.raster` only for an *absent*
        // key and throws on the retired `"compositing"` one, taking the whole project down with it.
        // See `LayerKind.decodeMigratingEffectLayers`, which carries the argument.
        kind = try LayerKind.decodeMigratingEffectLayers(from: container, forKey: .kind) ?? .raster
        cels = try container.decode([CelManifest].self, forKey: .cels)
        parentFolderID = try container.decodeIfPresent(String.self, forKey: .parentFolderID)
        blendMode = try container.decodeIfPresent(BlendMode.self, forKey: .blendMode) ?? .normal
        alphaMask = try container.decodeIfPresent(AlphaMask.self, forKey: .alphaMask)
        effect = try container.decodeIfPresent(Effect.self, forKey: .effect)
        effectTracks = try container.decodeIfPresent([String: AnimationCurve].self, forKey: .effectTracks)
        keyframeMarks = try container.decodeIfPresent([Int].self, forKey: .keyframeMarks)
        pendingBaselines = try container.decodeIfPresent([String: Double].self, forKey: .pendingBaselines)
        fill = try container.decodeIfPresent(ValueFill.self, forKey: .fill)
        fillReferenceOverride = try container.decodeIfPresent(Bool.self, forKey: .fillReferenceOverride)
        transform = try container.decodeIfPresent(LayerPose.self, forKey: .transform)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, hasCustomName, opacity, isVisible, kind, parentFolderID, blendMode, alphaMask
        case effect, effectTracks, keyframeMarks, pendingBaselines, fill, fillReferenceOverride
        case transform, cels
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
    /// `true` when no raster PNG was written because the cel's `RasterLayerTexture` held no backing
    /// bitmap at all — see `RasterLayerTexture.hasContent`. The overwhelmingly common case on a
    /// vector document, where every cel's raster tier is untouched and the PNG is a canvas-sized
    /// image of nothing (73,558 bytes and a 16 MiB `CGContext` on load, per cel, measured on the
    /// owner's own 2048² project).
    ///
    /// **`rasterFileName` still carries the name the file *would* have had, and that is deliberate
    /// rather than sloppy.** Making it optional would change how the app treats packages from the
    /// previous PencilKit engine: they have no `rasterFileName` key, the non-optional field is what
    /// makes their manifests fail to decode, and failing to decode is what makes the gallery skip
    /// them instead of opening them as blank documents. That behaviour is documented above and is not
    /// this key's business to retire. Keeping the name also means the file's identity is unchanged if
    /// the cel is ever drawn into and saved again.
    ///
    /// **An older build reading a package that sets this still opens it correctly.** `Decodable`
    /// ignores keys it does not know, so the old build decodes the manifest, looks for the named
    /// raster PNG, does not find it, and falls through `decodeCel`'s existing
    /// `?? .empty(size: canvasSize)` — which is exactly the blank texture the new build would have
    /// built. (`ProjectBackupManager.validateProject` on that older build would report the package
    /// damaged; there is no forward-compatibility story for the validator, and none is claimed.)
    var rasterOmitted: Bool? = nil
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
    /// JSON file holding this cel's pose channels (`Cel.transformTracks` and
    /// `Cel.pendingPoseBaselines`), when it has any — KEYFRAMES.md §3.5.
    ///
    /// **Its own sidecar for `interpolationFileName`'s reason verbatim**: a pose track is unbounded
    /// (a recorded shake is dozens of keys a channel, and a channel per group), and `manifest.json`
    /// is read in full for every gallery tile. A missing or unreadable sidecar costs the *animation*,
    /// not the drawing — the cel loads with its ink where it stores it.
    ///
    /// **In `ProjectBackupManager.ManifestSkeleton.Cel` from day one**, unlike
    /// `interpolationFileName`, which §3.5 records as a real existing gap: a cel whose recipe sidecar
    /// is missing still validates and the atomic save proceeds. Not inheriting that is the whole of
    /// what "add it to the validator on day one" asks.
    var animationFileName: String? = nil
}
