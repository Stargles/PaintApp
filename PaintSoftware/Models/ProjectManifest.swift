import Foundation

struct ProjectManifest: Codable {
    var id: UUID
    var name: String
    var canvasWidth: Double
    var canvasHeight: Double
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

    init(id: UUID, name: String, canvasWidth: Double, canvasHeight: Double, fps: Int, sceneFrameCount: Int,
         layers: [LayerManifest], modifiedAt: Date,
         backgroundColor: CodableColor = CodableColor(red: 1, green: 1, blue: 1, alpha: 1), isBackgroundVisible: Bool = true,
         selectedBrush: Brush = BrushLibrary.softRound, customBrushes: [Brush] = []) {
        self.id = id
        self.name = name
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.fps = fps
        self.sceneFrameCount = sceneFrameCount
        self.layers = layers
        self.modifiedAt = modifiedAt
        self.backgroundColor = backgroundColor
        self.isBackgroundVisible = isBackgroundVisible
        self.selectedBrush = selectedBrush
        self.customBrushes = customBrushes
    }

    // Custom decoding so projects saved before backgroundColor/isBackgroundVisible (or, more
    // recently, selectedBrush/customBrushes) existed — missing those keys entirely — still load
    // instead of failing to decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        canvasWidth = try container.decode(Double.self, forKey: .canvasWidth)
        canvasHeight = try container.decode(Double.self, forKey: .canvasHeight)
        fps = try container.decode(Int.self, forKey: .fps)
        sceneFrameCount = try container.decode(Int.self, forKey: .sceneFrameCount)
        layers = try container.decode([LayerManifest].self, forKey: .layers)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        backgroundColor = try container.decodeIfPresent(CodableColor.self, forKey: .backgroundColor)
            ?? CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
        isBackgroundVisible = try container.decodeIfPresent(Bool.self, forKey: .isBackgroundVisible) ?? true
        selectedBrush = try container.decodeIfPresent(Brush.self, forKey: .selectedBrush) ?? BrushLibrary.softRound
        customBrushes = try container.decodeIfPresent([Brush].self, forKey: .customBrushes) ?? []
    }
}

struct CodableColor: Codable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
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
    var isObjectLayer: Bool
    var objectImageFileName: String?
    var objectTransform: ObjectTransformManifest?
    var cels: [CelManifest]

    init(id: UUID, name: String, opacity: Double, isVisible: Bool, kind: LayerKind = .raster, isObjectLayer: Bool,
         objectImageFileName: String?, objectTransform: ObjectTransformManifest?, cels: [CelManifest]) {
        self.id = id
        self.name = name
        self.opacity = opacity
        self.isVisible = isVisible
        self.kind = kind
        self.isObjectLayer = isObjectLayer
        self.objectImageFileName = objectImageFileName
        self.objectTransform = objectTransform
        self.cels = cels
    }

    // Custom decoding so projects saved before object layers (or, more recently, `kind`) existed
    // still load: those saved a full-bleed "image layer" under the old
    // `isImageLayer`/`backgroundImageFileName` keys, which becomes an object layer with
    // `objectTransform` left nil — ProjectStore.load fills that in with a canvas-covering
    // transform once it knows the canvas size and image. `kind` missing entirely just means
    // "saved before layer kinds existed", i.e. an ordinary raster layer.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        opacity = try container.decode(Double.self, forKey: .opacity)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
        kind = try container.decodeIfPresent(LayerKind.self, forKey: .kind) ?? .raster
        cels = try container.decode([CelManifest].self, forKey: .cels)

        if let modernIsObjectLayer = try container.decodeIfPresent(Bool.self, forKey: .isObjectLayer) {
            isObjectLayer = modernIsObjectLayer
            objectImageFileName = try container.decodeIfPresent(String.self, forKey: .objectImageFileName)
            objectTransform = try container.decodeIfPresent(ObjectTransformManifest.self, forKey: .objectTransform)
        } else {
            isObjectLayer = try container.decodeIfPresent(Bool.self, forKey: .isImageLayer) ?? false
            objectImageFileName = try container.decodeIfPresent(String.self, forKey: .backgroundImageFileName)
            objectTransform = nil
        }
    }

    // Custom encoding to match the custom init(from:) above — CodingKeys has two legacy,
    // decode-only cases with no corresponding stored property, which stops synthesis of this.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encode(kind, forKey: .kind)
        try container.encode(isObjectLayer, forKey: .isObjectLayer)
        try container.encodeIfPresent(objectImageFileName, forKey: .objectImageFileName)
        try container.encodeIfPresent(objectTransform, forKey: .objectTransform)
        try container.encode(cels, forKey: .cels)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, opacity, isVisible, kind, isObjectLayer, objectImageFileName, objectTransform, cels
        case isImageLayer, backgroundImageFileName // legacy, decode-only
    }
}

struct ObjectTransformManifest: Codable {
    var x: Double
    var y: Double
    var scale: Double
    var rotation: Double
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
}
