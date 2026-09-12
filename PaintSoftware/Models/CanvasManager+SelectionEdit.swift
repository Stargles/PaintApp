import SwiftUI

// MARK: - The tool, in the model — TODO (42)
//
// > *"i plan to replace the change color of selection into a better tool where you can also change
// > the brush type, size, etc. of the strokes inside the selection. The color changer also shouldnt
// > be the current selected color, but instead show the color picker menu defaulting to the current
// > color. all changes able to be seen live in the drawing."* — owner.
//
// Four arms, one seam. Colour, Size and Opacity are the three controls below; Brush is
// `applyBrushToSelection` (BRUSH.md §2.10), which was the half that shipped first and is one press
// rather than a drag, so it needs none of the session machinery here. Every arm rewrites the elements
// the loop caught **in place, under their own ids**, through `VectorCanvas.restoreElements
// (_:changedInk:rewriting:)` — TODO (41)'s last box, PERFORMANCE.md §11.11f — so one tick costs the
// selection's own rectangle rather than the cel. That is the whole of what makes "seen live" true at
// the owner's density: a whole-cel re-walk was ~142 ms there and 745 ms at 1,000 strokes, and a slider
// driving one was unusable.
//
// **Preview, then commit — a drag is one undo step, and a tick is not.** `beginSelectionEdit` resolves
// the loop once (the pull-back, the split under Cut, the caught set) and records nothing;
// `previewSelectionEdit` rewrites and re-renders on every tick and records nothing; `commitSelectionEdit`
// registers the one step from the list the artist started with to the list they let go of, or puts
// the first list back when the drag ended where it began. `cancelSelectionEdit` puts it back
// unconditionally and is what a cleared selection or an undo press mid-drag reaches. The shape is the
// text session's (`commitTextToVector`: *"one undo step for the whole session, whatever happened
// inside it"*) and the value layer's colour swatch (`valueLayerColour`), which brackets its popover's
// lifetime rather than its writes for exactly this reason.

/// What one of the three controls writes.
///
/// A value rather than three methods, so the session can be asked "did the artist's drag change
/// anything" in one place (`SelectionEditKind.current(of:)`) and the rewrite rule for every element
/// kind lives beside it rather than being copied into a colour arm, a size arm and an opacity arm.
enum SelectionEditValue: Equatable {
    /// The picked colour. **Its alpha is ignored**: only the hue travels and the element's own alpha
    /// stays (owner, 2026-08-28 — a faint stroke stays faint), and the Opacity control beside it is
    /// the one door to that. The picker the Select panel raises is built with `supportsOpacity: false`
    /// so it cannot even show a slider for a channel this discards.
    case color(CodableColor)
    /// An absolute width in canvas points — `VectorStroke.size`, the same number the brush's own
    /// Size slider wrote when the stroke was drawn, on the same 1…50 range. Absolute rather than a
    /// multiplier because the control shows the strokes' *current* size and the artist drags it to a
    /// new one, exactly as the colour swatch shows the current colour; a multiplier would read
    /// "×1.5" beside a Size slider that reads "12 pt", and after one tick the number shown would be
    /// true of no stroke.
    case size(CGFloat)
    /// `VectorStroke.opacity` / `VectorFillElement.opacity` / `TextRecipe.opacity` — the field the
    /// brush's Opacity slider wrote at draw time, 0…1. The colour's own alpha is not touched, for the
    /// reason `.color` gives read the other way round: one control, one field.
    case opacity(Double)

    var kind: SelectionEditKind {
        switch self {
        case .color: return .color
        case .size: return .size
        case .opacity: return .opacity
        }
    }
}

/// Which of the three controls a session belongs to.
enum SelectionEditKind: Equatable {
    case color, size, opacity

    /// The one undo step a drag becomes, named for the artist.
    var label: HistoryActionLabel {
        switch self {
        case .color: return .recolorSelection
        case .size: return .resizeSelectionStrokes
        case .opacity: return .changeSelectionOpacity
        }
    }

