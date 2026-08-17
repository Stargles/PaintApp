import Foundation

/// `CaseIterable` exists for `ToolLogicTests`, which walks every case and asserts its
/// `paintsOnCanvas` answer is *stated* rather than inherited. See that property for why the
/// enumeration is the point.
enum Tool: Hashable, CaseIterable {
    case pen
    case pencil
    case eraser
    case fill
    /// Tap the canvas to take the colour under the tap as the brush colour. A *tool* rather than a
    /// swatch that opens a picker — the owner's wording, 2026-08-17.
    ///
    /// **It is momentary: picking reverts to whichever tool was selected before it.** See
    /// `CanvasManager.selectEyedropper`. Unlike every other case here, the artist reaches for this one
    /// in the middle of doing something else — they want a colour *so that* they can carry on
    /// painting with it, and the pick is complete in a single tap with nothing left to adjust. Left
    /// selected, the next canvas touch would re-pick instead of paint, which is never what the tap
    /// was for.
    case eyedropper
}

extension Tool {
    /// Whether a canvas touch made with this tool selected belongs to the active layer's own
    /// drawing surface. `CanvasView.reconcileLayers`' `shouldInteract` is the caller of record: it
    /// is what decides whether that layer's host view — and the `StrokeGestureRecognizer` inside it
    /// — accepts touches at all, and `false` here is what lets the touch fall through to the
    /// container, where the tool's own recognizer is waiting. `handleCatchAllTap` asks the same
    /// question for the other half of that arrangement.
    ///
    /// **`false` does not mean "does nothing on the canvas".** Both false cases act on a canvas
    /// touch; they act on it through a `TouchTypePressRecognizer` mounted on the *container*
    /// (`fillTapRecognizer`, `eyedropperTapRecognizer`), and the active layer declining the touch is
    /// a precondition for theirs ever seeing it — the host fully covers the container, so an
    /// interactive one swallows the touch via `UIView`'s default hit-test. The question is "whose
    /// recognizer is this touch for", not "does anything happen".
    ///
    /// **Exhaustive, with no `default:`, and that is the whole reason it is a property rather than a
    /// list of exclusions written into the predicate.** It was a list, spelled `selectedTool !=
    /// .fill`, and adding `.eyedropper` to the enum did not add it to the list: the owner reported
    /// on 2026-08-17 that the eyedropper picked the colour *and* painted a stroke with the same tap,
    /// because the host stayed interactive and the touch reached both recognizers. A tool added
    /// after this cannot repeat that — it will not compile until it says which side it is on.
    var paintsOnCanvas: Bool {
        switch self {
        case .pen, .pencil, .eraser:
            // The eraser included: it is a stroke like any other, `.destinationOut` on a raster
            // layer and a real gesture on a vector one, and it goes through the same recognizer.
            return true
        case .fill, .eyedropper:
            return false
        }
    }
}

/// How the eraser behaves on a `.vector` layer. Modelled on Clip Studio Paint's three vector-eraser
/// modes. Raster layers ignore this entirely — there the eraser stays a `.destinationOut` brush.
///
/// Lives here rather than in `Engine/` because it is a *tool* setting owned by `CanvasManager`,
/// persisted in `ProjectManifest`, and pushed into `StrokeCanvasView` alongside `isEraser`.
enum VectorEraserMode: String, Codable, CaseIterable, Identifiable {
    /// Mode 1 — *erase touched parts*. Indistinguishable from raster erasing: partial-width shaves,
    /// soft edges and `< 1` opacity all reproduce. Retains the eraser's gesture whole as an
    /// `.erase` punch, then removes geometry the punch was going to hide anyway: a stroke covered
    /// end to end is deleted outright; one covered full-width over a stretch is cut into pieces
    /// that keep rendering on the original's dab lattice (`DabLattice` — cutting was unsafe before
    /// that type existed, since a re-stamped piece re-anchors `BrushStamper`'s dab lattice and
    /// lands ink outside the punch). `RasterVectorParityLogicTests` proves the punch is
    /// byte-identical to raster erasing.
    case erase

    /// Mode 2 — deletes the stroke geometry the eraser's footprint covers, cutting at the eraser's
    /// edge. Always a real geometric split: no residue element, no alpha.
    case cutPoints

    /// Mode 3 — removes the span of a stroke between the two nearest crossings with another stroke
    /// in the same cel. A stroke with no crossings at all is deleted whole.
    case cutToIntersection

    var id: String { rawValue }

    /// Label for the segmented control in `EraserSettingsPanel`. Short enough to fit three across.
    var displayName: String {
        switch self {
        case .erase: return "Erase"
        case .cutPoints: return "Cut"
        case .cutToIntersection: return "To Cross"
        }
    }

    /// Whether input for this mode should go through `StrokeStabilizer`. Mode 1 is a brush stroke,
    /// so jitter shows up directly in the erased edge and wants the same smoothing a paint stroke
    /// gets. Modes 2 and 3 are cuts, which belong exactly where the finger went — smoothing would
    /// move the cut away from the aimed line.
    var isStabilized: Bool {
        switch self {
        case .erase: return true
        case .cutPoints, .cutToIntersection: return false
        }
    }
}
