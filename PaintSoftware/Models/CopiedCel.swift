import UIKit

/// A cel's content, detached from any position on the timeline — the timeline's Copy/Paste
/// clipboard payload. See `CanvasManager.copyCel`/`pasteCel`.
struct CopiedCel {
    var raster: RasterLayerTexture
    var fillImage: UIImage?
    var bakedImage: UIImage?
    var vector: VectorCanvas?
    /// **The pose channels travel with the drawing** — KEYFRAMES.md §3.1's *"it rides the cel through
    /// move, split, duplicate and paste for free"*, which is only true of paste because these two are
    /// here. In cel-local frames, so they need no adjustment on the way in or out.
    var transformTracks: [String: TransformTrack] = [:]
    var pendingPoseBaselines: [String: PoseQuad] = [:]
    var frameCount: Int
}
