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

    /// **The text tool's tap on the canvas outside any box — one rule, for every box.** A tap while a
    /// box is open ends that session and places nothing; a tap with none open places one
    /// (`beginTextSession(at:)`).
    ///
    /// The rule does not ask how the box came to be open: a box placed a moment ago and a box
    /// re-opened by Select → Edit Text (TODO (116)) are the same session. The owner, on the second:
    /// *"Select a text, click edit text, then click anywhere on the canvas. A new textbox for some
    /// reason comes up … which has entirely no reason to be there."* A tap away from a box is the
    /// artist putting it down, and the next tap is what places the next one.
    func textToolTapped(at canvasPoint: CGPoint) {
        guard !textGestureActive else {
            commitInteractiveText()
            return
        }
        beginTextSession(at: canvasPoint)
    }

    /// Puts an empty box at `canvasPoint` on the active cel — **or, on a vector layer, re-opens the
    /// text object already sitting under the tap.**
    ///
    /// **`beginCanvasEdit()` first**, exactly as `beginInteractiveShape` and `beginInteractiveFill`
    /// do: placing a new box is a canvas edit, so whatever was still pending — a fill or a shape the
    /// artist left adjustable — bakes before this one starts. Only one draft is tracked at a time.
    ///
    /// The tap is the box's *top-left*, not its centre. An empty box has no measured extent to
    /// centre on, and growing rightward-and-downward from the point touched is what the caret
    /// appearing under the finger looks like.
    func beginTextSession(at canvasPoint: CGPoint) {
        guard beginCanvasEdit() else { return }
        guard layers.indices.contains(currentLayerIndex) else { return }
        guard Tool.textUnavailableReason(onLayerOfKind: activeLayerKind) == nil else { return }
        let layerIndex = currentLayerIndex
        guard let celIndex = activeCelIndex(inLayer: layerIndex, atFrame: currentFrame) else { return }

        let layerID = layers[layerIndex].id
        let celID = layers[layerIndex].cels[celIndex].id
        // **The whole point of stage 3**: on a vector layer the object is still there, so a tap on it
        // reopens the same object rather than dropping a second one on top. `topmostText` hits the
        // *box*, not the glyphs — tapping the hole in an "O" is tapping the text. The same per-element
        // maps the render uses carry grouped text to its drawn position before the hit test.
        if layers[layerIndex].kind == .vector,
           let vectorCanvas = layers[layerIndex].cels[celIndex].vector {
            let poses = celPoseMaps(vectorCanvas.elements, layerID: layerID, celID: celID, atFrame: currentFrame)
            if let existing = vectorCanvas.topmostText(atCanvasPoint: canvasPoint, posedBy: poses) {
                _ = reopenText(existing, in: vectorCanvas, layerID: layerID, celID: celID,
                               shownThrough: poses[existing.id])
                return
            }
        }
        bindTextSession(toLayer: layerID, cel: celID, shownThrough: inkPose(forLayerID: layerID))

        // The recipe carries over from the previous session — font, size, tracking, colour. An
        // artist labelling six things in a row sets the type once, which is what every other tool in
        // this app does with its settings and what the panel's sliders would otherwise mean nothing
        // for on the second box. Only the string is cleared.
        textRecipe.string = ""
        let resolution = TextLayout.resolvedFont(for: textRecipe)
        textSettings.fontSubstitution = resolution.substitution
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

    /// **Opens a text object that is already on the active vector cel for editing, by identity** — the
    /// Select tool's Edit Text (TODO (116)), where the artist has lassoed the box and there is no tap
    /// point to hit-test. It is `beginTextSession(at:)`'s re-open branch reached by id: the same
    /// session, the same overlay with its box and grips, the same panel, so typing, restyling and
    /// dragging the box all behave exactly as they do after tapping the text with the text tool.
    ///
    /// - Returns: false when the object is not on the cel under the playhead, or text cannot go on
    ///   this layer — the caller then has nothing to open a panel for.
    @discardableResult
    func beginEditingText(elementID: UUID) -> Bool {
        guard beginCanvasEdit() else { return false }
        guard layers.indices.contains(currentLayerIndex),
              Tool.textUnavailableReason(onLayerOfKind: activeLayerKind) == nil,
              layers[currentLayerIndex].kind == .vector,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              let vectorCanvas = layers[currentLayerIndex].cels[celIndex].vector,
              let existing = vectorCanvas.elements.lazy.compactMap(\.text).first(where: { $0.id == elementID })
        else { return false }
        let layerID = layers[currentLayerIndex].id
        let celID = layers[currentLayerIndex].cels[celIndex].id
        let pose = celPoseMaps([.text(existing)], layerID: layerID, celID: celID, atFrame: currentFrame)[existing.id]
        return reopenText(existing, in: vectorCanvas, layerID: layerID, celID: celID, shownThrough: pose)
    }

    /// Bind the chosen cel and its already-resolved session pose, with no object or handle held.
    private func bindTextSession(toLayer layerID: UUID, cel celID: UUID, shownThrough pose: PoseMap?) {
        textGestureLayerID = layerID
        textGestureCelID = celID
        textGesturePose = pose
        textEditingElementID = nil
        textHandleDrag = nil
    }

    /// The session opening on an object already in the display list. **Suppressed from the flatten,
    /// never lifted out of the array** — `ADD_TEXT.md` §1/§2, and the assignment to `editingElementID`
    /// is the session's **first and only** invalidation until it commits.
    private func reopenText(_ existing: VectorTextElement, in vectorCanvas: VectorCanvas,
                            layerID: UUID, celID: UUID, shownThrough pose: PoseMap?) -> Bool {
        guard let draft = shownText(existing, in: vectorCanvas, through: pose) else {
            raise(.drawingSourceUnavailable); return false
        }
        bindTextSession(toLayer: layerID, cel: celID, shownThrough: pose)
        textRecipe = draft.recipe
        textFrame = draft.frame
        textEditingElementID = existing.id
        vectorCanvas.editingElementID = existing.id
        textSettings.fontSubstitution = TextLayout.resolvedFont(for: textRecipe).substitution
        textGestureActive = true
        textFingerDown = false
        textIsFocused = false
        celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        refreshUndoRedoState()
        return true
    }

    /// A text element shown exactly in render order: its group/cel/container pose in local space,
    /// then the vector canvas's carried transform. Refuse an unrepresentable quad before suppressing.
    private func shownText(_ text: VectorTextElement, in vectorCanvas: VectorCanvas,
                           through pose: PoseMap?) -> VectorTextElement? {
        let posed: VectorTextElement
        if let pose {
            guard let mapped = VectorCanvas.mapping(.text(text), through: pose)?.text else { return nil }
            posed = mapped
        } else { posed = text }
        let shown = vectorCanvas.canvasText(fromLocal: posed)
        return shown.frame.homography == nil ? nil : shown
    }

    /// The string changed — the overlay's `textViewDidChange`, coalesced to one call per frame by
    /// the overlay itself (`ADD_TEXT.md` §4 rule 3).
    ///
    /// Re-measures and regrows the box while `autoSize` is set. A box the artist has sized is
    /// authoritative and keeps its size: text wraps inside it and anything past the bottom is hidden
    /// until they enlarge it (§5.3, "overflow clips"). **Stage 4 is what turns the second branch
    /// on**: the first drag of a resize handle clears `autoSize`, and from that keystroke onwards the
    /// box the artist set is the box the text wraps into.
    ///
    /// A keystroke is the draft's and the box's: the canvas is told (`onHeldPictureMoved`) and nothing
    /// is published over the editor (TODO (179)).
    func updateTextString(_ string: String) {
        guard textGestureActive, textRecipe.string != string else { return }
        textRecipe.string = string
        regrowTextFrameIfAutoSizing()
        onHeldPictureMoved?()
    }

    /// A settings-panel change landed on `textRecipe` directly (its sliders bind to it). Re-resolves
    /// the font — a family change can substitute — and regrows the box, since a bigger point size on
    /// a pristine box is exactly as much a re-layout as a longer string.
    ///
    /// **A tick of a panel control is the panel's and the box's** (TODO (179)): the panel observes
    /// `textSettings`, the canvas is told (`onHeldPictureMoved`) and re-lays the box, whose glyphs are
    /// drawn off the main thread — nothing is published over the editor.
    func textRecipeDidChange() {
        textSettings.fontSubstitution = TextLayout.resolvedFont(for: textRecipe).substitution
        // No live box: resolved all the same, so the panel can warn about a missing family before the
        // artist has placed anything.
        guard textGestureActive else { return }
        regrowTextFrameIfAutoSizing()
        onHeldPictureMoved?()
    }

    /// **No canvas size, and no cap.** Stage 1 measured the room left to the canvas's right edge and
    /// wrapped there, because with no handles a box that grew off-canvas could not be dragged back.
    /// Stage 4 builds the handles, so the box grows to whatever the string measures and the artist
    /// can size it by hand — `TextLayout.autoSize` carries the reasoning.
    ///
    /// `resized(to:)` is rotation-preserving as of stage 4, which is what lets a *turned* pristine
    /// box keep growing as the artist types instead of snapping back to axis-aligned on the next
    /// keystroke.
    private func regrowTextFrameIfAutoSizing() {
        guard textFrame.autoSize else { return }
        let font = TextLayout.resolvedFont(for: textRecipe).font
        textFrame = textFrame.resized(to: TextLayout.autoSize(for: textRecipe, font: font))
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

    /// Moves the box's top-left to `origin` in canvas space — the box's, not the editor's: the canvas
    /// is told (`onHeldPictureMoved`) and nothing is published (TODO (179)).
    func dragTextFrame(toOrigin origin: CGPoint) {
        guard textGestureActive else { return }
        let current = textFrame[.topLeft]
        textFrame = textFrame.moved(by: CGVector(dx: origin.x - current.x, dy: origin.y - current.y))
        onHeldPictureMoved?()
    }

    /// The finger came off the box. Stays adjustable — this is not a commit, for the same reason
    /// `endInteractiveShape` is not one.
    func endTextFrameDrag() {
        guard textGestureActive, textFingerDown else { return }
        textFingerDown = false
        objectWillChange.send()
        refreshUndoRedoState()
    }

    // MARK: Rotating and sizing the box

    /// Touch-down on one of the nine grips (`ADD_TEXT.md` §3 stage 4).
    ///
    /// **The latch is the whole of this method.** `TextFrameDrag` captures the starting quad and the
    /// anchor now, and every delta that follows is measured against *that* — never against the frame
    /// the previous delta produced. Two things fall out, and only the first is obvious: a drag cannot
    /// accumulate rounding, and a second finger arriving mid-drag to pinch-zoom cannot move the
    /// reference frame under the first (§1's stated reason for the latch).
    ///
    /// Returns silently on a frame too degenerate to have axes — a zero-size box has no direction to
    /// size along, and a handle that quietly did nothing would be better than one that produced
    /// NaNs.
    /// **Stage 5 added the second half of the first line.** A corner grip distorts when the panel's
    /// Corners control says so; the four edge grips and the rotation knob never do, in either mode.
    ///
    /// **A distort drag drops the keyboard first**, and that is not tidiness. The moment the quad
    /// stops being a parallelogram the frame becomes `.projective`, and `ADD_TEXT.md` §1's
    /// unwarp-while-typing rule then says the box must spring flat for the caret — which, if the
    /// caret were still live, would happen *underneath the finger*, mid-gesture, with the handle the
    /// artist is holding jumping to a different place. Resigning first makes the rule's precondition
    /// false before the drag can trip it.
    /// **The text-derived floor is latched here too, and once.** The owner's ruling — a box may not
    /// be made smaller than its text unless it is being distorted — needs the *recipe*, which the
    /// pure `TextFrameDrag` does not carry and should not; measuring it at touch-down rather than per
    /// delta keeps ADD_TEXT.md §4 rule 2's promise that a 60 Hz drag runs no layout, and costs
    /// nothing, since the only thing that could change the answer is typing and there is a finger on
    /// a grip. `TextLayout.minimumBoxSize` states which floor each axis gets and what was rejected.
    func beginTextHandleDrag(_ handle: TextFrame.Handle) {
        guard textGestureActive else { return }
        let distort = textCornerMode == .distort && handle.corner != nil
        let font = TextLayout.resolvedFont(for: textRecipe).font
        guard let drag = TextFrameDrag(frame: textFrame, handle: handle, distort: distort,
                                       minimumSize: TextLayout.minimumBoxSize(for: textRecipe,
                                                                              font: font)) else { return }
        if distort, textIsFocused { textFocusResigner?() }
        textHandleDrag = drag
        textFingerDown = true
        refreshUndoRedoState()
    }

    /// A grip moved to `canvasPoint`.
    ///
    /// **No `recordUndo` here, and none per delta** — that is what `ADD_TEXT.md` §1 means by
    /// "`setVectorTransform` is explicitly not the pattern to copy" — that function is gone (TODO
    /// item (12) stage 2) and this is what replaced its shape everywhere. The frame is a pure function of
    /// the latched drag and this one point, so sixty deltas cost sixty struct assignments and
    /// produce exactly the answer one delta to the same place would have.
    /// **Stage 5's clamping lives in the one word `guard`.** `ADD_TEXT.md` §1: a drag that would
    /// fail `isValidQuad` — a corner across the diagonal, a quad squeezed shut, a corner past the
    /// vanishing line — holds the last valid quad rather than being refused outright or rendering
    /// garbage. The handle then feels like it sticks, which the document says plainly is a UX cliff
    /// and the honest one, and which is what the big editors do.
    ///
    /// The last valid quad is `textFrame` itself, because the only thing that ever writes it during a
    /// drag is this line. So "hold it" is "do not write it", and no second copy of the frame has to
    /// be kept in step with the first.
    ///
    /// **One optional, for all nine grips and both modes.** The clamp used to be spelled out here as
    /// an `if drag.isDistort`, which was right while the distort was the only gesture that could
    /// make an invalid quad. It is not: the sizing grips and the knob on a `.projective` frame are
    /// composed through the homography now (`TextFrameDrag.warpedFrame`), so growing a box towards
    /// the vanishing line can be refused too, and it must stick in exactly the same way. Asking one
    /// question keeps the two from drifting apart.
    ///
    /// `snapsRotation` is true while a touch has joined the rotation knob's drag
    /// (`PrecisionDrag`, TODO (151)): the box lands on a round angle.
    func dragTextHandle(to canvasPoint: CGPoint, snapsRotation: Bool = false) {
        guard textGestureActive, let drag = textHandleDrag else { return }
        guard let next = drag.clampedFrame(draggedTo: canvasPoint, snapsRotation: snapsRotation) else { return }
        textFrame = next
        onHeldPictureMoved?()
    }

    /// The finger came off a grip.
    ///
    /// **And it registers nothing on the history stack, which is a departure from stage 4's sketch
    /// and is deliberate.** The sketch said "one `recordUndo` per drag"; a text session already
    /// registers exactly one step for everything that happened inside it — `commitTextToVector`'s own
    /// doc lists "dragging the box" among them — and a second step for the drag would be a *dead*
    /// entry. The path is short enough to state: undo mid-session runs
    /// `finalizePendingGesturesForHistoryAction`, which commits the session and pushes its step, and
    /// `history.undo()` then reverts that. A per-drag step would be left sitting underneath it, and
    /// the next undo would restore a frame into a session that no longer exists — the artist presses
    /// undo and nothing they can see happens. `ADD_TEXT.md` §2's "an undo step that removes nothing
    /// is a step the artist has to press through" is the same objection one level down.
    ///
    /// What the sketch was actually guarding against — a drag spraying a step per delta, the way
    /// the deleted `setVectorTransform`'s caller did — is guarded: `dragTextHandle` records nothing at all, and
    /// `TextTransformLogicTests` pins that sixty deltas and one delta leave the same history depth.
    ///
    /// Re-runs the auto-size measurement, which matters only after a *rotation*: a resize clears
    /// `autoSize`, so the regrow is a no-op there, while a turned pristine box has to go on growing
    /// to fit along its new axes.
    func endTextHandleDrag() {
        guard textHandleDrag != nil else { return }
        textHandleDrag = nil
        textFingerDown = false
        regrowTextFrameIfAutoSizing()
        objectWillChange.send()
        refreshUndoRedoState()
    }

    // MARK: Committing

    /// **The keyboard goes first, and the session's state is read after it has.** `textViewDidEndEditing`
    /// flushes the last keystrokes to the recipe, so the draft the commit bakes is only complete once the
    /// editor has resigned. Resigning here, in the action that ends the session, also keeps it out of the
    /// SwiftUI update pass that hides the overlay.
    private func dropTheKeyboardBeforeTheSessionEnds() {
        guard textIsFocused else { return }
        textFocusResigner?()
    }

    /// What a text session was when it ended: the layer and cel it was placed on, the object a
    /// re-edit reopened (nil for a new box), the captured pose that showed that text, and the draft —
    /// read after the keyboard dropped, so the last keystrokes are in it.
    private struct EndedTextSession {
        let layerID: UUID?
        let celID: UUID?
        let editingID: UUID?
        let pose: PoseMap?
        let recipe: TextRecipe
        let frame: TextFrame
    }

    /// **The one way out of a text session** — `commitInteractiveText` and `cancelInteractiveText`
    /// differ only in what they do with what was typed. Drops the keyboard, takes the gesture down
    /// (before `settle` runs, so a canvas edit inside it cannot commit the session again), forgets the
    /// session's identity, runs `settle` on what it was, then tells observers once it has finished.
    private func endTextSession(settling settle: (EndedTextSession) -> Void) {
        dropTheKeyboardBeforeTheSessionEnds()
        textGestureActive = false
        textFingerDown = false
        textIsFocused = false
        textHandleDrag = nil
        let ended = EndedTextSession(layerID: textGestureLayerID, celID: textGestureCelID,
                                     editingID: textEditingElementID, pose: textGesturePose,
                                     recipe: textRecipe, frame: textFrame)
        textGestureLayerID = nil
        textGestureCelID = nil
        textGesturePose = nil
        textEditingElementID = nil
        defer {
            objectWillChange.send()
            refreshUndoRedoState()
        }
        settle(ended)
    }

    /// Bakes the draft into the target cel's raster and registers one undo step for the whole
    /// session.
    ///
    /// **Landing the pixels is `registerUndoableCelChange`, not a private stamp helper.** That
    /// primitive is already tool-agnostic across Fill, Shape, Move, Duplicate and both selection
    /// operations; it wraps the result via `preparedRasterTexture(source:likeExisting:)` into
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
    @discardableResult
    func commitInteractiveText() -> Bool {
        var staged: [UUID: Cel] = [:]
        guard let commit = prepareInteractiveText(staging: &staged) else { return false }
        commit()
        return true
    }

    /// Read the editor's current text without resigning it. The usual coalesced model delivery may
    /// still be pending, and a later tool's refusal must leave the keyboard and every draft intact.
    func prepareInteractiveText(staging: inout [UUID: Cel]) -> (() -> Void)? {
        guard textGestureActive else { return {} }
        var recipe = textRecipe
        if textIsFocused, let current = textDraftReader?() { recipe.string = current }
        let ended = EndedTextSession(layerID: textGestureLayerID, celID: textGestureCelID,
            editingID: textEditingElementID, pose: textGesturePose, recipe: recipe, frame: textFrame)
        guard let layerID = ended.layerID, let celID = ended.celID,
              let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
              let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }),
              let canvasSize else { raise(.drawingSourceUnavailable); return nil }
        var cel = staging[celID] ?? layers[layerIndex].cels[celIndex]
        let before = cel.vector?.elements ?? []
        let original = ended.editingID.flatMap { id in before.lazy.compactMap(\.text).first { $0.id == id } }
        guard layers[layerIndex].kind != .vector || ended.editingID == nil || original != nil else {
            raise(.drawingSourceUnavailable); return nil
        }
        let unchanged: VectorTextElement?
        if layers[layerIndex].kind == .vector, let original, let vector = cel.vector,
           let prior = shownText(original, in: vector, through: ended.pose),
           ended.recipe == prior.recipe, ended.frame == prior.frame {
            // Compare the untouched draft before measuring it: a render font bound or a display
            // pose is not an edit to the stored layout, mode or auto-size bit.
            unchanged = original
        } else { unchanged = nil }
        let frame = ended.frame.autoSize && unchanged == nil
            ? ended.frame.resized(to: TextLayout.autoSize(
                for: ended.recipe, font: TextLayout.resolvedFont(for: ended.recipe).font))
            : ended.frame
        let bake: () -> Void
        if layers[layerIndex].kind == .vector {
            let prepared = cel.vector?.makeCopy() ?? .empty(size: cel.raster.size)
            // Copy the existing element whole. Recipe and frame are the only editable fields;
            // identity and both group memberships belong to the original object.
            var shown = original ?? VectorTextElement(recipe: ended.recipe, frame: frame)
            shown.recipe = ended.recipe
            shown.frame = frame
            let isBlank = shown.recipe.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let element: VectorTextElement?
            if isBlank {
                element = nil
            } else if let unchanged {
                element = unchanged
            } else {
                let local = prepared.localText(fromCanvas: shown)
                guard let pulled = Self.inLayerSpace(.text(local), shownThrough: ended.pose)?.text,
                      pulled.frame.homography != nil else { raise(.drawingSourceUnavailable); return nil }
                element = pulled
            }
            let changed = prepared.commitTextEdit(editingID: ended.editingID, element: element)
            let elements = prepared.elements
            cel.vector = prepared
            staging[celID] = cel
            bake = { [weak self] in
                guard let self,
                      let layer = self.layers.firstIndex(where: { $0.id == layerID }),
                      let at = self.layers[layer].cels.firstIndex(where: { $0.id == celID }) else { return }
                if self.layers[layer].cels[at].vector == nil { self.layers[layer].cels[at].vector = .empty(size: canvasSize) }
                guard let vector = self.layers[layer].cels[at].vector else { return }
                vector.commitTextEdit(editingID: ended.editingID, element: element)
                guard changed else { return }
                self.registerVectorElementsUndo(vectorCanvas: vector, oldElements: before,
                    newElements: elements, layerID: layerID, celID: celID,
                    label: ended.editingID == nil ? .addText : .editText,
                    swap: ended.editingID.map { element == nil ? .addsAndRemoves(ink: nil) : .rewritesInPlace([$0]) }
                        ?? .addsAndRemoves(ink: nil))
                self.scheduleThumbnailRegen(layerID: layerID, celID: celID)
            }
        } else {
            let shown = VectorTextElement(recipe: ended.recipe, frame: frame)
            guard let drawn = Self.inLayerSpace(.text(shown), shownThrough: ended.pose)?.text else {
                raise(.drawingSourceUnavailable); return nil
            }
            if drawn.recipe.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return { [weak self] in self?.endTextSession { _ in } }
            }
            guard let glyphs = TextLayout.render(recipe: drawn.recipe, frame: drawn.frame, canvasSize: canvasSize),
                  let base = PixelOps.rasterize(cel: cel, canvasSize: canvasSize) else {
                raise(.drawingSourceUnavailable); return nil
            }
            let source: RasterSource
            switch PixelOps.compositeOver(base: base, overlay: glyphs, using: cel.raster.residency) {
            case .success(let prepared): source = prepared
            case .failure: raise(.drawingSourceUnavailable); return nil
            }
            let before = cel
            let raster = preparedRasterTexture(source: source, likeExisting: cel.raster)
            cel.raster = raster
            cel.bakedImage = nil
            staging[celID] = cel
            bake = { [weak self] in
                guard let self else { return }
                self.registerUndoableCelChange(layerID: layerID, celID: celID,
                    oldRaster: before.raster, oldBaked: before.bakedImage,
                    newRaster: raster, newBaked: nil, label: .addText)
                self.scheduleThumbnailRegen(layerID: layerID, celID: celID)
            }
        }
        return { [weak self] in self?.endTextSession { _ in bake() } }
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
        endTextSession { ended in
            guard let layerID = ended.layerID, let celID = ended.celID, ended.editingID != nil,
                  let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
                  let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }),
                  let vectorCanvas = layers[layerIndex].cels[celIndex].vector else { return }
            vectorCanvas.editingElementID = nil
            celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        }
    }
}
