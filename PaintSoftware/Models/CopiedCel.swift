import UIKit

/// A cel's content, detached from any position on the timeline — the timeline's Copy/Paste
/// clipboard payload. See `CanvasManager.copyCel`/`pasteCel`.
struct CopiedCel {
    var raster: RasterLayerTexture
    var fillImage: UIImage?
    var bakedImage: UIImage?
    var vector: VectorCanvas?
    var frameCount: Int
}
