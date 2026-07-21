import SwiftUI
import PencilKit
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
/// `CanvasManager.handleActiveContextChanged`).
struct Selection {
    var path: CGPath
    var bounds: CGRect
    var layerIndex: Int
    var celIndex: Int
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
struct FloatingPiece {
    var kind: FloatingPieceKind
    var sourceLayerIndex: Int
    var sourceCelIndex: Int
    var targetLayerIndex: Int
    var targetCelIndex: Int

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
    /// Called whenever `currentLayerIndex`/`currentFrame` change (see the `didSet`s in
    /// CanvasManager.swift). A pending floating piece is committed — never silently discarded — if
    /// the active cel actually changed; an active selection tied to a now-inactive cel is cleared.
    /// Same-cel frame ticks (scrubbing within one cel's frame range) intentionally leave both alone.
    func handleActiveContextChanged() {
        let activeCel = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame)
        if let piece = floatingPiece {
            let stillTargeted = piece.targetLayerIndex == currentLayerIndex && activeCel == piece.targetCelIndex
            if !stillTargeted {
                commitFloatingPieceIfNeeded()
            }
        }
        if let sel = selection, !(sel.layerIndex == currentLayerIndex && activeCel == sel.celIndex) {
            selection = nil
        }
    }

    // MARK: Making a selection

    func beginSelection(mode: SelectionMode) {
        commitFloatingPieceIfNeeded()
        selectionMode = mode
    }

    func finishSelection(path: CGPath) {
        guard let canvasSize, let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame) else { return }
        let bounds = path.boundingBoxOfPath.intersection(CGRect(origin: .zero, size: canvasSize))
        guard bounds.width > 1, bounds.height > 1 else { return }
        selection = Selection(path: path, bounds: bounds, layerIndex: currentLayerIndex, celIndex: celIndex)
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

