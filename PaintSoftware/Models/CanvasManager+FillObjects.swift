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
// only in the path (a rectangle, an ellipse, a band) and the paint (a flat colour or a gradient). So
// each is selected, moved, cut by the eraser, warped by an interpolation and animated by a channel
// exactly as a filled region is, with nothing written for it in any of those — the paint travels
// inside the element, through the one `reshaped(to:paint:)` that every rebuild-from-a-mapped-path
// site already calls.
//
// **What they are laid down *at* is the pen's** (TODO (149), `CanvasManager+Placement.swift`): the
// two verbs here take the geometry a drag has already measured, in canvas points.

extension CanvasManager {

    // MARK: - Solid shapes

    /// **Add → Rectangle and Add → Ellipse, at the geometry the pen dragged out.** A solid shape in the
    /// brush colour, laid down through the fill tool's own add path (`layDownSolidFill`): a
    /// `VectorFillElement` on a vector layer, painted pixels on a raster layer. One undo step.
    ///
    /// **A raster layer has no object to lift**, so the shape lands as pixels and the lasso-and-Move
    /// route is the way to move it; that asymmetry is the raster tier's, not this feature's. **A layer
    /// with no drawing surface** (a value or transform layer) gets a fresh vector layer to put the shape
    /// on, as an imported photo does — a refusal here would be an Add row that does nothing on the layers
    /// where the artist most often stands to add a backdrop.
    ///
    /// - Parameter shape: a rectangle or an oval, in canvas points.
    /// - Returns: whether a shape was laid down — false for a `.line`, which has no inside to fill.
    @discardableResult
    func placeSolidShape(_ shape: ShapeGeometry) -> Bool {
        let label: HistoryActionLabel
        switch shape.kind {
        case .rectangle: label = .addRectangle
        case .oval: label = .addEllipse
        case .line: return false
        }
        let color = brushColor.resolvedUIColor(opacity: brushOpacity)
        guard let surface = drawingSurfaceForNewObject(vectorOnly: false),
              let stored = layerSpaceFill(shape.rotatedCGPath, paint: .solid(CodableColor(color)),
                                          onLayerAt: surface.layerIndex) else { return false }
        return layDownSolidFill(stored.path, color: color, layerIndex: surface.layerIndex,
                                celIndex: surface.celIndex, label: label) != nil
    }

    // MARK: - Linear gradient

    /// **Add → Linear Gradient, as the band the pen dragged out.** A gradient fill, black to white,
    /// whose ramp runs from `from` to `to` and **ends there**: the object is the band itself, so the
    /// length of the line is the length of the gradient and the colours do not run on past it. On the
    /// active vector layer — or on a fresh vector layer when the active one is not one, because a
    /// gradient is an object in a vector layer and nothing else.
    ///
    /// **Its panel opens with it.** What the artist does next is choose the two colours, which is what
    /// the panel is for, so it is up by the time the gradient is — the way Add Text opens the text
    /// panel. (The direction it also offers is the one the drag just set; turning it afterwards re-spans
    /// the ramp over the band's bounds, as it does for any filled shape.)
    ///
    /// - Parameters:
    ///   - band: the rectangle the gradient occupies, in canvas points.
    ///   - from: where the ramp starts (the pen's press), in canvas points.
    ///   - to: where it ends (the pen's lift).
    /// - Returns: whether a gradient was laid down.
    @discardableResult
    func placeGradient(band: ShapeGeometry, from: CGPoint, to: CGPoint) -> Bool {
        let paint = FillPaint.linearGradient(.fresh(from: from, to: to))
        guard let surface = drawingSurfaceForNewObject(vectorOnly: true),
              let stored = layerSpaceFill(band.rotatedCGPath, paint: paint, onLayerAt: surface.layerIndex),
              let id = placeVectorFill(stored.path, paint: stored.paint,
                                       layerIndex: surface.layerIndex, celIndex: surface.celIndex,
                                       label: .addGradient) else { return false }
        return beginGradientEdit(elementID: id)
    }

    // MARK: - Shared by the two

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

    /// **What the artist sees laid down, written where the layer will show it** — the geometry of an
    /// added object, which is made in canvas points (what the pen dragged out), taken through
    /// the inverse of the pose its layer is shown through (`inkPose(forLayerID:)`, TODO (124)'s one
    /// source), path and gradient ends together. Under a transformation layer the object is then
    /// *shown* where the pen put it, rather than a pose away from it; on a layer nothing poses it
    /// is the object unchanged.
    ///
    /// A fill element is built only to be carried by `inLayerSpace`, the one mapping every other input
    /// surface already writes through (a smart shape, text, a stroke), so there is no second map to
    /// disagree with it. Nil only where a keystone sends a point through its vanishing line.
    private func layerSpaceFill(_ path: CGPath, paint: FillPaint,
                                onLayerAt layerIndex: Int) -> (path: CGPath, paint: FillPaint)? {
        let drawn = VectorElement.fill(VectorFillElement(path: path, paint: paint))
        guard case .fill(let fill)? = Self.inLayerSpace(drawn, shownThrough: inkPose(forLayerID: layers[layerIndex].id)),
              let stored = fill.cgPath else { return nil }
        return (stored, fill.paint)
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
