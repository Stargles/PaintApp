import Combine   // objectWillChange.send()
import SwiftUI
import UIKit

// MARK: - Objects the Add menu lays down — Rectangle, Ellipse and Linear Gradient
//
// TODO (129) and (128), the owner: *"the rectangle and ellipse objects in the add menu should not be
// smart shapes. They should be entirely solid shapes. I think the best way to implement them may be
// to make it the same type of shape as what the fill tool lays down."* and *"revise the gradient
// feature. Currently it seems to be a property of the layer. Remove all that and make sure nothing is
// left. It is supposed to be an object in the vector layer."*
//
// **All three are one kind of object: a `VectorFillElement`**, the fill tool's own output, differing
// only in the path (a rectangle, an ellipse, the artwork's rectangle) and the paint (a flat colour or
// a gradient). So each is selected, moved, cut by the eraser, warped by an interpolation and
// animated by a channel exactly as a filled region is, with nothing written for it in any of those —
// the paint travels inside the element, through the one `reshaped(to:paint:)` that every
// rebuild-from-a-mapped-path site already calls.

extension CanvasManager {

    // MARK: - Solid shapes

    /// The shapes Add offers as solid objects.
    enum SolidShape: Equatable {
        case rectangle
        case ellipse

        /// The shape's outline in `rect`.
        func path(in rect: CGRect) -> CGPath {
            switch self {
            case .rectangle: return CGPath(rect: rect, transform: nil)
            case .ellipse: return CGPath(ellipseIn: rect, transform: nil)
            }
        }

        var label: HistoryActionLabel {
            switch self {
            case .rectangle: return .addRectangle
            case .ellipse: return .addEllipse
            }
        }
    }

    /// **Add → Rectangle and Add → Ellipse.** A solid shape in the brush colour, centred on the
    /// artwork, laid down through the fill tool's own add path (`layDownSolidFill`): a
    /// `VectorFillElement` on a vector layer, painted pixels on a raster layer.
    ///
    /// **Where, and how big.** Centred in the *artwork* rect — the canvas inset by its padding, which
    /// is the paper the artist is looking at and not the margin around it — at 60% of that rect's
    /// shorter side, so it is a square or a circle every handle of which is on screen whatever the
    /// document's aspect. Not the visible viewport: the model does not know it, and an object that
    /// lands at the same place every time is one the artist can predict, which beats one that lands
    /// wherever the last pinch left them.
    ///
    /// **On a vector layer the new shape arrives held in the Move box**, exactly as an imported photo
    /// does (`insertImage`, TODO (34)): a default-sized shape is only useful if it can be sized, and
    /// Move's own box is the sizing tool — corners scale, the knob turns, the stretch handles
    /// distort — so there is nothing new to learn and nothing new to build. A raster layer has no
    /// object to lift, so the shape lands as pixels and the lasso-and-Move route is the way to size
    /// it; that asymmetry is the raster tier's, not this feature's.
    ///
    /// **A layer with no drawing surface** (a value or transform layer) gets a fresh vector layer to
    /// put the shape on, as an imported photo does — a refusal here would be an Add row that does
    /// nothing on the layers where the artist most often stands to add a backdrop.
    ///
    /// - Returns: whether a shape was laid down.
    @discardableResult
    func addSolidShape(_ shape: SolidShape) -> Bool {
        guard let rect = defaultShapeRect,
              let surface = drawingSurfaceForNewObject(vectorOnly: false),
              let landing = layDownSolidFill(shape.path(in: rect),
                                             color: brushColor.resolvedUIColor(opacity: brushOpacity),
                                             layerIndex: surface.layerIndex, celIndex: surface.celIndex,
                                             label: shape.label) else { return false }
        if case .element(let id) = landing { raiseMoveBox(onNewElement: id) }
        return true
    }

    /// The default rectangle a solid shape is laid in: a square centred on the artwork at 60% of its
    /// shorter side. Nil before a canvas exists.
    var defaultShapeRect: CGRect? {
        guard let artwork = artworkRect else { return nil }
        let side = min(artwork.width, artwork.height) * 0.6
        return CGRect(x: artwork.midX - side / 2, y: artwork.midY - side / 2, width: side, height: side)
    }

    // MARK: - Linear gradient