    /// **What `element` currently holds for this control, or nil when the control does not reach
    /// this kind of element.** The comparison operand for "did anything change", and the tally
    /// operand for the readout's "most common".
    ///
    /// The per-kind table, and it is the whole of the no-op rule the tests pin:
    ///
    /// | | paint stroke | erase stroke | fill | text | image / video |
    /// |---|---|---|---|---|---|
    /// | Colour | yes | **no** | yes | yes | no |
    /// | Size | yes | yes | no | no | no |
    /// | Opacity | yes | yes | yes | yes | no |
    ///
    /// An `.erase` stroke takes no colour because `.destinationOut` reads only alpha, so recolouring
    /// one changes no pixel and would be an undo step that lies (`applyBrushToSelection`'s doc
    /// carries the same argument for why it *does* re-point one — the hole's shape is visible). It
    /// takes a size and an opacity for that reason: both change the hole. A placed image and a video
    /// frame take nothing from any of the three — neither has a colour field, a width, or an opacity,
    /// and tinting or fading a photograph is an effect (`Effect`), not a recolour.
    func current(of element: VectorElement) -> SelectionEditValue? {
        switch (self, element) {
        case (.color, .stroke(let stroke)):
            return stroke.composite == .paint ? .color(Self.hue(of: stroke.color)) : nil
        case (.color, .fill(let fill)):
            return .color(Self.hue(of: fill.color))
        case (.color, .text(let text)):
            return .color(Self.hue(of: text.recipe.color))
        case (.size, .stroke(let stroke)):
            return .size(stroke.size)
        case (.opacity, .stroke(let stroke)):
            return .opacity(stroke.opacity)
        case (.opacity, .fill(let fill)):
            return .opacity(fill.opacity)
        case (.opacity, .text(let text)):
            return .opacity(text.recipe.opacity)
        case (.color, .image), (.color, .video),
             (.size, .fill), (.size, .text), (.size, .image), (.size, .video),
             (.opacity, .image), (.opacity, .video):
            return nil
        }
    }

    /// `element` with this control's field set to `value`, or nil when the control does not reach
    /// this kind — the same table as `current(of:)`, written from the other side.
    ///
    /// **Replace the field and touch nothing else.** `recolorSelection` established the pattern for
    /// colour — keep `existing.alpha`, write the RGB triple — and the two newer arms follow it: a
    /// size write leaves the samples, the lattice and the brush alone, which is also what lets
    /// `VectorCanvas.rewrittenInk` bound the new half off the stroke's centre line at the new width
    /// rather than falling to the cel.
    static func rewritten(_ element: VectorElement, to value: SelectionEditValue) -> VectorElement? {
        switch (value, element) {
        case (.color(let picked), .stroke(var stroke)):
            guard stroke.composite == .paint else { return nil }
            stroke.color = Self.recoloured(stroke.color, to: picked)
            return .stroke(stroke)
        case (.color(let picked), .fill(var fill)):
            fill.color = Self.recoloured(fill.color, to: picked)
            return .fill(fill)
        case (.color(let picked), .text(var text)):
            text.recipe.color = Self.recoloured(text.recipe.color, to: picked)
            return .text(text)
        case (.size(let size), .stroke(var stroke)):
            stroke.size = size
            return .stroke(stroke)
        case (.opacity(let opacity), .stroke(var stroke)):
            stroke.opacity = opacity
            return .stroke(stroke)
        case (.opacity(let opacity), .fill(var fill)):
            fill.opacity = opacity
            return .fill(fill)
        case (.opacity(let opacity), .text(var text)):
            text.recipe.opacity = opacity
            return .text(text)
        case (.color, .image), (.color, .video),
             (.size, .fill), (.size, .text), (.size, .image), (.size, .video),
             (.opacity, .image), (.opacity, .video):
            return nil
        }
    }

