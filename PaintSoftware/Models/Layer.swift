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
    /// The grade a `.compositing` layer applies (§4.4), or nil on a layer that draws pixels instead.
    ///
    /// Stored on `Layer` rather than in `LayerKind`'s payload so that flipping a layer's kind cannot
    /// lose it, and so the field decodes with the one `decodeIfPresent` `Effect`'s persistence note
    /// prescribes. `compositingEffect` below is what rendering reads — the kind is what decides
    /// whether this is live, and that decision has one home.
    var effect: Effect? = nil
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

extension Layer {

    /// The grade this layer applies to the backdrop beneath it, or nil if it draws pixels instead —
    /// §4.4's stack-layer wrapper, and the *only* place "is this an effect layer" is decided.
    ///
    /// Both halves are required. A `.compositing` layer with no effect yet is one the artist has just
    /// added and not configured, and it must read as a no-op rather than as a missing grade; an
    /// `effect` left on a layer whose kind has since changed back must not silently start grading the
    /// stack. Rendering asks this, never `kind` or `effect` on their own.
    var compositingEffect: Effect? { kind == .compositing ? effect : nil }
}
