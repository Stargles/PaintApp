import Combine   // objectWillChange.send()
import SwiftUI
import UIKit

// MARK: - Smart Shapes (interactive: detect shape from held stroke, adjustable via handles)
//
// The CanvasManager side of smart shapes: the derived views of the gesture state, the memoized
// preview, and the commit paths that bake the shape into a raster or vector layer. Detection itself
// lives in Engine/ShapeDetector.swift and is untouched by this file.
//
// Extracted from CanvasManager.swift as an extension — all state still lives on the class itself
// (see that file's header), so the shape gesture's stored properties stay declared over there.

extension CanvasManager {

    /// The current shape being drawn/edited, exposed as a read-only snapshot for the overlay's
    /// control handles.
    var activeShape: ShapeGeometry? {
        shapeGestureActive ? shapeGeometry : nil
    }

    /// The shape as it will actually be baked: `activeShape` with the two-finger constraint applied.
    /// The preview, the handles, and `commitInteractiveShape` all go through this, so what the user
    /// sees is what lands on the layer.
    var resolvedShape: ShapeGeometry? {
        guard let shape = activeShape else { return nil }
        return shapeIsConstrained ? shape.constrained : shape
    }

    /// Spacing between stamps along the shape outline — the same brush-diameter fraction live
    /// drawing uses, so a collapsed shape is stamped exactly as densely as a freehand stroke.
    private var shapeStampSpacing: CGFloat {
        max(shapeGestureStrokeWidth * CGFloat(shapeGestureBrush.dab.spacing), 1)
    }

    /// The stroke `commitInteractiveShape` will lay down: the freehand samples collapsed onto the
    /// resolved shape's outline.
    private func collapsedShapeSamples(for shape: ShapeGeometry) -> StrokeSamples {
        ShapeDetector.collapseSamplesToShape(samples: shapeGestureSamples, shape: shape,
                                             spacing: shapeStampSpacing)
    }

    /// The most recently rendered preview. May lag the current geometry by a frame — see
    /// `isActiveShapePreviewStale` — which is deliberate: showing the previous stroke for one frame
    /// beats re-stamping a canvas-sized raster for every coalesced Pencil sample.
    var activeShapePreviewImage: UIImage? {
        shapeGestureActive ? shapePreviewCache?.image : nil
    }

    /// True when the geometry has moved on from what `activeShapePreviewImage` was rendered for.
    var isActiveShapePreviewStale: Bool {
        guard let shape = resolvedShape else { return false }
        return shapePreviewCache?.shape != shape
    }

    /// Renders the transient shape as the collapsed brush stroke that committing it would produce —
    /// so the adjustable preview shows the user's own stroke, pressure profile and all, rather than a
    /// uniform generated outline that then visibly changes the moment it bakes.
    ///
    /// Memoized per geometry, and stamped into a texture reused across the gesture, so a handle drag
    /// costs one re-stamp rather than one allocation plus one re-stamp per event.
    @discardableResult
    func renderActiveShapePreview() -> UIImage? {
        guard let shape = resolvedShape, let canvasSize else { return nil }
        if let cached = shapePreviewCache, cached.shape == shape { return cached.image }

        let texture: RasterLayerTexture
        if let existing = shapePreviewTexture, existing.size == canvasSize {
            texture = existing
            texture.reset(to: nil, strokeCount: 0)
        } else {
            texture = .empty(size: canvasSize)
            shapePreviewTexture = texture
        }

        BrushStamper.stampStroke(into: texture, samples: collapsedShapeSamples(for: shape),
                                 brush: shapeGestureBrush,
                                 color: shapeGestureColor.uiColor, brushSize: shapeGestureStrokeWidth,
                                 brushOpacity: shapeGestureOpacity,
                                 random: DabRandom(seed: shapeGestureSeed))
        let image = texture.renderToUIImage()
        shapePreviewCache = (shape, image)
        return image
    }

