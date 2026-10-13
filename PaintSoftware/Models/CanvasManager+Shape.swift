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
    /// The preview (`shapeInk`), the handles, and `commitInteractiveShape` all go through this, so what
    /// the user sees is what lands on the layer.
    var resolvedShape: ShapeGeometry? {
        guard let shape = activeShape else { return nil }
        return shapeIsConstrained ? shape.constrained : shape
    }

    /// Spacing between stamps along the shape outline — the same brush-diameter fraction live
    /// drawing uses, so a collapsed shape is stamped exactly as densely as a freehand stroke.
    private var shapeStampSpacing: CGFloat {
        max(shapeGestureStrokeWidth * CGFloat(shapeGestureBrush.dab.spacing), 1)
    }

    /// **The pending shape's ink, as a value a render queue can draw** — the collapsed brush stroke
    /// committing it would lay down, pressure profile and all, rather than a uniform generated outline
    /// that visibly changes the moment it bakes. What `ShapeOverlayView` draws off the main thread, one
    /// picture in flight, into a canvas-sized surface pair (TODO (179)); nil with no shape pending.
    var shapeInk: ShapeInk? {
        guard let shape = resolvedShape, let canvasSize else { return nil }
        return ShapeInk(shape: shape, canvasSize: canvasSize, samples: shapeGestureSamples,
                        spacing: shapeStampSpacing, brush: shapeGestureBrush, color: shapeGestureColor,
                        size: shapeGestureStrokeWidth, opacity: shapeGestureOpacity, seed: shapeGestureSeed)
    }

    /// Begins an interactive shape. Called when the hold timer fires and ShapeDetector confirms a shape.
    func beginInteractiveShape(_ shape: ShapeGeometry, samples: [VectorSample]) {
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
        shapeGestureLayerID = layers[layerIndex].id
        shapeGestureCelID = layers[layerIndex].cels[celIndex].id
        shapeGestureInkPose = inkPose(forLayerID: layers[layerIndex].id)
        shapeGestureSamples = samples
        // Shape detection only ever runs for the pen/pencil (see `startShapeDetection`), so the
        // paint brush's settings are always the right ones to snapshot here.
        shapeGestureBrush = toolProfiles.brush.preset
        shapeGestureSeed = DabRandom.freshSeed()
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        brushColor.resolvedUIColor(opacity: toolProfiles.brush.opacity).getRed(&r, green: &g, blue: &b, alpha: &a)
        shapeGestureColor = CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
        shapeGestureStrokeWidth = toolProfiles.brush.size
        shapeGestureOpacity = toolProfiles.brush.opacity
        refreshUndoRedoState()
    }

    /// Updates the shape's geometry as the user drags a handle or continues the hold stroke.
    /// `startPoint`/`endPoint` are optional so partial updates are possible (e.g. edge-handle
    /// drags on rectangles resize opposite edges, changing only one corner).
    ///
    /// **Writes the draft tier, tells the canvas, and publishes nothing** (TODO (179)): the canvas is
    /// the one thing that draws the shape (`onHeldPictureMoved` re-lays its overlay), so a tick of a
    /// handle drag is the overlay's — not a SwiftUI pass over the editor.
    func updateInteractiveShape(startPoint: CGPoint? = nil, endPoint: CGPoint? = nil,
                                rotation: CGFloat? = nil, isConstrained: Bool? = nil) {
        guard shapeGestureActive else { return }
        if let startPoint { shapeGeometry.startPoint = startPoint }
        if let endPoint { shapeGeometry.endPoint = endPoint }
        if let rotation { shapeGeometry.rotation = rotation }
        if let isConstrained { shapeIsConstrained = isConstrained }
        onHeldPictureMoved?()
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
        guard shapeGestureActive, let ink = shapeInk else { return }
        shapeGestureActive = false
        shapeFingerDown = false
        let savedBrush = shapeGestureBrush
        let collapsed = ink.collapsedSamples
        let layerID = shapeGestureLayerID
        let celID = shapeGestureCelID
        let drawnUnder = shapeGestureInkPose
        defer {
            shapeGestureLayerID = nil
            shapeGestureCelID = nil
            shapeGestureInkPose = nil
            shapeGestureSamples = []
            objectWillChange.send()
            refreshUndoRedoState()
        }
        guard !collapsed.isEmpty, let layerID, let celID,
              let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
              let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) else { return }

        // The outline is in canvas points (it was dragged there), pulled into the layer's own space
        // through the pose it was drawn under — so a shape drawn on a posed layer lands where the
        // preview showed it. Both tiers take the same pull-back: a raster cel's pixels are the
        // layer's own too.
        guard case .stroke(let stroke)? = Self.inLayerSpace(.stroke(drawnShape(collapsed, brush: savedBrush)),
                                                            shownThrough: drawnUnder) else { return }

        if layers[layerIndex].kind == .vector {
            // A vector layer's cel should always have a VectorCanvas, but stamping into the cel's
            // raster if it somehow doesn't would paint into a buffer a vector layer never displays —
            // i.e. the shape would silently vanish. Materialise one instead.
            if layers[layerIndex].cels[celIndex].vector == nil, let canvasSize {
                layers[layerIndex].cels[celIndex].vector = .empty(size: canvasSize)
            }
            if let vectorCanvas = layers[layerIndex].cels[celIndex].vector {
                let elementsBefore = vectorCanvas.elements
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

        stampShapeIntoRaster(stroke, raster: layers[layerIndex].cels[celIndex].raster,
                             layerID: layerID, celID: celID)
        scheduleThumbnailRegen(layerID: layerID, celID: celID)
    }

    /// The collapsed outline as the stroke the artist's settings at detection make of it, in canvas
    /// points.
    private func drawnShape(_ samples: StrokeSamples, brush: Brush) -> VectorStroke {
        VectorStroke(brush: brush, color: shapeGestureColor, size: shapeGestureStrokeWidth,
                     opacity: shapeGestureOpacity, samples: samples, seed: shapeGestureSeed)
    }

    /// Stamps a collapsed shape stroke into a raster cel and registers its undo step. Kept separate
    /// so the vector and raster commit paths share one collapse and one set of brush settings.
    private func stampShapeIntoRaster(_ stroke: VectorStroke, raster: RasterLayerTexture,
                                      layerID: UUID, celID: UUID) {
        let before = raster.renderToUIImage()
        let strokeCountBefore = raster.strokeCount
        // stampStroke brackets itself in beginStroke/endStroke, so this is one undoable unit.
        BrushStamper.stampStroke(into: raster, samples: stroke.samples,
                                 brush: stroke.brush, color: shapeGestureColor.uiColor,
                                 brushSize: stroke.size, brushOpacity: shapeGestureOpacity,
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
        shapeGestureInkPose = nil
        shapeGestureSamples = []
        objectWillChange.send()
        refreshUndoRedoState()
    }
}

/// **A pending smart shape's ink, frozen** — everything the stroke its commit lays down is made of, so
/// a render queue can draw it while the main thread goes on moving the shape (TODO (179),
/// `CanvasManager.shapeInk`). A value: nothing in it is shared with the draft tier the next tick writes.
struct ShapeInk {
    /// The resolved geometry it draws — what tells two pictures of one shape apart.
    let shape: ShapeGeometry
    /// The canvas it is drawn over, in points: the window of its picture.
    let canvasSize: CGSize
    fileprivate let samples: [VectorSample]
    fileprivate let spacing: CGFloat
    fileprivate let brush: Brush
    fileprivate let color: CodableColor
    fileprivate let size: CGFloat
    fileprivate let opacity: Double
    fileprivate let seed: UInt64

    /// The freehand samples collapsed onto the shape's outline, at the spacing live drawing stamps —
    /// the stroke `commitInteractiveShape` lays down.
    var collapsedSamples: StrokeSamples {
        ShapeDetector.collapseSamplesToShape(samples: samples, shape: shape, spacing: spacing)
    }

    /// **Stamps the stroke into `context`**, a UIKit context over the canvas in its own points — the
    /// brush, colour, size, opacity and random field the commit stamps with, so the preview is the ink
    /// that lands. Safe off the main thread: it reads only this value.
    func draw(into context: CGContext) {
        BrushStamper.stampStroke(into: CGContextDabTarget(context), samples: collapsedSamples, brush: brush,
                                 color: color.uiColor, brushSize: size, brushOpacity: opacity,
                                 random: DabRandom(seed: seed))
    }
}
