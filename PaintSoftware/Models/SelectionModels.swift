import SwiftUI
import UIKit

// MARK: - Selection

enum SelectionMode: String, CaseIterable, Identifiable {
    case lasso
    case automatic
    case rectangle

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .lasso: return "Freehand"
        case .automatic: return "Automatic"
        case .rectangle: return "Rectangle"
        }
    }
    var systemImage: String {
        switch self {
        case .lasso: return "lasso"
        case .automatic: return "wand.and.rays"
        case .rectangle: return "rectangle.dashed"
        }
    }
}

enum TransformMode: String, CaseIterable, Identifiable {
    case freeform
    case uniform
    case distort
    case warp

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .freeform: return "Freeform"
        case .uniform: return "Uniform"
        case .distort: return "Distort"
        case .warp: return "Warp"
        }
    }
    /// Distort/Warp aren't implemented with real per-corner/mesh geometry yet — they render and
    /// gesture identically to Uniform until that follow-up work lands.
    var isImplemented: Bool { self == .freeform || self == .uniform }
}

/// A finalized selection: a closed path in canvas point space, stamped with the (layer, cel) it
/// belongs to so a layer/frame switch can tell whether it's still valid (see
/// `CanvasManager.handleActiveContextChanged`). Keyed by stable UUID rather than array index —
/// indices shift (or get silently reused) whenever `layers` is mutated, e.g. deleting the very
/// layer a selection lives on can leave `currentLayerIndex` numerically unchanged while it now
/// points at a different layer, which an index-based selection would wrongly treat as still valid.
struct Selection {
    var path: CGPath
    var bounds: CGRect
    var layerID: UUID
    var celID: UUID
}

// MARK: - Floating piece

/// Position/scale/rotation/flip of a floating (not-yet-committed) piece of pixel content, in canvas
/// point space. Conceptually the same idea as the object-layer work's `LayerTransform`, extended
/// with independent scaleX/scaleY (Freeform's non-uniform stretch) and flip flags (Mirror H/V).
struct FloatingTransform: Equatable {
    var position: CGPoint
    var scaleX: CGFloat
    var scaleY: CGFloat
    var rotation: CGFloat // radians
    var flipH: Bool = false
    var flipV: Bool = false

    static let identity = FloatingTransform(position: .zero, scaleX: 1, scaleY: 1, rotation: 0)

    /// Maps the piece's own local space (centered on its own origin, unrotated, unflipped) into
    /// canvas space.
    var affineTransform: CGAffineTransform {
        CGAffineTransform.identity
            .translatedBy(x: position.x, y: position.y)
            .rotated(by: rotation)
            .scaledBy(x: scaleX * (flipH ? -1 : 1), y: scaleY * (flipV ? -1 : 1))
    }
}

enum FloatingPieceKind {
    /// Target cel == source cel; the source shows a transparent hole (a render-time preview, not
    /// yet written into the model) while this piece floats above it.
    case move
    /// Target is a newly-inserted layer; the source layer is left untouched (a true copy).
    case duplicate
}

/// A piece of pixel content lifted out for interactive move/resize/rotate, not yet committed back
/// into a `Cel.bakedImage`. Purely transient UI state — never persisted (see `CanvasManager.
/// commitFloatingPieceIfNeeded`, called before saving and whenever the layer/frame changes).
/// Keyed by stable UUID rather than array index — see `Selection`'s doc comment for why.
struct FloatingPiece {
    var kind: FloatingPieceKind
    var sourceLayerID: UUID
    var sourceCelID: UUID
    var targetLayerID: UUID
    var targetCelID: UUID

    /// The extracted content, cropped to its own bounding box: `pieceImage`'s bounds map directly
    /// onto `baseSize` centered at the origin, before `transform` is applied.
    var pieceImage: UIImage
    var baseSize: CGSize

    /// What the source cel should render instead of its real `bakedImage`/`drawing` while this piece
    /// is floating. Nil for `.duplicate`, where the source isn't touched at all.
    var remainderPreview: UIImage?

    var transform: FloatingTransform
    var mode: TransformMode

