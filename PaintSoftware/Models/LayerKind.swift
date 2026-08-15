import Foundation

/// The four layer kinds. `.raster` (ordinary brush-stroke drawing) and `.vector` (brush
/// strokes/images stored as resolution-independent geometry — move/rotate/scale without quality
/// loss, re-rasterized on demand) hold pixels. `.compositing` holds none: it carries `Layer.effect`
/// and grades everything accumulated below it *within its own container*, which is
/// LAYER_COMPOSITING.md §4.4's stack-layer wrapper — Photoshop's adjustment layer. The case was
/// reserved from the start so that arriving needed no data-model migration, and it did not.
///
/// `.value` holds no drawn pixels either: it carries `Layer.fill` and *is* one flat colour across the
/// whole canvas — Photoshop's Solid Colour layer. It exists to be an operand: `Mix(A, B, .multiply)`
/// where A and B are single layers is identical to stacking B over A with Multiply (`RenderTree.swift`
/// says so), so a value layer is the honest answer to "why use a node at all" —
/// `Mix(folder-of-drawings, grey 50%, .multiply)` combines the folder as a unit and *then* halves it,
/// which a flat stack cannot express. It also blends with what is beneath it like any other leaf,
/// which is the flat-background and tint case.
///
/// **Unlike `.compositing`, this case was not reserved**, and that is fine rather than a migration:
/// no document has ever contained the string, so a manifest written before it decodes to `.raster`
/// exactly as it always did. What it does mean is that a `switch` over this enum that predates the
/// case has to say what a value layer does — the compiler finds them, and as of this phase there are
/// none, because every reader asks `kind == .vector` / `layer.valueFill` rather than switching.
enum LayerKind: String, Codable, Equatable {
    case raster
    case vector
    case compositing
    case value
}
