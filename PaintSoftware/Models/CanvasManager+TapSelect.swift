import CoreGraphics

// MARK: - Select → Tap — TODO (147)
//
// > *"a new select mode which is simple: you just tap on anything and it selects whatever object you
// > tapped on. If it is a text, it instantly opens the edit text menu, vice versa for gradients,
// > brushstrokes/fill shapes, etc."* — owner.
//
// A tap names an object, and everything that reads a selection already reads it through `Selection`
// and the loops it makes (`CanvasManager.lassoLoops(of:in:posedBy:)`), so a tapped object is that
// same value with its one element named (`Selection.element`): Move, Recolour, Size, Opacity, Clear,
// Duplicate, To New Layer, the animation-group edits and the Edit entries act on it exactly as they
// act on a lassoed one.

extension CanvasManager {

    /// **Tap mode's tap: select the topmost object under `point`, and open its editor at once when it
    /// has one.**
    ///
    /// *Which object* is what the artist can see: every visible vector layer is asked, topmost first,
    /// and each is asked about its drawing **as it is shown** — carried by the cel's channels and the
    /// transformation layers above it (`celPoseMaps`), the way a lasso is read (LASSO_MOVE.md §5.27) —
    /// against the drawn shape of each element (`VectorHitTest`): a stroke's inked width, a fill's
    /// path, a text box's or a picture's quad.
    ///
    /// **Any layer, not only the active one** — the owner's *"anything"* — and the object's layer
    /// becomes the active one, since a selection belongs to the cel it was made on and the Select
    /// panel's verbs act on that layer. A pixel layer holds no objects, so a tap on its ink reaches
    /// whatever vector layer is beneath it, or nothing.
    ///
    /// **A tap on nothing clears the selection.** The one thing an empty tap can mean to the mode
    /// whose every tap is about *what is under the finger*, and the gesture that puts a selection
    /// down in every other editor.
    ///
    /// **The kinds with an editor open it** (`editSelectedObject(_:)`, the Select panel's own Edit
    /// entries' door): text its box and panel, a gradient its card. A stroke or a fill with a flat
    /// colour has none, so the Select panel simply stays up with that one object selected, and the
    /// artist's options are its verbs — Edit, Move, Clear.
    ///
    /// - Returns: the kind of editor that opened, for the caller to raise the panel it belongs in
    ///   (`EditableKind.panel`); nil when nothing opened.
    @discardableResult
    func selectObject(at point: CGPoint) -> EditableKind? {
        // The same settling every selection makes: a fill or a shape still hanging over the cel has
        // to be part of its content before something is selected out of it.
        beginCanvasEdit()
        guard let canvasSize, let hit = topmostObject(at: point),
              let outline = VectorHitTest.outline(of: hit.shown) else {
            deselect()
            return nil
        }
        let bounds = outline.boundingBoxOfPath.intersection(CGRect(origin: .zero, size: canvasSize))
        guard !bounds.isNull else {
            deselect()
            return nil
        }
        // Before the selection is written: the active cel changing clears a selection
        // (`handleActiveContextChanged`), so the other order would lose the one just made.
        selectLayer(hit.layerIndex)
        selection = Selection(path: outline, bounds: bounds,
                              layerID: layers[hit.layerIndex].id, celID: layers[hit.layerIndex].cels[hit.celIndex].id,
                              element: hit.shown.id)
        guard let kind = EditableKind(hit.shown), editSelectedObject(kind) else { return nil }
        return kind
    }

    /// The topmost object under `point` across the document, as it is shown, and where it lives.
    ///
    /// The render walk's own order (`leafLayerIndices` is bottom to top, depth first through the
    /// folders), so "topmost" is what the compositor puts on top; a layer a switch or a folder hides
    /// is not asked, and neither is an in-between, whose drawing is derived rather than stored.
    private func topmostObject(at point: CGPoint)
        -> (layerIndex: Int, celIndex: Int, shown: VectorElement)? {
        for index in renderTreeAndPoses(atFrame: currentFrame).tree.leafLayerIndices.reversed() {
            guard layers.indices.contains(index), layers[index].kind == .vector,
                  isLayerEffectivelyVisible(index),
                  let celIndex = activeCelIndex(inLayer: index, atFrame: currentFrame),
                  layers[index].cels[celIndex].interpolation == nil,
                  let vector = layers[index].cels[celIndex].vector else { continue }
            let elements = vector.elements
            let shown = Self.posed(elements, by: celPoseMaps(elements, layerID: layers[index].id,
                                                             celID: layers[index].cels[celIndex].id,
                                                             atFrame: currentFrame))
            if let hit = VectorHitTest.topmost(in: shown, at: point) { return (index, celIndex, hit) }
        }
        return nil
    }
}
