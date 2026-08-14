import Foundation

/// The three layer kinds. `.raster` (ordinary brush-stroke drawing) and `.vector` (brush
/// strokes/images stored as resolution-independent geometry — move/rotate/scale without quality
/// loss, re-rasterized on demand) hold pixels. `.compositing` holds none: it carries `Layer.effect`
/// and grades everything accumulated below it *within its own container*, which is
/// LAYER_COMPOSITING.md §4.4's stack-layer wrapper — Photoshop's adjustment layer. The case was
/// reserved from the start so that arriving needed no data-model migration, and it did not.
enum LayerKind: String, Codable, Equatable {
    case raster
    case vector
    case compositing
}
