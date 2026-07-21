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

    init(id: UUID, name: String, canvasWidth: Double, canvasHeight: Double, fps: Int, sceneFrameCount: Int,
         layers: [LayerManifest], modifiedAt: Date,
         backgroundColor: CodableColor = CodableColor(red: 1, green: 1, blue: 1, alpha: 1), isBackgroundVisible: Bool = true) {
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
    }

    // Custom decoding so projects saved before backgroundColor/isBackgroundVisible existed
    // (missing those keys entirely) still load instead of failing to decode.
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
    var isObjectLayer: Bool
    var objectImageFileName: String?
    var objectTransform: ObjectTransformManifest?
    var cels: [CelManifest]

    init(id: UUID, name: String, opacity: Double, isVisible: Bool, isObjectLayer: Bool,
         objectImageFileName: String?, objectTransform: ObjectTransformManifest?, cels: [CelManifest]) {
        self.id = id
        self.name = name
        self.opacity = opacity
        self.isVisible = isVisible
        self.isObjectLayer = isObjectLayer
        self.objectImageFileName = objectImageFileName
        self.objectTransform = objectTransform
        self.cels = cels
    }

    // Custom decoding so projects saved before object layers existed still load: those saved
    // a full-bleed "image layer" under the old `isImageLayer`/`backgroundImageFileName` keys,
    // which becomes an object layer with `objectTransform` left nil — ProjectStore.load fills
    // that in with a canvas-covering transform once it knows the canvas size and image.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        opacity = try container.decode(Double.self, forKey: .opacity)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
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
        try container.encode(isObjectLayer, forKey: .isObjectLayer)
        try container.encodeIfPresent(objectImageFileName, forKey: .objectImageFileName)
        try container.encodeIfPresent(objectTransform, forKey: .objectTransform)
        try container.encode(cels, forKey: .cels)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, opacity, isVisible, isObjectLayer, objectImageFileName, objectTransform, cels
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
    var drawingFileName: String
    var fillImageFileName: String?
}