        floatingPiece = FloatingPiece(
            kind: .move,
            sourceLayerIndex: currentLayerIndex, sourceCelIndex: celIndex,
            targetLayerIndex: currentLayerIndex, targetCelIndex: celIndex,
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

        let newCel = Cel(id: UUID(), startFrame: 0, frameCount: max(sceneFrameCount, 1), drawing: PKDrawing())
        let newLayer = Layer(id: UUID(), name: "Layer \(layers.count + 1)", opacity: 1.0, isVisible: true, cels: [newCel])
        let insertIndex = sourceLayerIndex + 1
        layers.insert(newLayer, at: insertIndex)
        currentLayerIndex = insertIndex // triggers handleActiveContextChanged, but floatingPiece is still nil here

        self.selection = nil
        floatingPiece = FloatingPiece(
            kind: .duplicate,
            sourceLayerIndex: sourceLayerIndex, sourceCelIndex: celIndex,
            targetLayerIndex: insertIndex, targetCelIndex: 0,
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
        guard layers.indices.contains(piece.targetLayerIndex),
              layers[piece.targetLayerIndex].cels.indices.contains(piece.targetCelIndex) else { return true }

        let rendered = PixelOps.render(floatingPiece: piece, into: canvasSize)
        let targetCel = layers[piece.targetLayerIndex].cels[piece.targetCelIndex]

        switch piece.kind {
        case .move:
            let baseForComposite = piece.remainderPreview ?? targetCel.bakedImage
            let newBaked = PixelOps.compositeOver(base: baseForComposite, overlay: rendered)
            registerUndoableCelChange(layerIndex: piece.targetLayerIndex, celIndex: piece.targetCelIndex,
                                       oldDrawing: targetCel.drawing, oldBaked: targetCel.bakedImage,
                                       newDrawing: PKDrawing(), newBaked: newBaked, actionName: "Move")
        case .duplicate:
            let newBaked = PixelOps.compositeOver(base: targetCel.bakedImage, overlay: rendered)
            registerUndoableLayerInsertion(layerIndex: piece.targetLayerIndex, finalBaked: newBaked, actionName: "Duplicate")
        }
        return true
    }

    // MARK: Fill / Clear (one-shot pixel edits on the current selection)

    func fillSelection() {
        guard let selection, let canvasSize,
              currentLayerIndex == selection.layerIndex,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              celIndex == selection.celIndex else { return }
        let cel = layers[currentLayerIndex].cels[celIndex]
        let base = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
        let newImage = PixelOps.fill(base: base, path: selection.path, color: PixelOps.uiColor(from: brushColor))
        registerUndoableCelChange(layerIndex: currentLayerIndex, celIndex: celIndex,
                                   oldDrawing: cel.drawing, oldBaked: cel.bakedImage,
                                   newDrawing: PKDrawing(), newBaked: newImage, actionName: "Fill")
    }

    func clearSelectionPixels() {
        guard let selection, let canvasSize,
              currentLayerIndex == selection.layerIndex,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              celIndex == selection.celIndex else { return }
        let cel = layers[currentLayerIndex].cels[celIndex]
        let base = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
        let newImage = PixelOps.clear(base: base, path: selection.path)
        registerUndoableCelChange(layerIndex: currentLayerIndex, celIndex: celIndex,
                                   oldDrawing: cel.drawing, oldBaked: cel.bakedImage,
                                   newDrawing: PKDrawing(), newBaked: newImage, actionName: "Clear")
    }

    // MARK: Undo-integrated mutation helpers

    /// Applies a cel's drawing/bakedImage change and registers it as one undo step against the same
    /// `UndoManager` PencilKit strokes already use, so the existing Undo/Redo buttons cover it too.
    func registerUndoableCelChange(layerIndex: Int, celIndex: Int,
                                    oldDrawing: PKDrawing, oldBaked: UIImage?,
                                    newDrawing: PKDrawing, newBaked: UIImage?,
                                    actionName: String) {
        applyCelChange(layerIndex: layerIndex, celIndex: celIndex, drawing: newDrawing, baked: newBaked)
        activeUndoManager?.setActionName(actionName)
        activeUndoManager?.registerUndo(withTarget: self) { target in
            target.applyCelChange(layerIndex: layerIndex, celIndex: celIndex, drawing: oldDrawing, baked: oldBaked)
            target.activeUndoManager?.setActionName(actionName)
            target.activeUndoManager?.registerUndo(withTarget: target) { redoTarget in
                redoTarget.applyCelChange(layerIndex: layerIndex, celIndex: celIndex, drawing: newDrawing, baked: newBaked)
            }
        }
        refreshUndoRedoState()
    }

    private func applyCelChange(layerIndex: Int, celIndex: Int, drawing: PKDrawing, baked: UIImage?) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        layers[layerIndex].cels[celIndex].drawing = drawing
        layers[layerIndex].cels[celIndex].bakedImage = baked
        scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIndex)
    }

    /// Same idea as `registerUndoableCelChange`, but for Duplicate: the undoable unit is the whole
    /// new layer's existence, not just one cel's content.
    private func registerUndoableLayerInsertion(layerIndex: Int, finalBaked: UIImage, actionName: String) {
        guard layers.indices.contains(layerIndex) else { return }
        layers[layerIndex].cels[0].bakedImage = finalBaked
        scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: 0)
        let insertedLayer = layers[layerIndex]

        activeUndoManager?.setActionName(actionName)
        activeUndoManager?.registerUndo(withTarget: self) { target in
            guard target.layers.indices.contains(layerIndex) else { return }
            target.layers.remove(at: layerIndex)
            if target.currentLayerIndex >= target.layers.count {
                target.currentLayerIndex = max(0, target.layers.count - 1)
            }
            target.activeUndoManager?.setActionName(actionName)
            target.activeUndoManager?.registerUndo(withTarget: target) { redoTarget in
                let insertAt = min(layerIndex, redoTarget.layers.count)
                redoTarget.layers.insert(insertedLayer, at: insertAt)
                redoTarget.currentLayerIndex = insertAt
            }
        }
        refreshUndoRedoState()
    }
}