    /// Begins an interactive shape. Called when the hold timer fires and ShapeDetector confirms a shape.
    func beginInteractiveShape(_ shape: ShapeGeometry, samples: [VectorSample] = []) {
        guard !shapeFingerDown else { return }
        // Laying down a new shape is a canvas edit: whatever was still pending bakes first, so the
        // two never share the transient tier (only one shape's geometry is tracked at a time).
        beginCanvasEdit()
        guard layers.indices.contains(currentLayerIndex) else { return }
        let layerIndex = currentLayerIndex
        guard let celIndex = activeCelIndex(inLayer: layerIndex, atFrame: currentFrame) else { return }

        shapeGestureActive = true
        shapeFingerDown = true
        shapeGeometry = shape
        shapeIsConstrained = false
        shapePreviewCache = nil
        shapeGestureLayerID = layers[layerIndex].id
        shapeGestureCelID = layers[layerIndex].cels[celIndex].id
        shapeGestureSamples = samples
        // Shape detection only ever runs for the pen/pencil (see `startShapeDetection`), so the
        // paint brush's settings are always the right ones to snapshot here.
        shapeGestureBrush = selectedBrush
        shapeGestureSeed = DabRandom.freshSeed()
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        brushColor.resolvedUIColor(opacity: brushOpacity).getRed(&r, green: &g, blue: &b, alpha: &a)
        shapeGestureColor = CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
        shapeGestureStrokeWidth = brushSize
        shapeGestureOpacity = brushOpacity
        refreshUndoRedoState()
    }

    /// Updates the shape's geometry as the user drags a handle or continues the hold stroke.
    /// `startPoint`/`endPoint` are optional so partial updates are possible (e.g. edge-handle
    /// drags on rectangles resize opposite edges, changing only one corner). Emits
    /// `objectWillChange` so the SwiftUI-refresh path re-runs `updateShapeOverlay` and keeps
    /// the overlay's preview and handles glued to the live shape.
    func updateInteractiveShape(startPoint: CGPoint? = nil, endPoint: CGPoint? = nil,
                                rotation: CGFloat? = nil, isConstrained: Bool? = nil) {
        guard shapeGestureActive else { return }
        if let startPoint { shapeGeometry.startPoint = startPoint }
        if let endPoint { shapeGeometry.endPoint = endPoint }
        if let rotation { shapeGeometry.rotation = rotation }
        if let isConstrained { shapeIsConstrained = isConstrained }
        objectWillChange.send()
    }

    /// Lifts the pen but leaves the shape adjustable.
    ///
    /// If the snap constraint is engaged at that moment, it stops being a live constraint and
    /// becomes the geometry itself. The pen coming off the board is what settles the shape, so
    /// releasing the snapping finger afterwards leaves the circle a circle — rather than springing
    /// it back to the oval it was originally drawn as, which is what the user saw before. Lifting
    /// the finger *first*, while still drawing, releases the snap as usual.
    func endInteractiveShape() {
        guard shapeGestureActive, shapeFingerDown else { return }
        shapeFingerDown = false
        if shapeIsConstrained { shapeGeometry = shapeGeometry.constrained }
        objectWillChange.send()
    }

    /// Bakes the current shape into the layer: the freehand stroke collapsed onto the shape outline,
    /// added as a `VectorStroke` on a vector layer (so the eraser cuts into it like any other stroke)
    /// or stamped into the cel's raster on a raster layer (so the eraser punches through it there).
    /// Either way what lands is a real brush stroke, not a separate shape object.
    func commitInteractiveShape() {
        guard shapeGestureActive, let shape = resolvedShape else { return }
        shapeGestureActive = false
        shapeFingerDown = false
        let savedBrush = shapeGestureBrush
        let collapsed = collapsedShapeSamples(for: shape)
        let layerID = shapeGestureLayerID
        let celID = shapeGestureCelID
        defer {
            shapeGestureLayerID = nil
            shapeGestureCelID = nil
            shapeGestureSamples = []
            shapePreviewCache = nil
            shapePreviewTexture = nil
            objectWillChange.send()
            refreshUndoRedoState()
        }
        guard !collapsed.isEmpty, let layerID, let celID,
              let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
              let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) else { return }

