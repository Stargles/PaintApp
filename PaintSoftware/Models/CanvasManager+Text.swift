import Combine   // objectWillChange.send()
import SwiftUI   // the toolbar swatch's Color
import UIKit

// MARK: - Text (interactive: place a box, type into it, bake it on the next canvas edit)
//
// The `CanvasManager` side of `ADD_TEXT.md` stage 1. The session's stored properties live on the
// class itself (see `CanvasManager.swift`'s header — extensions cannot declare them); the layout and
// the rasterizer live in `Engine/TextLayout.swift`; the editor is `Views/TextOverlayView.swift`.
//
// **Stage 3 added the vector half, and the branch is where stage 1 said it would be**: in
// `commitInteractiveText`, plus the one in `beginTextSession` that re-opens an object already on the
// layer instead of placing a new one over it. Everything between those two — typing, the panel's
// sliders, dragging the box — is identical for both destinations, because the draft tier is the same
// draft tier and `TextLayout` is the same rasterizer. On a raster layer the session bakes to pixels;
// on a vector layer it lands as a `VectorTextElement` in the display list and stays editable forever.

extension CanvasManager {

    /// True when a box exists and nothing is dragging it — the state the settings panel's sliders
    /// are for. `isShapeInAdjustableState`'s twin, and named the same way for the same reason.
    var isTextInAdjustableState: Bool { textGestureActive && !textFingerDown }

    /// What the top toolbar's colour swatch shows and its picker panel edits.
    ///
    /// The brush's colour, except while a text session is live — then it is that text's, because
    /// that is what the artist has in front of them. `ADD_TEXT.md` §1 makes the *bake* half of this
    /// explicit ("picking a colour for your text bakes the text you were about to recolour", which
    /// `TopToolbar.toggle` now guards); this is the other half, and without it the guard buys a
    /// panel that no longer bakes and still edits the wrong colour.
    ///
    /// A computed property with a setter rather than a `Binding` built at the call site, so the
    /// toolbar's swatch and the panel behind it cannot come to disagree about which colour they are
    /// showing — and so `$canvasManager.activeEditColor` is the whole of the view-side change.
    var activeEditColor: Color {
        get {
            guard textGestureActive else { return brushColor }
            return Color(textRecipe.color.uiColor)
        }
        set {
            guard textGestureActive else {
                brushColor = newValue
                return
            }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
            newValue.resolvedUIColor(opacity: 1).getRed(&r, green: &g, blue: &b, alpha: &a)
            textRecipe.color = CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
            textRecipeDidChange()
        }
    }

    /// The text tool's placement tap. Puts an empty box at `canvasPoint` on the active cel — **or, on
    /// a vector layer, re-opens the text object already sitting under the tap.**
    ///
    /// **`beginCanvasEdit()` first**, exactly as `beginInteractiveShape` and `beginInteractiveFill`
    /// do: placing a new box is a canvas edit, so whatever was still pending — including a previous
    /// text session — bakes before this one starts. Only one draft is tracked at a time, so tapping
    /// away to start a second box is what commits the first, which is also the gesture an artist
    /// expects from every other editor.
    ///
    /// The tap is the box's *top-left*, not its centre. An empty box has no measured extent to
    /// centre on, and growing rightward-and-downward from the point touched is what the caret
    /// appearing under the finger looks like.
    func beginTextSession(at canvasPoint: CGPoint) {
        beginCanvasEdit()
        guard layers.indices.contains(currentLayerIndex) else { return }
        guard Tool.textUnavailableReason(onLayerOfKind: activeLayerKind) == nil else { return }
        let layerIndex = currentLayerIndex
        guard let celIndex = activeCelIndex(inLayer: layerIndex, atFrame: currentFrame) else { return }

        let layerID = layers[layerIndex].id
        let celID = layers[layerIndex].cels[celIndex].id
        textGestureLayerID = layerID
        textGestureCelID = celID
        textEditingElementID = nil

        // **The whole point of stage 3**: on a vector layer the object is still there, so a tap on it
        // reopens the same object rather than dropping a second one on top. `topmostText` hits the
        // *box*, not the glyphs — tapping the hole in an "O" is tapping the text.
        if layers[layerIndex].kind == .vector,
           let vectorCanvas = layers[layerIndex].cels[celIndex].vector,
           let existing = vectorCanvas.topmostText(atCanvasPoint: canvasPoint) {
            let draft = vectorCanvas.canvasText(fromLocal: existing)
            textRecipe = draft.recipe
            textFrame = draft.frame
            textEditingElementID = existing.id
            // Suppressed from the flatten, never lifted out of the array — `ADD_TEXT.md` §1/§2, and
            // this assignment is the session's **first and only** invalidation until it commits.
            vectorCanvas.editingElementID = existing.id
            textFontSubstitution = TextLayout.resolvedFont(for: textRecipe).substitution
            textGestureActive = true
            textFingerDown = false
            textIsFocused = false
            celContentChangedOutsideStroke(layerID: layerID, celID: celID)
            refreshUndoRedoState()
            return
        }

        // The recipe carries over from the previous session — font, size, tracking, colour. An
        // artist labelling six things in a row sets the type once, which is what every other tool in
        // this app does with its settings and what the panel's sliders would otherwise mean nothing
        // for on the second box. Only the string is cleared.
        textRecipe.string = ""
        let resolution = TextLayout.resolvedFont(for: textRecipe)
        textFontSubstitution = resolution.substitution
        let emptyHeight = resolution.font.lineHeight
        textFrame = TextFrame(origin: canvasPoint,
                              size: CGSize(width: TextLayout.minimumBoxWidth, height: emptyHeight),
                              autoSize: true)
        textGestureActive = true
        textFingerDown = false
        textIsFocused = false
        objectWillChange.send()
        refreshUndoRedoState()
    }