    /// The colour with its alpha pinned at 1 — what a colour *comparison* and a colour *tally* are
    /// about, since the alpha is the element's own and never travels.
    static func hue(of color: CodableColor) -> CodableColor {
        CodableColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
    }

    /// The element's own alpha kept, the hue replaced — the 2026-08-28 ruling.
    private static func recoloured(_ existing: CodableColor, to picked: CodableColor) -> CodableColor {
        CodableColor(red: picked.red, green: picked.green, blue: picked.blue, alpha: existing.alpha)
    }
}

/// **What the loop has caught, as the three controls show it** — each field the most common value
/// among the caught elements the control reaches, and whether the caught elements disagree.
///
/// "Most common" rather than the first, the mean or nothing: the swatch has to *default to the
/// current colour* (the owner's words), and a loop around two black lines and one red one is a loop
/// around black ink with an exception, which is what a picker should open on. When they disagree the
/// control says **Mixed** beside the value it opens on, so the artist knows the first tick will make
/// them agree. Ties go to whichever value the display list reaches first, which is deterministic and
/// otherwise arbitrary.
///
/// A nil field means the loop caught nothing that control reaches — a loop around a photograph has
/// no colour to default to — and the control is dimmed rather than shown at a made-up value.
struct SelectionStyle: Equatable {
    var color: CodableColor?
    var colorIsMixed = false
    var size: CGFloat?
    var sizeIsMixed = false
    var opacity: Double?
    var opacityIsMixed = false

    /// Nothing to show: no selection, the wrong kind of cel, or a derived frame.
    static let unavailable = SelectionStyle()

    /// The tally over `elements` restricted to `caught`, with an open session's live value laid over
    /// the field it is dragging — during a drag every caught element the control reaches already
    /// holds that value, so the tally would say the same thing at the cost of a walk.
    static func of(_ elements: [VectorElement], caught: Set<UUID>,
                   overriding live: SelectionEditValue? = nil) -> SelectionStyle {
        var colours: [CodableColor: Int] = [:], colourOrder: [CodableColor] = []
        var sizes: [CGFloat: Int] = [:], sizeOrder: [CGFloat] = []
        var opacities: [Double: Int] = [:], opacityOrder: [Double] = []
        for element in elements where caught.contains(element.id) {
            if case .color(let colour)? = SelectionEditKind.color.current(of: element) {
                if colours.updateValue((colours[colour] ?? 0) + 1, forKey: colour) == nil { colourOrder.append(colour) }
            }
            if case .size(let size)? = SelectionEditKind.size.current(of: element) {
                if sizes.updateValue((sizes[size] ?? 0) + 1, forKey: size) == nil { sizeOrder.append(size) }
            }
            if case .opacity(let opacity)? = SelectionEditKind.opacity.current(of: element) {
                if opacities.updateValue((opacities[opacity] ?? 0) + 1, forKey: opacity) == nil { opacityOrder.append(opacity) }
            }
        }
        /// The most common value, ties to the first in display order — `max(by:)` replaces its
        /// candidate only on a strictly greater count, so walking `order` keeps the earliest of equals.
        func mode<T: Hashable>(_ counts: [T: Int], _ order: [T]) -> (T?, Bool) {
            guard !order.isEmpty else { return (nil, false) }
            let best = order.max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
            return (best, order.count > 1)
        }
        var style = SelectionStyle()
        (style.color, style.colorIsMixed) = mode(colours, colourOrder)
        (style.size, style.sizeIsMixed) = mode(sizes, sizeOrder)
        (style.opacity, style.opacityIsMixed) = mode(opacities, opacityOrder)
        switch live {
        case .color(let colour)?:
            if style.color != nil { style.color = SelectionEditKind.hue(of: colour); style.colorIsMixed = false }
        case .size(let size)?:
            if style.size != nil { style.size = size; style.sizeIsMixed = false }
        case .opacity(let opacity)?:
            if style.opacity != nil { style.opacity = opacity; style.opacityIsMixed = false }
        case nil:
            break
        }
        return style
    }
}

