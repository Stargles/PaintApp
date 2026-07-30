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
    /// soft edges and `< 1` opacity all reproduce, via the hybrid geometric-split/alpha-punch
    /// resolution in plan §1.
    ///
    /// **Phase 2 status:** the hybrid resolution is Phase 4. Until then this routes to the same
    /// geometry as `.cutPoints`, which is strictly better than the pre-Phase-2 behaviour it replaces
    /// (exact cut boundaries instead of whole-sample deletion) but still cannot shave a side off a
    /// stroke or leave a soft edge. `VectorEraser.resolve` is the single place that decides this, so
    /// Phase 4 changes one branch.
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