    /// Bounding box of the transformed piece in canvas space — used to hit-test "tap outside to
    /// commit" and to lay out handles.
    var transformedBounds: CGRect {
        let half = CGSize(width: baseSize.width / 2, height: baseSize.height / 2)
        let localCorners = [
            CGPoint(x: -half.width, y: -half.height), CGPoint(x: half.width, y: -half.height),
            CGPoint(x: -half.width, y: half.height), CGPoint(x: half.width, y: half.height)
        ]
        let corners = localCorners.map { $0.applying(transform.affineTransform) }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}

// MARK: - CanvasManager operations

extension CanvasManager {
    /// Resolves a stable layer UUID back to its current array index — `layers` gets reordered/
    /// spliced by delete, insert, and (eventually) drag-to-reorder, so callers holding onto a
    /// `Selection`/`FloatingPiece`'s ID must re-look-up the index every time rather than caching it.
    func layerIndex(ofID id: UUID) -> Int? {
        layers.firstIndex { $0.id == id }
    }

    /// Called whenever `currentLayerIndex`/`currentFrame` change (see the `didSet`s in
    /// CanvasManager.swift), and explicitly by `deleteLayer` since it can leave
    /// `currentLayerIndex`'s numeric value unchanged while the layer it now points at is a
    /// different one (no `didSet` fires in that case). A pending floating piece is committed —
    /// never silently discarded — if the active cel actually changed; an active selection tied to
    /// a now-inactive cel is cleared. Same-cel frame ticks (scrubbing within one cel's frame
    /// range) intentionally leave both alone.
    func handleActiveContextChanged() {
        // A still-adjustable fill can't follow the user to another cel — finalize it here so it lands
        // as a committed "Fill" step on the global history before the context moves on.
        // commitInteractiveFill self-guards.
        commitInteractiveFill()
        let activeLayerID = layers.indices.contains(currentLayerIndex) ? layers[currentLayerIndex].id : nil
        let activeCel = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame)
        let activeCelID = activeCel.map { layers[currentLayerIndex].cels[$0].id }
        if let piece = floatingPiece {
            let stillTargeted = piece.targetLayerID == activeLayerID && piece.targetCelID == activeCelID
            if !stillTargeted {
                commitFloatingPieceIfNeeded()
            }
        }
        if let sel = selection, !(sel.layerID == activeLayerID && sel.celID == activeCelID) {
            selection = nil
        }
        // Leaving the layer/frame ends any in-progress vector-layer transform.
        if isVectorTransforming { isVectorTransforming = false }
    }

    // MARK: Making a selection

    func beginSelection(mode: SelectionMode) {
        commitFloatingPieceIfNeeded()
        selectionMode = mode
    }

