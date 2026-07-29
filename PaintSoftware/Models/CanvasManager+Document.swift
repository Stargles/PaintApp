import SwiftUI
import UIKit

// MARK: - Document
//
// Whole-canvas operations: the drawable padding margin around the artwork, and mirroring the canvas.
// Both rewrite every cel's buffers in place and so are deliberately not undoable. Extracted from
// CanvasManager.swift as an extension — all state still lives on the class itself (see that file's
// header), so every view binding is unchanged.

extension CanvasManager {

    /// Sets the light-grey drawable margin around the artwork, resizing every layer/cel buffer so the
    /// existing artwork stays centred (a uniform translate — no resampling of vector content, and
    /// raster/baked/fill content is re-placed at the offset). Growing the margin shifts content by a
    /// positive offset; shrinking crops whatever falls outside the new bounds. Not undoable — buffer
    /// dimensions change, so the active layer's stroke-undo stack is cleared (inactive layers' stacks
    /// clear on next activation, see `updateActiveLayerAndTool`).
    func setCanvasPadding(_ newPadding: CGFloat) {
        guard let oldSize = canvasSize else { return }
        let clamped = min(max(newPadding, Self.canvasPaddingRange.lowerBound), Self.canvasPaddingRange.upperBound)
        let delta = clamped - canvasPadding
        guard delta != 0 else { return }

        // Every transient buffer here is canvas-sized, so all of them have to be baked before the
        // size changes underneath them (a shape/fill preview rendered at the old size would land
        // mis-scaled once it eventually committed).
        commitAllInteractiveState()
        selection = nil

        let offset = CGPoint(x: delta, y: delta)
        let newSize = CGSize(width: oldSize.width + 2 * delta, height: oldSize.height + 2 * delta)

        for layerIndex in layers.indices {
            for celIndex in layers[layerIndex].cels.indices {
                layers[layerIndex].cels[celIndex].raster =
                    layers[layerIndex].cels[celIndex].raster.resized(to: newSize, offset: offset)
                if let fill = layers[layerIndex].cels[celIndex].fillImage {
                    layers[layerIndex].cels[celIndex].fillImage = PixelOps.resizedCanvasImage(fill, to: newSize, offset: offset)
                }
                if let baked = layers[layerIndex].cels[celIndex].bakedImage {
                    layers[layerIndex].cels[celIndex].bakedImage = PixelOps.resizedCanvasImage(baked, to: newSize, offset: offset)
                }
                if let vector = layers[layerIndex].cels[celIndex].vector {
                    layers[layerIndex].cels[celIndex].vector = vector.resized(to: newSize, offset: offset)
                }
            }
        }

        canvasSize = newSize
        canvasPadding = clamped

        history.removeAll()
        refreshUndoRedoState()
        regenerateAllThumbnails()
    }

    func flipCanvas(horizontal: Bool) {
        guard let canvasSize else { return }
        // Mirroring is a canvas edit: bake first, or the pending shape/fill would commit afterwards
        // at its un-mirrored geometry, landing on the wrong side of the canvas it was drawn on.
        commitAllInteractiveState()
        for layerIndex in layers.indices {
            for celIndex in layers[layerIndex].cels.indices {
                layers[layerIndex].cels[celIndex].raster = layers[layerIndex].cels[celIndex].raster.flipped(horizontal: horizontal)
                if let fillImage = layers[layerIndex].cels[celIndex].fillImage {
                    layers[layerIndex].cels[celIndex].fillImage = Self.flippedImage(fillImage, canvasSize: canvasSize, horizontal: horizontal)
                }
                if let bakedImage = layers[layerIndex].cels[celIndex].bakedImage {
                    layers[layerIndex].cels[celIndex].bakedImage = Self.flippedImage(bakedImage, canvasSize: canvasSize, horizontal: horizontal)
                }
            }
            // NOTE: vector-layer content (strokes/shapes/fills/images, all stored as geometry in
            // `cel.vector` — see `VectorCanvas`) is not mirrored by this loop at all, unlike
            // raster/fillImage/bakedImage above. This predates object layers being retired; a vector
            // layer's live strokes already didn't flip. Flagged as a follow-up, not fixed here.
        }
        // Not undoable, same as setCanvasPadding: every cel's raster/fill/baked content is mirrored
        // in place, so any undo entry recorded before the flip would restore content in the wrong
        // (pre-flip) orientation if left on the stack.
        history.removeAll()
        refreshUndoRedoState()
        regenerateAllThumbnails()
    }

    /// Mirrors a cel's raster content (fillImage or bakedImage) about the canvas center, so a flipped
    /// canvas doesn't leave raster content behind on the wrong side.
    ///
    /// The geometry itself lives in `RasterLayerTexture.flippedImage` — this used to hold a second
    /// copy of the same translate+scale, which had to be kept in step by hand with the one the
    /// live-stroke tier uses. All this adds is the backing-image guard: a `UIImage` with no `cgImage`
    /// has nothing to mirror, and the caller drops the buffer rather than storing a blank one.
    private static func flippedImage(_ image: UIImage, canvasSize: CGSize, horizontal: Bool) -> UIImage? {
        guard image.cgImage != nil else { return nil }
        return RasterLayerTexture.flippedImage(image, canvasSize: canvasSize, horizontal: horizontal)
    }
}