    /// **Add → Linear Gradient.** A gradient fill covering the artwork, black to white and running
    /// left to right, on the active vector layer — or on a fresh vector layer when the active one is
    /// not one, because a gradient is an object in a vector layer and nothing else.
    ///
    /// **Its panel opens with it.** What the artist does next is choose the two colours and the
    /// direction, which is what the panel is for, so it is up by the time the gradient is — the way
    /// Add Text opens the text panel. No Move box: a gradient that covers the artwork has a box the
    /// size of the screen, which is a box nobody can grab, and the panel is the thing it needs.
    ///
    /// - Returns: whether a gradient was laid down.
    @discardableResult
    func addGradient() -> Bool {
        guard let artwork = artworkRect,
              let surface = drawingSurfaceForNewObject(vectorOnly: true),
              let id = placeVectorFill(CGPath(rect: artwork, transform: nil),
                                       paint: .linearGradient(.spanning(artwork, angle: 0)),
                                       layerIndex: surface.layerIndex, celIndex: surface.celIndex,
                                       label: .addGradient) else { return false }
        return beginGradientEdit(elementID: id)
    }

    // MARK: - Shared by the three

    /// The cel an added object lands on, minting what it needs: the active layer when it can take the
    /// object, otherwise a fresh vector layer (a separate, preceding undo step — `insertImage`'s
    /// precedent). Settles whatever was pending first, which is what a canvas edit does.
    ///
    /// `vectorOnly` is for the gradient, which exists only as a vector element; a shape also lands
    /// on a raster layer, through the fill tool's raster arm.
    private func drawingSurfaceForNewObject(vectorOnly: Bool) -> (layerIndex: Int, celIndex: Int)? {
        beginCanvasEdit()
        guard canvasSize != nil else { return nil }
        let usable = vectorOnly ? activeLayerKind == .vector : (activeLayerKind?.holdsPixels ?? false)
        if !usable { addVectorLayer() }
        guard layers.indices.contains(currentLayerIndex),
              let celIndex = ensureCelAtCurrentFrame(layerIndex: currentLayerIndex) else { return nil }
        return (currentLayerIndex, celIndex)
    }

    /// Holds a newly added element in the Move box. **Silent on an in-between**, which is the one
    /// frame where Move refuses: `beginVectorMove` would raise a banner for a Move the artist did
    /// not ask for, and the object itself has landed — `insertImage`'s rule, for its reason.
    private func raiseMoveBox(onNewElement id: UUID) {
        guard !activeCelIsInBetween else { return }
        beginVectorMove(ofElementIDs: [id])
    }

    // MARK: - Editing a gradient

    /// Which end of the gradient a colour belongs to.
    enum GradientEnd: Equatable {
        case start
        case end
    }