    func finishSelection(path: CGPath) {
        guard let canvasSize, layers.indices.contains(currentLayerIndex),
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame) else { return }
        let bounds = path.boundingBoxOfPath.intersection(CGRect(origin: .zero, size: canvasSize))
        guard bounds.width > 1, bounds.height > 1 else { return }
        selection = Selection(path: path, bounds: bounds, layerID: layers[currentLayerIndex].id, celID: layers[currentLayerIndex].cels[celIndex].id)
    }

    func finishAutomaticSelection(at point: CGPoint) {
        guard let canvasSize, layers.indices.contains(currentLayerIndex),
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame) else { return }
        let image = PixelOps.rasterize(cel: layers[currentLayerIndex].cels[celIndex], canvasSize: canvasSize)
        guard let path = PixelOps.floodFillMask(image: image, point: point, tolerance: magicWandTolerance) else { return }
        finishSelection(path: path)
    }

    func deselect() {
        selection = nil
    }

    // MARK: Move / Duplicate — lifting into a floating piece

    /// Begins transforming the current selection (or, if there isn't one, the whole current layer),
    /// in place: the source cel immediately shows a transparent hole where the piece was lifted from.
    func beginMove() {
        commitFloatingPieceIfNeeded()
        guard let canvasSize, layers.indices.contains(currentLayerIndex),
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame) else { return }

        let cel = layers[currentLayerIndex].cels[celIndex]
        let fullImage = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let path = selection?.path ?? CGPath(rect: canvasRect, transform: nil)
        let bounds = (selection?.bounds ?? canvasRect).intersection(canvasRect)
        guard bounds.width > 0, bounds.height > 0 else { return }

        let (rawPiece, remainder) = PixelOps.maskedPiece(image: fullImage, path: path)
        guard let croppedPiece = PixelOps.crop(rawPiece, to: bounds) else { return }

        let sourceLayerID = layers[currentLayerIndex].id
        let sourceCelID = cel.id
        floatingPiece = FloatingPiece(
            kind: .move,
            sourceLayerID: sourceLayerID, sourceCelID: sourceCelID,
            targetLayerID: sourceLayerID, targetCelID: sourceCelID,
            pieceImage: croppedPiece, baseSize: bounds.size,
            remainderPreview: remainder,
            transform: FloatingTransform(position: CGPoint(x: bounds.midX, y: bounds.midY), scaleX: 1, scaleY: 1, rotation: 0),
            mode: transformMode
        )
        selection = nil
    }

    /// Copies the current selection onto a brand-new layer above the current one, immediately
    /// entering the same interactive move/resize/rotate state as `beginMove()`. The source layer is
    /// left untouched — this is a copy, not a cut.
    func beginDuplicate() {
        guard let selection, let canvasSize,
              layers.indices.contains(currentLayerIndex) else { return }
        commitFloatingPieceIfNeeded()

        let sourceLayerIndex = currentLayerIndex
        guard let celIndex = activeCelIndex(inLayer: sourceLayerIndex, atFrame: currentFrame) else { return }
        let cel = layers[sourceLayerIndex].cels[celIndex]
        let fullImage = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
        let bounds = selection.bounds.intersection(CGRect(origin: .zero, size: canvasSize))
        guard bounds.width > 0, bounds.height > 0 else { return }

        let (rawPiece, _) = PixelOps.maskedPiece(image: fullImage, path: selection.path)
        guard let croppedPiece = PixelOps.crop(rawPiece, to: bounds) else { return }

        let sourceLayerID = layers[sourceLayerIndex].id
        let sourceCelID = cel.id
        let newCel = Cel(id: UUID(), startFrame: 0, frameCount: max(sceneFrameCount, 1), raster: .empty(size: canvasSize))
        let newLayer = Layer(id: UUID(), name: "Layer \(layers.count + 1)", opacity: 1.0, isVisible: true, cels: [newCel])
        let insertIndex = sourceLayerIndex + 1
        layers.insert(newLayer, at: insertIndex)
        currentLayerIndex = insertIndex // triggers handleActiveContextChanged, but floatingPiece is still nil here

        self.selection = nil
        floatingPiece = FloatingPiece(
            kind: .duplicate,
            sourceLayerID: sourceLayerID, sourceCelID: sourceCelID,
            targetLayerID: newLayer.id, targetCelID: newCel.id,
            pieceImage: croppedPiece, baseSize: bounds.size,
            remainderPreview: nil,
            transform: FloatingTransform(position: CGPoint(x: bounds.midX, y: bounds.midY), scaleX: 1, scaleY: 1, rotation: 0),
            mode: transformMode
        )
    }

    // MARK: Adjusting the floating piece

    func updateFloatingTransform(_ transform: FloatingTransform) {
        floatingPiece?.transform = transform
    }

    func setTransformMode(_ mode: TransformMode) {
        transformMode = mode
        floatingPiece?.mode = mode
    }

    func mirrorFloating(horizontal: Bool) {
        guard floatingPiece != nil else { return }
        if horizontal { floatingPiece!.transform.flipH.toggle() } else { floatingPiece!.transform.flipV.toggle() }
    }

    func rotateFloating90(clockwise: Bool) {
        guard floatingPiece != nil else { return }
        floatingPiece!.transform.rotation += clockwise ? .pi / 2 : -.pi / 2
    }

    // MARK: Committing

    /// Renders the floating piece at its current transform and bakes it into its target cel, as one
    /// undoable step. No-op if there's nothing floating.
    @discardableResult
    func commitFloatingPieceIfNeeded() -> Bool {
        guard let piece = floatingPiece, let canvasSize else { return false }
        floatingPiece = nil
        guard let targetLayerIndex = layerIndex(ofID: piece.targetLayerID),
              let targetCelIndex = layers[targetLayerIndex].cels.firstIndex(where: { $0.id == piece.targetCelID }) else { return true }

        let rendered = PixelOps.render(floatingPiece: piece, into: canvasSize)
        let targetCel = layers[targetLayerIndex].cels[targetCelIndex]

        switch piece.kind {
        case .move:
            // remainderPreview was rendered from PixelOps.rasterize (see beginMove), which already
            // folds fillImage into it — so fillImage's old content is now baked into newBaked and
            // must be cleared here, or it would render a second time underneath.
            let baseForComposite = piece.remainderPreview ?? targetCel.bakedImage
            let newBaked = PixelOps.compositeOver(base: baseForComposite, overlay: rendered)
            registerUndoableCelChange(layerID: layers[targetLayerIndex].id, celID: targetCel.id,
                                       oldRaster: targetCel.raster, oldBaked: targetCel.bakedImage, oldFill: targetCel.fillImage,
                                       newRaster: .empty(size: canvasSize), newBaked: newBaked, newFill: nil,
                                       actionName: "Move")
        case .duplicate:
            let newBaked = PixelOps.compositeOver(base: targetCel.bakedImage, overlay: rendered)
            registerUndoableLayerInsertion(layerIndex: targetLayerIndex, finalBaked: newBaked, actionName: "Duplicate")
        }
        return true
    }

    // MARK: Fill / Clear (one-shot pixel edits on the current selection)

    func fillSelection() {
        guard let selection, let canvasSize,
              layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].id == selection.layerID,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              layers[currentLayerIndex].cels[celIndex].id == selection.celID else { return }
        let cel = layers[currentLayerIndex].cels[celIndex]
        let isVector = layers[currentLayerIndex].kind == .vector
        if isVector, let vectorCanvas = cel.vector {
            let fillsBefore = vectorCanvas.fills
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
            brushColor.resolvedUIColor(opacity: brushOpacity).getRed(&r, green: &g, blue: &b, alpha: &a)
            let element = VectorFillElement(path: selection.path, color: CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a)))
            vectorCanvas.addFill(element)
            setFillImage(layerIndex: currentLayerIndex, celIndex: celIndex, image: (nil as UIImage?))
            registerVectorFillUndo(vectorCanvas: vectorCanvas, oldFills: fillsBefore, newFills: vectorCanvas.fills,
                                   layerID: layers[currentLayerIndex].id, celID: cel.id, actionName: "Fill")
        } else {
            let base = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
            let newImage = PixelOps.fill(base: base, path: selection.path, color: PixelOps.uiColor(from: brushColor))
            registerUndoableCelChange(layerID: layers[currentLayerIndex].id, celID: cel.id,
                                       oldRaster: cel.raster, oldBaked: cel.bakedImage, oldFill: cel.fillImage,
                                       newRaster: .empty(size: canvasSize), newBaked: newImage, newFill: nil, actionName: "Fill")
        }
    }

    func clearSelectionPixels() {
        guard let selection, let canvasSize,
              layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].id == selection.layerID,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              layers[currentLayerIndex].cels[celIndex].id == selection.celID else { return }
        let cel = layers[currentLayerIndex].cels[celIndex]
        let isVector = layers[currentLayerIndex].kind == .vector
        if isVector, let vectorCanvas = cel.vector {
            let fillsBefore = vectorCanvas.fills
            var newFills: [VectorFillElement] = []
            for fill in fillsBefore {
                guard let path = fill.cgPath else { continue }
                let clipped = Self.clipPath(path, excluding: selection.path)
                newFills.append(VectorFillElement(path: clipped, color: fill.color, opacity: fill.opacity, evenOddFill: true))
            }
            vectorCanvas.fills = newFills
            vectorCanvas.bumpVersion()
            setFillImage(layerIndex: currentLayerIndex, celIndex: celIndex, image: (nil as UIImage?))
            registerVectorFillUndo(vectorCanvas: vectorCanvas, oldFills: fillsBefore, newFills: vectorCanvas.fills,
                                   layerID: layers[currentLayerIndex].id, celID: cel.id, actionName: "Clear")
        } else {
            let base = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
            let newImage = PixelOps.clear(base: base, path: selection.path)
            registerUndoableCelChange(layerID: layers[currentLayerIndex].id, celID: cel.id,
                                       oldRaster: cel.raster, oldBaked: cel.bakedImage, oldFill: cel.fillImage,
                                       newRaster: .empty(size: canvasSize), newBaked: newImage, newFill: nil, actionName: "Clear")
        }
    }

    /// Subtracts `excludePath` from `path` by composing them into a single even-odd filled path
    /// (the overlapping region becomes a hole). Returns nil if the result is empty.
    private static func clipPath(_ path: CGPath, excluding excludePath: CGPath) -> CGPath {
        let combined = CGMutablePath()
        combined.addPath(path)
        combined.addPath(excludePath)
        return combined
    }

    // MARK: Undo-integrated mutation helpers

    /// Applies a cel's raster/bakedImage/fillImage change and registers it as one step on the
    /// global `history`, so the existing Undo/Redo buttons cover it too. Every call site must
    /// state `oldFill`/`newFill` explicitly (rather than defaulting to "leave untouched") since
    /// silently leaving a stale fillImage in place is exactly the double-composite bug this
    /// parameter exists to prevent — see the callers' comments.
    ///
    /// `oldRaster`/`newRaster` are `RasterLayerTexture` instances captured by reference, not
    /// copied: once a cel's `raster` field is reassigned away from `oldRaster` here, nothing keeps
    /// drawing into that instance, so it's safe for undo/redo to swap it back in later without a
    /// snapshot. `layerID`/`celID` (rather than indices) are what the undo/redo closures resolve
    /// against — other edits may shift array positions between now and whenever undo/redo fires.
    func registerUndoableCelChange(layerID: UUID, celID: UUID,
                                    oldRaster: RasterLayerTexture, oldBaked: UIImage?, oldFill: UIImage?,
                                    newRaster: RasterLayerTexture, newBaked: UIImage?, newFill: UIImage?,
                                    actionName: String) {
        applyCelChange(layerID: layerID, celID: celID, raster: newRaster, baked: newBaked, fill: newFill)
        registerCelReversal(layerID: layerID, celID: celID,
                            undoRaster: oldRaster, undoBaked: oldBaked, undoFill: oldFill,
                            redoRaster: newRaster, redoBaked: newBaked, redoFill: newFill,
                            actionName: actionName)
    }

    /// Registers one step on the global `history` that reverts to the `undo*` state, or (on redo)
    /// restores the `redo*` state — `UndoHistory` moves the same action between its two stacks, so
    /// unlike the old per-layer `UndoManager` idiom this doesn't need to re-register itself.
    private func registerCelReversal(layerID: UUID, celID: UUID,
                                     undoRaster: RasterLayerTexture, undoBaked: UIImage?, undoFill: UIImage?,
                                     redoRaster: RasterLayerTexture, redoBaked: UIImage?, redoFill: UIImage?,
                                     actionName: String) {
        let cost = Self.approximateImageCost(undoBaked) + Self.approximateImageCost(redoBaked)
                 + Self.approximateImageCost(undoFill) + Self.approximateImageCost(redoFill)
        recordUndo(name: actionName, cost: cost, undo: { [weak self] in
            self?.applyCelChange(layerID: layerID, celID: celID, raster: undoRaster, baked: undoBaked, fill: undoFill)
        }, redo: { [weak self] in
            self?.applyCelChange(layerID: layerID, celID: celID, raster: redoRaster, baked: redoBaked, fill: redoFill)
        })
    }

    private func applyCelChange(layerID: UUID, celID: UUID, raster: RasterLayerTexture, baked: UIImage?, fill: UIImage?) {
        guard let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
              let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) else { return }
        layers[layerIndex].cels[celIndex].fillImage = fill
        layers[layerIndex].cels[celIndex].raster = raster
        layers[layerIndex].cels[celIndex].bakedImage = baked
        scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIndex)
    }

    /// Same idea as `registerUndoableCelChange`, but for Duplicate: the undoable unit is the whole
    /// new layer's existence, not just one cel's content. The undo side removes it by ID (safe even
    /// if other layers have since shifted its index); the redo side re-inserts at the position it
    /// was originally created at, which is safe because `history`'s redo stack only ever holds this
    /// action while nothing else has been recorded in between (any new edit clears it).
    private func registerUndoableLayerInsertion(layerIndex: Int, finalBaked: UIImage, actionName: String) {
        guard layers.indices.contains(layerIndex) else { return }
        layers[layerIndex].cels[0].bakedImage = finalBaked
        scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: 0)
        let insertedLayer = layers[layerIndex]
        let insertedLayerID = insertedLayer.id

        recordUndo(name: actionName, cost: Self.approximateImageCost(finalBaked), undo: { [weak self] in
            guard let self, let idx = self.layers.firstIndex(where: { $0.id == insertedLayerID }) else { return }
            self.layers.remove(at: idx)
            if self.currentLayerIndex >= self.layers.count {
                self.currentLayerIndex = max(0, self.layers.count - 1)
            }
        }, redo: { [weak self] in
            guard let self else { return }
            let insertAt = min(layerIndex, self.layers.count)
            self.layers.insert(insertedLayer, at: insertAt)
            self.currentLayerIndex = insertAt
        })
    }
}