extension CodableColor: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(red); hasher.combine(green); hasher.combine(blue); hasher.combine(alpha)
    }
}

/// The memo behind `CanvasManager.selectionStyle` — `SelectionAnimationGroupMemo`'s shape, for its
/// reason: the tally needs the loop pulled back and a containment test per element, which is fine
/// once per edit and not once per SwiftUI body pass.
struct SelectionStyleMemo: Equatable {
    var pathObject: ObjectIdentifier
    var bounds: CGRect
    var layerID: UUID
    var celID: UUID
    var frame: Int
    var vectorVersion: Int
    var membership: LassoMembership
    var answer: SelectionStyle

    func matches(_ key: SelectionStyleMemo) -> Bool {
        pathObject == key.pathObject && bounds == key.bounds && layerID == key.layerID
            && celID == key.celID && frame == key.frame && vectorVersion == key.vectorVersion
            && membership == key.membership
    }
}

/// **One drag, from the first tick to the commit.** Built by `beginSelectionEdit`, rewritten by every
/// `previewSelectionEdit`, closed by `commitSelectionEdit` or `cancelSelectionEdit`.
struct SelectionEditSession {
    let kind: SelectionEditKind
    let layerID: UUID
    let celID: UUID
    let vectorCanvas: VectorCanvas
    /// The list as the artist found it — what a cancel puts back and what the undo step's old side is.
    let elementsBefore: [VectorElement]
    /// The list every tick rewrites *from*: `elementsBefore` under Enclosed and Touching, and the split
    /// list under Cut, whose inside pieces are the caught set. Rewriting from here rather than from the
    /// canvas's current list is what makes a tick idempotent — dragging back to the start value gives
    /// exactly this list back, field for field.
    let working: [VectorElement]
    /// The ids a tick may rewrite — `ElementSwap.rewritesInPlace`'s operand, over-declared on purpose:
    /// it includes the caught elements the control does not reach, which cost their own footprint of
    /// repair and can never draw a wrong picture.
    let caught: Set<UUID>
    /// Whether any tick has reached the canvas. False for a picker opened and closed untouched, and
    /// for a drag whose first ticks changed nothing; such a session ends with no render and no step.
    var applied = false
    /// The last value previewed, laid over the readout while the drag is live.
    var value: SelectionEditValue?
}

extension CanvasManager {

    // MARK: - Availability

    /// Why Colour, Size and Opacity are off on the active cel, or nil when they are on. Shown in the
    /// Select panel in the artist's terms rather than the band going quietly grey — the rule and the
    /// voice of `applyBrushUnavailableReason` beside it, which refuses on exactly the same two cels.
    ///
    /// **Pixel layers are out of scope** (owner, 2026-08-28): every arm rewrites a stored *field* on
    /// an element, and a raster cel has pixels and no elements. **An in-between refuses** for
    /// `TopToolbar.toggleMove`'s reason: an interpolated cel's frame is derived, so the write would
    /// land on a `VectorCanvas` the displayed image is not computed from.
    ///
    /// Says nothing about whether a selection exists: the whole band is already disabled without one
    /// (`SelectPanel.hasSelection`), so folding that in would put two captions on screen saying the
    /// same thing.
    var selectionEditUnavailableReason: String? {
        guard layers.indices.contains(currentLayerIndex) else { return nil }
        guard layers[currentLayerIndex].kind == .vector,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              layers[currentLayerIndex].cels[celIndex].vector != nil else {
            return "Colour, Size and Opacity work on vector layers only."
        }
        if activeCelIsInBetween { return "Colour, Size and Opacity can't edit an in-between frame." }
        return nil
    }

    // MARK: - The readout