    /// Opens the gradient `elementID` on the active cel for editing — the panel's whole life.
    ///
    /// **A session, not a gesture**: it stays open while the panel is up, every change re-renders the
    /// element in place (`restoreElements(_:changedInk:rewriting:)`, so a change costs the gradient's
    /// own rectangle), and it closes as **one undo step** when the next canvas edit, tool change or
    /// undo settles it (`commitGradientEdit`). The text session's shape, for its reason: undo is the
    /// artist's way back to *before they opened the panel*, not through every slider tick.
    ///
    /// - Returns: false when the element is not a gradient on the cel under the playhead.
    @discardableResult
    func beginGradientEdit(elementID: UUID) -> Bool {
        commitGradientEdit()
        guard layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].kind == .vector,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              let vector = layers[currentLayerIndex].cels[celIndex].vector else { return false }
        let elements = vector.elements
        guard elements.contains(where: { $0.id == elementID && $0.fill?.gradient != nil }) else { return false }
        gradientEdit = GradientEditSession(elementID: elementID, layerID: layers[currentLayerIndex].id,
                                           celID: layers[currentLayerIndex].cels[celIndex].id,
                                           vectorCanvas: vector, elementsBefore: elements)
        return true
    }

    /// The gradient the panel is editing, or nil when none is open — the model's answer for what the
    /// panel's two swatches and its angle show, so they cannot disagree with the picture.
    var editedGradient: LinearGradientPaint? {
        editedGradientElement?.fill?.gradient
    }

    private var editedGradientElement: VectorElement? {
        guard let session = gradientEdit else { return nil }
        return session.vectorCanvas.elements.first { $0.id == session.elementID }
    }

    /// One end's colour, previewed live. The alpha travels with the pick — a gradient to transparent
    /// is the most useful gradient there is — unlike Change Colour, whose alpha is the element's own.
    func setGradientColour(_ end: GradientEnd, to color: Color) {
        let components = color.rgbaComponents
        let picked = CodableColor(red: components.r, green: components.g, blue: components.b,
                                  alpha: components.a)
        rewriteEditedGradient { gradient, _ in
            var changed = gradient
            switch end {
            case .start: changed.start = picked
            case .end: changed.end = picked
            }
            return changed
        }
    }

    /// The direction, previewed live, in radians — `LinearGradientPaint.angle`'s convention. The two
    /// points are re-spanned across the gradient's own shape (`turned(to:over:)`), so turning it never
    /// crops the ramp into a corner of itself.
    func setGradientAngle(_ angle: CGFloat) {
        rewriteEditedGradient { gradient, bounds in gradient.turned(to: angle, over: bounds) }
    }

    /// Writes one change to the edited element in place. Nothing is recorded; a no-change write
    /// touches nothing, so a slider grabbed and not moved leaves no trace.
    private func rewriteEditedGradient(_ change: (LinearGradientPaint, CGRect) -> LinearGradientPaint) {
        guard var session = gradientEdit else { return }
        var elements = session.vectorCanvas.elements
        guard let index = elements.firstIndex(where: { $0.id == session.elementID }),
              case .fill(var fill) = elements[index],
              let gradient = fill.gradient, let bounds = fill.cgPath?.boundingBoxOfPath else { return }
        let changed = change(gradient, bounds)
        guard changed != gradient else { return }
        fill.paint = .linearGradient(changed)
        elements[index] = .fill(fill)
        session.applied = true
        gradientEdit = session
        // **The id is declared**, so the repair is bounded by the gradient's own rectangle rather than
        // falling to the whole cel — `previewSelectionEdit`'s seam, for the same slider-driven rate.
        session.vectorCanvas.restoreElements(elements, changedInk: nil, rewriting: [session.elementID])
        celContentChangedOutsideStroke(layerID: session.layerID, celID: session.celID)
        refreshUndoRedoState()
    }

    /// Closes the session as **one undo step** from the list the artist found to the list they left —
    /// or records nothing when the edits ended where they began.
    ///
    /// - Returns: whether a step was recorded.
    @discardableResult
    func commitGradientEdit() -> Bool {
        guard let session = gradientEdit else { return false }
        gradientEdit = nil
        defer { refreshUndoRedoState() }
        guard session.applied else { return false }
        let final = session.vectorCanvas.elements
        let paintBefore = session.elementsBefore.first { $0.id == session.elementID }?.fill?.paint
        let paintAfter = final.first { $0.id == session.elementID }?.fill?.paint
        guard paintBefore != paintAfter else { return false }
        registerVectorElementsUndo(vectorCanvas: session.vectorCanvas,
                                   oldElements: session.elementsBefore, newElements: final,
                                   layerID: session.layerID, celID: session.celID, label: .editGradient,
                                   swap: .rewritesInPlace([session.elementID]))
        celContentChangedOutsideStroke(layerID: session.layerID, celID: session.celID)
        return true
    }

    /// Throws the session's changes away: the list the artist found goes back and nothing is
    /// recorded. For a caller that must leave the document exactly as it was.
    func cancelGradientEdit() {
        guard let session = gradientEdit else { return }
        gradientEdit = nil
        defer { refreshUndoRedoState() }
        guard session.applied else { return }
        session.vectorCanvas.restoreElements(session.elementsBefore, changedInk: nil,
                                             rewriting: [session.elementID])
        celContentChangedOutsideStroke(layerID: session.layerID, celID: session.celID)
    }
}

/// **One open gradient panel**, from `beginGradientEdit` to its commit — `SelectionEditSession`'s
/// shape, for an object chosen by id rather than by a loop: there is no Cut to split under and no
/// selection to follow, so the session lives exactly as long as the panel does.
struct GradientEditSession {
    let elementID: UUID
    let layerID: UUID
    let celID: UUID
    let vectorCanvas: VectorCanvas
    /// The display list as the artist found it — what a cancel puts back and the undo step's old side.
    let elementsBefore: [VectorElement]
    /// Whether any change has reached the canvas. False for a panel opened and closed untouched, which
    /// records no step.
    var applied = false
}