    /// The string changed — the overlay's `textViewDidChange`, coalesced to one call per frame by
    /// the overlay itself (`ADD_TEXT.md` §4 rule 3).
    ///
    /// Re-measures and regrows the box while `autoSize` is set. A box the artist has sized is
    /// authoritative and keeps its size: text wraps inside it and anything past the bottom is hidden
    /// until they enlarge it (§5.3, "overflow clips"). Stage 1 has no handles, so nothing clears
    /// `autoSize` yet and every Stage 1 box grows — the branch is here because Stage 4 turns it on,
    /// not because Stage 1 exercises it.
    func updateTextString(_ string: String) {
        guard textGestureActive, textRecipe.string != string else { return }
        textRecipe.string = string
        regrowTextFrameIfAutoSizing()
        objectWillChange.send()
    }

    /// A settings-panel change landed on `textRecipe` directly (its sliders bind to it). Re-resolves
    /// the font — a family change can substitute — and regrows the box, since a bigger point size on
    /// a pristine box is exactly as much a re-layout as a longer string.
    func textRecipeDidChange() {
        guard textGestureActive else {
            // No live box: still resolve, so the panel can warn about a missing family before the
            // artist has placed anything.
            textFontSubstitution = TextLayout.resolvedFont(for: textRecipe).substitution
            return
        }
        textFontSubstitution = TextLayout.resolvedFont(for: textRecipe).substitution
        regrowTextFrameIfAutoSizing()
        objectWillChange.send()
    }

    private func regrowTextFrameIfAutoSizing() {
        guard textFrame.autoSize, let canvasSize else { return }
        let font = TextLayout.resolvedFont(for: textRecipe).font
        let origin = textFrame[.topLeft]
        let measured = TextLayout.autoSize(for: textRecipe, font: font, originX: origin.x,
                                           canvasSize: canvasSize)
        textFrame = textFrame.resized(to: measured)
    }

    // MARK: Moving the box

    /// Touch-down on the box's move band. Latches nothing beyond the flag — the overlay measures its
    /// own drag delta in canvas space and hands whole positions to `dragTextFrame`, so a mid-drag
    /// pinch-zoom cannot move the reference frame under the gesture.
    func beginTextFrameDrag() {
        guard textGestureActive else { return }
        textFingerDown = true
        refreshUndoRedoState()
    }

    /// Moves the box's top-left to `origin` in canvas space.
    func dragTextFrame(toOrigin origin: CGPoint) {
        guard textGestureActive else { return }
        let current = textFrame[.topLeft]
        textFrame = textFrame.moved(by: CGVector(dx: origin.x - current.x, dy: origin.y - current.y))
        objectWillChange.send()
    }

