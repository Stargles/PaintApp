import Foundation

enum Tool: Hashable {
    case pen
    case pencil
    case eraser
    case fill
}

/// How the eraser behaves on a `.vector` layer. Modelled on Clip Studio Paint's three vector-eraser
/// modes; see VECTOR_ERASER_PLAN.md §4. Raster layers ignore this entirely — there the eraser is and
/// stays a `.destinationOut` brush.
///
/// Lives here rather than in `Engine/` because it is a *tool* setting: it is owned by
/// `CanvasManager`, persisted in `ProjectManifest`, and pushed into `StrokeCanvasView` alongside
/// `isEraser`. `Tool.swift` is also already a member of both the app and the test target, which the
/// engine-side files that consume this mode need it to be.
enum VectorEraserMode: String, Codable, CaseIterable, Identifiable {
    /// Mode 1 — *erase touched parts*. Indistinguishable from raster erasing: partial-width shaves,
    /// soft edges and `< 1` opacity all reproduce.
    ///
    /// It gets there by retaining the eraser's gesture whole as an `.erase` punch rather than by
    /// cutting geometry: a stroke it covers end to end is deleted outright, and a stroke it only
    /// crosses is left intact under the punch. It never cuts a stroke partway — a cut piece is
    /// re-stamped as a new stroke, which re-anchors `BrushStamper`'s dab lattice and lands ink
    /// outside anything the punch covers. Plan §1 has the measurements; `RasterVectorParityLogicTests`
    /// is the standing proof that the punch is byte-identical to raster erasing.
    case erase

    /// Mode 2 — deletes the stroke geometry the eraser's footprint covers, with the cut landing at
    /// the eraser's edge. Always a real geometric split: no residue element, no alpha.
    case cutPoints

    /// Mode 3 — removes the span of a stroke between the two nearest crossings with another stroke
    /// in the same cel. A stroke with no crossings at all is deleted whole.
    case cutToIntersection

    var id: String { rawValue }

    /// Label for the segmented control in `EraserSettingsPanel`. Short enough to fit three across an
    /// iPad panel; the full behaviour is documented on the cases above.
    var displayName: String {
        switch self {
        case .erase: return "Erase"
        case .cutPoints: return "Cut"
        case .cutToIntersection: return "To Cross"
        }
    }

    /// Whether input for this mode should go through `StrokeStabilizer`.
    ///
    /// Mode 1 is a brush stroke — jitter in the eraser path shows up directly in the erased edge, so
    /// it wants the same smoothing a paint stroke gets. Modes 2 and 3 are cuts, and a cut belongs
    /// exactly where the finger went; smoothing it would move the cut away from the line the user
    /// aimed at. This is the rule that replaces `StrokeCanvasView`'s blanket `isEraser ? raw :
    /// stabilized`. See plan §5.
    var isStabilized: Bool {
        switch self {
        case .erase: return true
        case .cutPoints, .cutToIntersection: return false
        }
    }
}
