import Foundation

/// The three layer kinds in the app's roadmap (see BUGS.md/README future-enhancements notes).
/// `.raster` (ordinary brush-stroke drawing) and `.vector` (brush strokes/images stored as
/// resolution-independent geometry — move/rotate/scale without quality loss, re-rasterized on
/// demand) are implemented. `.compositing` (a modifier layer applying color grading/transforms to
/// the layer below) is future work; the case exists so adding it needs no further data-model
/// migration.
enum LayerKind: String, Codable, Equatable {
    case raster
    case vector
    case compositing
}
