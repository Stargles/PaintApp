import UIKit

struct Layer: Identifiable {
    let id: UUID
    var name: String
    var opacity: Double
    var isVisible: Bool
    /// Whether this layer's content contributes to the fill tool's boundary walls. The fill uses the
    /// union of all layers with this set (see `CanvasManager.fillReferenceSources`). Defaults to true;
    /// hiding a layer clears it (hidden layers are fill-excluded by default) and it can be toggled back
    /// on independently from the layer's Edit menu. See [[feedback-vector-layer-extensibility]].
    var isFillReference: Bool = true
    var kind: LayerKind = .raster
    /// How this layer combines with everything beneath it *within its own container* — a layer inside
    /// a group blends against that group's contents, not through it, which is what §4.2's isolation
    /// means from the layer's side. Defaulted, so every existing project and every `Layer(...)` call
    /// site is unchanged.
    var blendMode: BlendMode = .normal
    /// Where this layer is allowed to show, clipped to the alpha of other layers or groups (§6.2).
    /// Nil — the default, and what a manifest without the key decodes to — is "no mask"; the mask is
    /// never baked into the pixels, so clearing it restores the whole buffer (§6.1).
    var alphaMask: AlphaMask? = nil
    /// If set, this layer belongs to the folder with this ID. Layer ordering in the `layers` array
    /// determines the stacking order within each folder. A folder's visibility/expand state lives on
    /// the corresponding `LayerFolder` in `CanvasManager.folders`.
    var parentFolderID: UUID? = nil
    var cels: [Cel]
    var thumbnail: UIImage? = nil
}
