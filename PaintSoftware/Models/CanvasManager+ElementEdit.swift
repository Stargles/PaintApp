import Foundation

// MARK: - A live edit of one cel's display list, settled as one undo step
//
// Two panels edit the objects already on a vector cel while the artist watches: the Select panel's
// Colour, Size and Opacity (`SelectionEditSession`, a drag) and the gradient panel
// (`GradientEditSession`, the panel's whole life). They are the same edit in four verbs, written once
// here, and each session adds only what is its own — what the edit rewrites and who decides it changed
// anything:
//
// - **begin** takes the list as the artist found it and names the ids the edit may rewrite;
// - **write** (`writeElementEdit`) puts a rewritten list on the canvas in place, every tick, recording
//   nothing;
// - **commit** (`recordElementEdit`) registers one undo step from the list found to the list let go of;
// - **revert** (`revertElementEdit`) puts the list found back and records nothing — a cancel, and an
//   edit that ended where it began.
//
// **The text session is not one of these, and what differs is real.** Its draft lives in a tier of its
// own (`textRecipe`, `textFrame`) while the object it reopened stays in the list, merely suppressed
// from the flatten, so there is no list to rewrite and no snapshot to take at the start; it can begin
// on a raster layer and bake to pixels, or add an object that was never in the list or remove one; and
// it ends by `VectorCanvas.commitTextEdit` rather than by a write. What it shares is the commit's last
// step, `registerVectorElementsUndo`, which already is the one door every whole-list undo goes through.

/// **What one live edit of a cel's display list holds from the first write to its end** — the cel it
/// is on, the list as the artist found it, and the ids it may rewrite.
struct ElementEditSession {
    let layerID: UUID
    let celID: UUID
    let vectorCanvas: VectorCanvas
    /// The display list as the artist found it — what a revert puts back and the undo step's old side.
    let elementsBefore: [VectorElement]
    /// The ids a write may rewrite — `ElementSwap.rewritesInPlace`'s operand, over-declared on purpose:
    /// an id here that did not change costs its own footprint of repair, an id left out that did is a
    /// wrong picture.
    let rewriting: Set<UUID>
    /// Whether any write has reached the canvas. False for a panel opened and closed untouched, which
    /// ends with no render and no step.
    var applied = false
}

extension CanvasManager {

    /// The edit's cel takes `elements` in place, and **nothing is recorded**. The seam is told the
    /// ids, so the repair is bounded by where each rewritten object was and will be rather than
    /// falling to the whole cel (`VectorCanvas.restoreElements(_:changedInk:rewriting:)`,
    /// PERFORMANCE.md §11.11f) — which is what lets a slider drive it.
    func writeElementEdit(_ elements: [VectorElement], on edit: ElementEditSession) {
        edit.vectorCanvas.restoreElements(elements, changedInk: nil, rewriting: edit.rewriting)
        celContentChangedOutsideStroke(layerID: edit.layerID, celID: edit.celID)
    }

    /// Closes the edit as **one undo step** from the list the artist found to `finalElements`, the list
    /// they let go of — whatever the edit wrote in between.
    func recordElementEdit(_ edit: ElementEditSession, finalElements: [VectorElement],
                           label: HistoryActionLabel) {
        registerVectorElementsUndo(vectorCanvas: edit.vectorCanvas,
                                   oldElements: edit.elementsBefore, newElements: finalElements,
                                   layerID: edit.layerID, celID: edit.celID, label: label,
                                   swap: .rewritesInPlace(edit.rewriting))
        // The layer-panel thumbnail is a third thing, and `registerVectorElementsUndo` refreshes it
        // on the undo and redo sides but not on the initial apply.
        celContentChangedOutsideStroke(layerID: edit.layerID, celID: edit.celID)
    }

    /// Puts the list the artist found back and **records nothing**.
    func revertElementEdit(_ edit: ElementEditSession) {
        writeElementEdit(edit.elementsBefore, on: edit)
    }
}
