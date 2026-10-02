import CoreGraphics
import Foundation

// MARK: - Select → Tap — TODO (147)
//
// > *"a new select mode which is simple: you just tap on anything and it selects whatever object you
// > tapped on. If it is a text, it instantly opens the edit text menu, vice versa for gradients,
// > brushstrokes/fill shapes, etc."* — owner.
//
// A tap names an object, and everything that reads a selection already reads it through `Selection`
// and the loops it makes (`CanvasManager.lassoLoops(of:in:posedBy:)`), so tapped objects are that
// same value with their elements named (`Selection.elements`): Move, Recolour, Size, Opacity, Clear,
// Duplicate, To New Layer, the animation-group edits and the Edit entries act on them exactly as they
// act on a lassoed region.
//
// **How a tap meets what is already selected is the artist's choice** (`TapComposition`, the Select
// panel's picker): Single replaces, Add joins, Subtract leaves. Every rule ends in the one builder,
// `tappedSelection`, which makes the selection out of the set of objects it is to hold — so a set that
// grew by Add and a set that shrank by Subtract are drawn and answered for exactly as a single tap is.

extension CanvasManager {

    /// **Tap mode's tap, under the rule the Select panel's picker has chosen** (`tapComposition`).
    ///
    /// *Which object* is what the artist can see: every visible vector layer is asked, topmost first,
    /// and each is asked about its drawing **as it is shown** — carried by the cel's channels and the
    /// transformation layers above it (`celPoseMaps`), the way a lasso is read (LASSO_MOVE.md §5.27) —
    /// against the drawn shape of each element (`VectorHitTest`): a stroke's inked width, a fill's
    /// path, a text box's or a picture's quad.
    ///
    /// - **Single** — the object under the tap is the whole selection, and **the kinds with an editor
    ///   open it at once** (`editSelectedObject(_:)`, the Select panel's own Edit entries' door): text
    ///   its box and panel, a gradient its card. A stroke or a fill with a flat colour has none, so the
    ///   Select panel simply stays up with that one object selected. **A tap on nothing clears the
    ///   selection** — the gesture that puts a selection down in every other editor.
    /// - **Add** — the object joins the tapped objects already selected on its cel. It opens no editor:
    ///   the artist is building a set, and the Select panel's Edit entries are one tap away for the
    ///   kind it holds. A tap on nothing changes nothing, since a miss must not cost a set that took
    ///   several taps to build.
    /// - **Subtract** — the *selected* object under the tap leaves the set, asked of the selected
    ///   objects alone so an unselected one lying over it does not shield it. A set emptied is a
    ///   deselect. With no tapped set to take from it says so (`CanvasNotice.nothingTappedToSubtractFrom`)
    ///   rather than doing nothing.
    ///
    /// **Any layer, not only the active one** — the owner's *"anything"* — and the object's layer
    /// becomes the active one, since a selection belongs to the cel it was made on and the Select
    /// panel's verbs act on that layer. A pixel layer holds no objects, so a tap on its ink reaches
    /// whatever vector layer is beneath it, or nothing. **An Add on another cel starts a new set there**:
    /// one selection holds objects of one cel, and walking to another cel has always put the selection
    /// down (`handleActiveContextChanged`).
    ///
    /// **Tapped objects and a drawn loop do not combine**, since a set is not a region: a loop drawn over
    /// a tapped set replaces it (`finishSelection`) and an Add over a loop's region starts a set.
    ///
    /// - Returns: the kind of editor that opened, for the caller to raise the panel it belongs in
    ///   (`EditableKind.panel`); nil when nothing opened.
    @discardableResult
    func selectObject(at point: CGPoint) -> EditableKind? {
        // The same settling every selection makes: a fill or a shape still hanging over the cel has
        // to be part of its content before something is selected out of it.
        beginCanvasEdit()
        switch tapComposition {
        case .single:
            guard let hit = topmostObject(at: point), selectTapped(.single, hit) else {
                deselect()
                return nil
            }
            guard let kind = EditableKind(hit.shown), editSelectedObject(kind) else { return nil }
            return kind
        case .add:
            if let hit = topmostObject(at: point) { selectTapped(.add, hit) }
            return nil
        case .subtract:
            guard let held = selection?.elements, let cel = tappedSelectionCel else {
                raise(.nothingTappedToSubtractFrom)
                return nil
            }
            let shown = shownElements(layerIndex: cel.layerIndex, celIndex: cel.celIndex)
            if let hit = VectorHitTest.topmost(in: shown.filter { held.contains($0.id) }, at: point) {
                selectTapped(.subtract, (cel.layerIndex, cel.celIndex, hit))
            }
            return nil
        }
    }

