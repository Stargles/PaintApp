import UIKit

/// A cel's content, detached from any position on the timeline — the timeline's Copy/Paste
/// clipboard payload. See `CanvasManager.copyCel`/`pasteCel`.
///
/// **There is no `interpolation` field and there should not be one** — ruled 2026-09-03. A recipe is
/// the one thing a snapshot cannot capture by copying it, because it names *other cels* the artist
/// may redraw, delete or move before pasting; so an in-between is flattened into a still by `copyCel`
/// and what lands here is that picture, in `bakedImage`. Adding the field back would make a paste a
/// picture of the document as it is *then* rather than of what the artist copied.
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
