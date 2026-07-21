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
    var isImageLayer: Bool
    var backgroundImageFileName: String?
    var cels: [CelManifest]
}

struct CelManifest: Codable {
    var id: UUID
    var startFrame: Int
    var frameCount: Int
    var drawingFileName: String
    var fillImageFileName: String?
}