    /// What the three controls show — the selection's own values, or the live one mid-drag.
    ///
    /// **During a session the tally is over the session's own list and touches no geometry**: the
    /// caught set is already resolved, and every tick bumps the canvas's version, so a memo keyed on
    /// it would recompute the containment pass on every body pass of the drag. Outside a session the
    /// answer is memoized on everything it can depend on, exactly as `selectionAnimationGroup` is.
    ///
    /// **The cheap classifier, never the splitter** — that property's rule, for its reason: under Cut
    /// a straddling stroke's inside piece inherits its parent's colour, size and opacity, so the
    /// parent's values *are* the answer for the piece that will be edited, and a readout that cut
    /// geometry to draw a swatch would be a side effect in a getter.
    var selectionStyle: SelectionStyle {
        if let session = selectionEdit {
            return SelectionStyle.of(session.working, caught: session.caught, overriding: session.value)
        }
        guard selectionEditUnavailableReason == nil,
              let selection,
              layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].id == selection.layerID,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              layers[currentLayerIndex].cels[celIndex].id == selection.celID,
              let vector = layers[currentLayerIndex].cels[celIndex].vector
        else { return .unavailable }

        let key = SelectionStyleMemo(
            pathObject: ObjectIdentifier(selection.path), bounds: selection.bounds,
            layerID: selection.layerID, celID: selection.celID, frame: currentFrame,
            vectorVersion: vector.version, membership: selectionMembership, answer: .unavailable)
        if let memo = selectionStyleMemo, memo.matches(key) { return memo.answer }