    /// The finger came off the box. Stays adjustable — this is not a commit, for the same reason
    /// `endInteractiveShape` is not one.
    ///
    /// Re-runs the auto-size measurement, because the cap `TextLayout.autoSize` applies is measured
    /// from the box's *origin*: dragging a wide box left gives it more room, and it should take it.
    func endTextFrameDrag() {
        guard textGestureActive, textFingerDown else { return }
        textFingerDown = false
        regrowTextFrameIfAutoSizing()
        objectWillChange.send()
        refreshUndoRedoState()
    }

    // MARK: Committing

    /// Bakes the draft into the target cel's raster and registers one undo step for the whole
    /// session.
    ///
    /// **Landing the pixels is `registerUndoableCelChange`, not a private stamp helper.** That
    /// primitive is already tool-agnostic across Fill, Shape, Move, Duplicate and both selection
    /// operations; it wraps the result via `bakedRasterTexture(image:likeExisting:)` into
    /// `Cel.raster` and never `bakedImage` — the ghost-layer bug its own doc comment records —
    /// applies by resolved layer/cel *ID* rather than index, and registers one atomic step.
    ///
    /// Self-guards when nothing is pending, like `commitInteractiveFill` and
    /// `commitInteractiveShape`, because `beginCanvasEdit()` calls it unconditionally on every
    /// canvas edit in the app.
    ///
    /// An empty box commits nothing and leaves no undo step. Placing a box and tapping away without
    /// typing has changed nothing about the drawing, so an "Undo add text" that removes nothing
    /// would be a step the artist has to press through to get back to real work.
    func commitInteractiveText() {
        guard textGestureActive else { return }
        textGestureActive = false
        textFingerDown = false
        textIsFocused = false
        let recipe = textRecipe
        let frame = textFrame
        let layerID = textGestureLayerID
        let celID = textGestureCelID
        let editingID = textEditingElementID
        defer {
            textGestureLayerID = nil
            textGestureCelID = nil
            textEditingElementID = nil
            objectWillChange.send()
            refreshUndoRedoState()
        }
        guard let layerID, let celID, let canvasSize,
              let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
              let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) else { return }

        // **The layer's kind decides the destination outright**, exactly as `commitInteractiveFill`'s
        // does and for the same reason: the two tiers are invisible to each other's renderer, so
        // there is no fallback between them. A vector layer keeps a real element; a raster layer
        // gets pixels.
        if layers[layerIndex].kind == .vector {
            commitTextToVector(recipe: recipe, frame: frame, editingID: editingID,
                               layerIndex: layerIndex, celIndex: celIndex, layerID: layerID, celID: celID)
            return
        }

        guard !recipe.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let glyphs = TextLayout.render(recipe: recipe, frame: frame, canvasSize: canvasSize) else { return }