    /// Puts `tapped` through `rule` against the objects already selected on its cel and writes the
    /// selection that is left — nothing selected when the set is empty. False when it is.
    @discardableResult
    private func selectTapped(_ rule: TapComposition,
                              _ tapped: (layerIndex: Int, celIndex: Int, shown: VectorElement)) -> Bool {
        let layer = layers[tapped.layerIndex]
        let held: Set<UUID>
        if let selection, selection.layerID == layer.id, selection.celID == layer.cels[tapped.celIndex].id {
            held = selection.elements ?? []
        } else {
            held = []
        }
        // Before the selection is written: the active cel changing clears a selection
        // (`handleActiveContextChanged`), so the other order would lose the one just made.
        selectLayer(tapped.layerIndex)
        guard let made = tappedSelection(rule.result(of: tapped.shown.id, onto: held),
                                         layerIndex: tapped.layerIndex, celIndex: tapped.celIndex) else {
            deselect()
            return false
        }
        selection = made
        return true
    }

    /// **The selection that holds exactly `ids` on one cel**, drawn as the union of their outlines —
    /// the one builder every tap rule ends in. Each object is asked as it is *shown*, so the outline is
    /// where the artist sees it. Nil when none of them has an outline to hold (an eraser mark has none,
    /// and an id whose object has since gone has nothing) or the union is off the paper.
    private func tappedSelection(_ ids: Set<UUID>, layerIndex: Int, celIndex: Int) -> Selection? {
        guard let canvasSize else { return nil }
        let rule = VectorCanvas.lassoFillRule
        let outlined = shownElements(layerIndex: layerIndex, celIndex: celIndex)
            .filter { ids.contains($0.id) }
            .compactMap { element in VectorHitTest.outline(of: element).map { (element.id, $0.normalized(using: rule)) } }
        guard let first = outlined.first else { return nil }
        let union = outlined.dropFirst().reduce(first.1) { $0.union($1.1, using: rule) }
        let bounds = union.boundingBoxOfPath.intersection(CGRect(origin: .zero, size: canvasSize))
        guard !bounds.isNull else { return nil }
        let layer = layers[layerIndex]
        return Selection(path: union, bounds: bounds, layerID: layer.id, celID: layer.cels[celIndex].id,
                         elements: Set(outlined.map(\.0)))
    }

    /// Where the tapped selection's cel is now, or nil when the selection is not one or its cel is gone.
    private var tappedSelectionCel: (layerIndex: Int, celIndex: Int)? {
        guard let selection, selection.elements != nil,
              let layerIndex = layers.firstIndex(where: { $0.id == selection.layerID }),
              let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == selection.celID })
        else { return nil }
        return (layerIndex, celIndex)
    }

    /// Everything the cel's drawing shows, as it is shown: its elements carried by the channels of the
    /// cel and the transformation layers above it.
    private func shownElements(layerIndex: Int, celIndex: Int) -> [VectorElement] {
        guard let vector = layers[layerIndex].cels[celIndex].vector else { return [] }
        let elements = vector.elements
        return Self.posed(elements, by: celPoseMaps(elements, layerID: layers[layerIndex].id,
                                                    celID: layers[layerIndex].cels[celIndex].id,
                                                    atFrame: currentFrame))
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
                  layers[index].cels[celIndex].interpolation == nil else { continue }
            if let hit = VectorHitTest.topmost(in: shownElements(layerIndex: index, celIndex: celIndex), at: point) {
                return (index, celIndex, hit)
            }
        }
        return nil
    }
}