        let elements = vector.elements
        let loops = CanvasManager.lassoLoops(
            vector.localPath(fromCanvas: selection.path).normalized(using: VectorCanvas.lassoFillRule),
            posedBy: celPoseMaps(elements, layerID: selection.layerID, celID: selection.celID,
                                 atFrame: currentFrame))
        let caught = vector.elementIDs(insideLoops: loops, membership: selectionMembership)
        let answer = SelectionStyle.of(elements, caught: caught)
        var stored = key
        stored.answer = answer
        selectionStyleMemo = stored
        return answer
    }

    // MARK: - The session

    /// Opens a drag on the selection: resolves the loop under the rule the artist picked, splits under
    /// Cut, and remembers the list as it stands. **Records nothing and renders nothing** — a session
    /// that is opened and closed untouched leaves no trace, which is what a picker opened to *look* at
    /// the current colour must cost.
    ///
    /// Membership is the selection's with no exception (LASSO_MOVE.md §5.26), read through the same
    /// two doors `applyBrushToSelection` and a lift read it through: the splitter under Cut, whose
    /// `insideIDs` is the caught set, and the classifier under Enclosed and Touching. Enclosed catching
    /// nothing in a loop full of ink says so (§5.24) and refuses; bare paper refuses silently.
    ///
    /// - Returns: whether a session is open for `kind` when this returns. A session already open for
    ///   the same control is reused rather than restarted — `previewSelectionEdit` begins one on the
    ///   first tick when the control's own touch-down did not, and the touch-down's call then lands
    ///   here. A session open for a *different* control is committed first: its drag is over.
    @discardableResult
    func beginSelectionEdit(_ kind: SelectionEditKind) -> Bool {
        if let open = selectionEdit {
            if open.kind == kind { return true }
            commitSelectionEdit()
        }
        let requested = selection
        // `commitAllInteractiveState`, not `beginCanvasEdit`, for `applyBrushToSelection`'s reason: a
        // selection outlives a Move lift, and a float still up would bake its own old values over
        // the top of every tick.
        commitAllInteractiveState()
        guard selectionEditUnavailableReason == nil,
              let selection = requested,
              layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].id == selection.layerID,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              layers[currentLayerIndex].cels[celIndex].id == selection.celID,
              let vectorCanvas = layers[currentLayerIndex].cels[celIndex].vector else { return false }
        let layerID = layers[currentLayerIndex].id
        let celID = layers[currentLayerIndex].cels[celIndex].id

        // Both preconditions `splitForLassoMove` states — local space, normalized — and the
        // per-element pull-back LASSO_MOVE.md §5.27 rules: a lasso means what it means on screen,
        // including on a frame where a pose channel shows the drawing somewhere other than where it
        // is stored.
        let drawn = vectorCanvas.localPath(fromCanvas: selection.path)
                                .normalized(using: VectorCanvas.lassoFillRule)
        let elementsBefore = vectorCanvas.elements
        let loops = CanvasManager.lassoLoops(
            drawn, posedBy: celPoseMaps(elementsBefore, layerID: layerID, celID: celID,
                                        atFrame: currentFrame))
        let membership = selectionMembership
        let working: [VectorElement]
        let caught: Set<UUID>
        if membership.cutsAtTheBoundary {
            // Nil is bare paper — Cut catches everything Touching does for strokes and fills, so it
            // cannot reach §5.24's case — and stays silent, exactly as a lift's does.
            guard let split = vectorCanvas.splitForLassoMove(insideLoops: loops,
                                                             membership: membership) else { return false }
            working = split.elements
            caught = split.insideIDs
        } else {
            working = elementsBefore
            caught = vectorCanvas.elementIDs(insideLoops: loops, membership: membership)
            guard !caught.isEmpty else {
                noteALassoThatCaughtNothing(vector: vectorCanvas, loops: loops)
                return false
            }
        }
        selectionEdit = SelectionEditSession(kind: kind, layerID: layerID, celID: celID,
                                             vectorCanvas: vectorCanvas,
                                             elementsBefore: elementsBefore, working: working,
                                             caught: caught)
        return true
    }

    /// One tick: every caught element the control reaches takes `value`, in place, and the selection's
    /// rectangle re-renders. **No undo entry.**
    ///
    /// Begins a session when none is open — a slider's first value write can land before its
    /// `onEditingChanged(true)`, and a tick with nowhere to go would be a control that moved and drew
    /// nothing, CLAUDE.md's "a refusal with no notice".
    ///
    /// **Rewrites from `working`, never from the canvas's current list**, so a tick is a function of
    /// the value alone and not of the ticks before it: dragging Size to 30 and back to 12 leaves every
    /// stroke at exactly the size it started with, bit for bit. A first tick that changes nothing —
    /// the picker opened on the selection's own colour, the slider grabbed without moving — assigns
    /// nothing, so no render is asked for; once a tick has reached the canvas every later one does,
    /// because the canvas now holds the *previous* tick's values and the one that puts them back is as
    /// real an edit as the one that took them away.
    func previewSelectionEdit(_ value: SelectionEditValue) {
        guard beginSelectionEdit(value.kind), var session = selectionEdit else { return }
        var newElements = session.working
        var changed = 0
        for (index, element) in session.working.enumerated() where session.caught.contains(element.id) {
            guard let rewritten = SelectionEditKind.rewritten(element, to: value) else { continue }
            if session.kind.current(of: element) != session.kind.current(of: rewritten) { changed += 1 }
            newElements[index] = rewritten
        }
        session.value = value
        guard changed > 0 || session.applied else {
            selectionEdit = session
            return
        }
        if !session.applied,
           let layerIndex = layers.firstIndex(where: { $0.id == session.layerID }),
           let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == session.celID }) {
            // Clear the transient tier once, or a stale pre-edit fill preview composites over the top —
            // `applyBrushToSelection`'s line, at the first tick rather than the press.
            setFillImage(layerIndex: layerIndex, celIndex: celIndex, image: (nil as UIImage?))
        }
        session.applied = true
        selectionEdit = session
        // **The seam, told the ids** — `restoreElements(_:changedInk:rewriting:)` bounds the swap by
        // the union of where each caught element was and where it will be, and a tick landing before
        // the previous tick's render has measured anything is bounded the same way rather than
        // falling to the cel (PERFORMANCE.md §11.11f's closing argument). `caught` rather than the
        // exact changed set, for `ElementSwap.rewritesInPlace`'s over-declare rule.
        session.vectorCanvas.restoreElements(newElements, changedInk: nil, rewriting: session.caught)
        celContentChangedOutsideStroke(layerID: session.layerID, celID: session.celID)
    }

    /// Closes the drag as **one undo step** from the list the artist started with to the list they
    /// let go of — or, when the drag ended where it began, puts the first list back and records
    /// nothing, which under Cut also throws the split away.
    ///
    /// - Returns: whether a step was recorded.
    @discardableResult
    func commitSelectionEdit() -> Bool {
        guard let session = selectionEdit else { return false }
        selectionEdit = nil
        guard session.applied else { return false }
        let final = session.vectorCanvas.elements
        // "Changed" is asked of the fields, not of the lists: under Cut the lists differ by the split
        // alone, and a split nobody's tick coloured, widened or faded is not an edit the artist made.
        var before: [UUID: SelectionEditValue] = [:]
        for element in session.working where session.caught.contains(element.id) {
            if let value = session.kind.current(of: element) { before[element.id] = value }
        }
        let changed = final.contains { element in
            guard let was = before[element.id] else { return false }
            return session.kind.current(of: element) != was
        }
        guard changed else {
            session.vectorCanvas.restoreElements(session.elementsBefore, changedInk: nil,
                                                 rewriting: session.caught)
            celContentChangedOutsideStroke(layerID: session.layerID, celID: session.celID)
            return false
        }
        registerVectorElementsUndo(vectorCanvas: session.vectorCanvas,
                                   oldElements: session.elementsBefore, newElements: final,
                                   layerID: session.layerID, celID: session.celID,
                                   label: session.kind.label,
                                   // Every tick put each caught element back at its own index under
                                   // its own id — these are the ids. Under Cut the split's pieces
                                   // arrive under fresh ids, which the same seam bounds by id
                                   // difference.
                                   swap: .rewritesInPlace(session.caught))
        // The layer-panel thumbnail is a third thing, and `registerVectorElementsUndo` refreshes it
        // on the undo and redo sides but not on the initial apply — `applyBrushToSelection`'s line.
        celContentChangedOutsideStroke(layerID: session.layerID, celID: session.celID)
        return true
    }

    /// Throws the drag away: the list the artist started with goes back and **nothing is recorded**.
    /// Reached when the selection is cleared mid-drag (`selection`'s `didSet`) and when undo is pressed
    /// mid-drag (`finalizePendingGesturesForHistoryAction`), which is the fill's and the shape's rule
    /// for a gesture still under the finger: it is discarded, not stepped back from.
    func cancelSelectionEdit() {
        guard let session = selectionEdit else { return }
        selectionEdit = nil
        guard session.applied else { return }
        session.vectorCanvas.restoreElements(session.elementsBefore, changedInk: nil,
                                             rewriting: session.caught)
        celContentChangedOutsideStroke(layerID: session.layerID, celID: session.celID)
    }

    // MARK: - One-shot

    /// The three-step session as one call — the shape a test drives and the shape a discrete control
    /// would take. Nothing in the Select panel calls it: every control there is a drag or a popover
    /// and brackets the session itself.
    ///
    /// - Returns: whether the document changed and a step was recorded.
    @discardableResult
    func applySelectionEdit(_ value: SelectionEditValue) -> Bool {
        guard beginSelectionEdit(value.kind) else { return false }
        previewSelectionEdit(value)
        return commitSelectionEdit()
    }

    /// Every stroke, fill and text object the selection caught takes `color`'s hue, keeping its own
    /// alpha, under the rule the artist picked in the Select panel — as one undo step.
    ///
    /// The colour is an argument. Until TODO (42) this read `brushColor` — the palette's current
    /// colour, applied silently — which the owner ruled against: *"The color changer also shouldnt be
    /// the current selected color, but instead show the color picker menu defaulting to the current
    /// color."* The Select panel's swatch is that picker, and it drives the session directly.
    @discardableResult
    func recolorSelection(to color: Color) -> Bool {
        let components = color.rgbaComponents
        return applySelectionEdit(.color(CodableColor(red: components.r, green: components.g,
                                                      blue: components.b, alpha: components.a)))
    }
}