        let cel = layers[layerIndex].cels[celIndex]
        // One canvas-sized flatten, one composite, once — `ADD_TEXT.md` §4 rule 7, and the same
        // shape and cost as a fill commit, which is already accepted.
        let base = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
        let composited = PixelOps.compositeOver(base: base, overlay: glyphs)
        registerUndoableCelChange(layerID: layerID, celID: celID,
                                  oldRaster: cel.raster, oldBaked: cel.bakedImage, oldFill: cel.fillImage,
                                  newRaster: bakedRasterTexture(image: composited, likeExisting: cel.raster),
                                  newBaked: nil, newFill: nil, label: .addText)
        // The bake never goes through `strokeEnded`, so the layer panel keeps showing the cel as it
        // was unless the thumbnail is refreshed here — `commitInteractiveShape`'s reason, verbatim.
        scheduleThumbnailRegen(layerID: layerID, celID: celID)
    }

    /// The vector arm of the commit: the draft becomes a real element in the cel's display list,
    /// upserted **at its own index** so a re-edit cannot change what the object is in front of.
    ///
    /// One undo step for the whole session, whatever happened inside it — retyping, restyling,
    /// dragging the box, or deleting every character (which removes the object). Not one per
    /// keystroke: `UndoHistory`'s `cost` accounting was never sized for 200 entries out of one
    /// sentence, and `UITextView` supplies within-session undo for free (`ADD_TEXT.md` §2, §5.1).
    ///
    /// A session that placed a box and typed nothing registers nothing at all — the same rule the
    /// raster bake follows, and for the same reason: an "undo add text" that removes nothing is a
    /// step the artist has to press through to reach real work.
    private func commitTextToVector(recipe: TextRecipe, frame: TextFrame, editingID: UUID?,
                                    layerIndex: Int, celIndex: Int, layerID: UUID, celID: UUID) {
        // A vector layer's cel should always have a `VectorCanvas`, but a text object landing in the
        // cel's raster would paint into a buffer a vector layer never displays — i.e. it would
        // silently vanish. Materialise one instead. `commitInteractiveShape`'s reasoning, verbatim.
        if layers[layerIndex].cels[celIndex].vector == nil, let canvasSize {
            layers[layerIndex].cels[celIndex].vector = .empty(size: canvasSize)
        }
        guard let vectorCanvas = layers[layerIndex].cels[celIndex].vector else { return }

        let before = vectorCanvas.elements
        let isBlank = recipe.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let element: VectorTextElement? = isBlank ? nil
            : vectorCanvas.localText(fromCanvas: VectorTextElement(id: editingID ?? UUID(),
                                                                   recipe: recipe, frame: frame))
        // One call, so un-suppressing and applying are one invalidation — the session's second and
        // last (`ADD_TEXT.md` §4 rule 4).
        let changed = vectorCanvas.commitTextEdit(editingID: editingID, element: element)
        guard changed else { return }

        registerVectorTextUndo(vectorCanvas: vectorCanvas, oldElements: before,
                               newElements: vectorCanvas.elements, layerID: layerID, celID: celID,
                               label: editingID == nil ? .addText : .editText)
        // Committing never goes through `strokeEnded`, so the layer panel keeps showing the cel as
        // it was unless the thumbnail is refreshed here — `commitInteractiveShape`'s reason, verbatim.
        scheduleThumbnailRegen(layerID: layerID, celID: celID)
    }

    /// `registerVectorFillUndo`'s twin, with one deliberate difference: it swaps the **whole
    /// `elements` array** rather than one kind-filtered bucket.
    ///
    /// The kind-filtered setters gather every element of their kind back at the first one's index, so
    /// a get→set round trip over a list where text is interleaved with strokes is order-stable only
    /// for the bucket as a whole. Text *is* interleaved by construction — `upsertText` appends a new
    /// object above whatever strokes are already there — so an undo through `texts` could quietly
    /// move an object's z-position. The whole-array swap has nothing to reconstruct.
    ///
    /// Coarse-grained is what every other element kind already does; this adds no new undo machinery,
    /// only a wider slice of the same one.
    func registerVectorTextUndo(vectorCanvas: VectorCanvas,
                                oldElements: [VectorElement], newElements: [VectorElement],
                                layerID: UUID, celID: UUID, label: HistoryActionLabel) {
        let cost = (oldElements.count + newElements.count) * 512
        recordUndo(label: label, cost: cost, undo: { [weak self] in
            vectorCanvas.elements = oldElements
            vectorCanvas.bumpVersion()
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        }, redo: { [weak self] in
            vectorCanvas.elements = newElements
            vectorCanvas.bumpVersion()
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        })
    }

    /// Throws the draft away without baking. The first arm of
    /// `finalizePendingGesturesForHistoryAction`'s three-way branch — a box under the finger when
    /// undo is pressed is discarded, exactly as a fill or a shape under the finger is.
    ///
    /// **A re-edit that is cancelled puts the object back**, which is the half a raster session has
    /// no equivalent of: the element never left the display list, so all that is owed is clearing the
    /// suppression. Doing it here rather than leaving it to the commit is what stops an undo pressed
    /// mid-edit leaving a committed object permanently invisible.
    func cancelInteractiveText() {
        guard textGestureActive else { return }
        textGestureActive = false
        textFingerDown = false
        textIsFocused = false
        if let layerID = textGestureLayerID, let celID = textGestureCelID,
           textEditingElementID != nil,
           let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
           let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }),
           let vectorCanvas = layers[layerIndex].cels[celIndex].vector {
            vectorCanvas.editingElementID = nil
            celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        }
        textEditingElementID = nil
        textGestureLayerID = nil
        textGestureCelID = nil
        objectWillChange.send()
        refreshUndoRedoState()
    }
}