        if layers[layerIndex].kind == .vector {
            // A vector layer's cel should always have a VectorCanvas, but stamping into the cel's
            // raster if it somehow doesn't would paint into a buffer a vector layer never displays —
            // i.e. the shape would silently vanish. Materialise one instead.
            if layers[layerIndex].cels[celIndex].vector == nil, let canvasSize {
                layers[layerIndex].cels[celIndex].vector = .empty(size: canvasSize)
            }
            if let vectorCanvas = layers[layerIndex].cels[celIndex].vector {
                let stroke = VectorStroke(brush: savedBrush, color: shapeGestureColor,
                                          size: shapeGestureStrokeWidth, opacity: shapeGestureOpacity,
                                          samples: collapsed, seed: shapeGestureSeed)
                let elementsBefore = vectorCanvas.elements
                // The shape outline is in canvas space (it was dragged there) — same mapping the
                // live vector-stroke path uses, so a shape drawn on a moved layer lands where the
                // preview showed it.
                vectorCanvas.addStroke(canvasSpaceStroke: stroke)
                // **The whole display list, not the `strokes` bucket**, which is
                // `registerVectorElementsUndo`'s own argument: `addFill` and `upsertText` append, so
                // the list is not kind-sorted and a bucket-shaped undo has to invent a z-position for
                // the stroke it puts back. That was already true of a shape baked onto a cel holding
                // a fill; what makes it worth changing now is that the whole-list seam is also the
                // one that can bound itself.
                //
                // It re-prices the step, and deliberately: `registerVectorStrokeUndo` charged the
                // history 2,048 bytes a stroke where every other whole-array swap charges 512 an
                // element. Both are the rough estimates `UndoHistory.trim` asks for, and a shape's
                // snapshot is the same array a brush stroke's is, so one number for the two of them
                // is the honest one.
                registerVectorElementsUndo(vectorCanvas: vectorCanvas, oldElements: elementsBefore,
                                           newElements: vectorCanvas.elements,
                                           layerID: layerID, celID: celID, label: .shape,
                                           // One stroke appended and nothing rewritten, and no
                                           // rectangle needed in either direction: the undo measures
                                           // what leaves, and the redo is bounded by what the undo
                                           // remembered it painted. Same as a drawn stroke, because
                                           // it is one.
                                           swap: .addsAndRemoves(ink: nil))
                // Baking a shape never goes through `strokeEnded` (the stroke that produced it was
                // reverted when detection fired), so the thumbnail has to be refreshed here or the
                // layer panel keeps showing the cel as it was before the shape landed.
                scheduleThumbnailRegen(layerID: layerID, celID: celID)
                return
            }
        }

        stampShapeIntoRaster(collapsed, raster: layers[layerIndex].cels[celIndex].raster,
                             brush: savedBrush, layerID: layerID, celID: celID)
        scheduleThumbnailRegen(layerID: layerID, celID: celID)
    }

    /// Stamps a collapsed shape stroke into a raster cel and registers its undo step. Kept separate
    /// so the vector and raster commit paths share one collapse and one set of brush settings.
    private func stampShapeIntoRaster(_ samples: StrokeSamples, raster: RasterLayerTexture,
                                      brush: Brush, layerID: UUID, celID: UUID) {
        let before = raster.renderToUIImage()
        let strokeCountBefore = raster.strokeCount
        // stampStroke brackets itself in beginStroke/endStroke, so this is one undoable unit.
        BrushStamper.stampStroke(into: raster, samples: samples,
                                 brush: brush, color: shapeGestureColor.uiColor,
                                 brushSize: shapeGestureStrokeWidth, brushOpacity: shapeGestureOpacity,
                                 random: DabRandom(seed: shapeGestureSeed))
        let after = raster.renderToUIImage()
        let strokeCountAfter = raster.strokeCount
        let cost = Self.approximateImageCost(before) + Self.approximateImageCost(after)
        // Undo/redo mutates the texture in place, which no live stroke is driving — so these have to
        // republish the host refresh for the same reason the commit itself does, or undoing a shape
        // leaves it on screen (and redoing leaves it off) until the next unrelated edit repaints.
        recordUndo(label: .shape, cost: cost, undo: { [weak self] in
            raster.reset(to: before, strokeCount: strokeCountBefore)
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        }, redo: { [weak self] in
            raster.reset(to: after, strokeCount: strokeCountAfter)
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        })
    }

    func cancelInteractiveShape() {
        guard shapeGestureActive else { return }
        shapeGestureActive = false
        shapeFingerDown = false
        shapeGestureLayerID = nil
        shapeGestureCelID = nil
        shapeGestureSamples = []
        shapePreviewCache = nil
        shapePreviewTexture = nil
        objectWillChange.send()
        refreshUndoRedoState()
    }
}
