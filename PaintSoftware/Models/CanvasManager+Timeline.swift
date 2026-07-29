import SwiftUI
import UIKit

// MARK: - Cels / timeline
//
// Cel CRUD: creating, copying, deleting, resizing and splitting the blocks that make up a layer's
// track in the animation timeline. Extracted from CanvasManager.swift as an extension — all state
// still lives on the class itself (see that file's header), so every view binding is unchanged.

extension CanvasManager {

    func activeCelIndex(inLayer layerIndex: Int, atFrame frame: Int) -> Int? {
        guard layers.indices.contains(layerIndex) else { return nil }
        return layers[layerIndex].cels.firstIndex { frame >= $0.startFrame && frame < $0.startFrame + $0.frameCount }
    }

    /// How long a new cel starting at `startFrame` may actually be: `maxLength`, cut short by the
    /// nearest cel that begins after it so the two can't overlap. Nil when there's no room at all
    /// (the caller then does nothing).
    ///
    /// Shared by the three cel creators — `addCel`, `duplicateCel` and `pasteCel` — which each held
    /// a byte-identical copy of this before. Note the filter is strictly `>`: a neighbour beginning
    /// at exactly `startFrame` is not treated as a bound. That matters for `duplicateCel`, whose
    /// start frame is the source's `endFrame`, i.e. precisely the value this excludes — see the
    /// overlap issue recorded in BUGS.md and pinned by
    /// `testDuplicatingIntoAnImmediatelyAdjacentNeighbourOverlapsIt`. Preserved deliberately: this
    /// extraction is behaviour-preserving, and fixing that is a separate change.
    func clampedCelLength(layerIndex: Int, startFrame: Int, maxLength: Int) -> Int? {
        var length = maxLength
        let laterStarts = layers[layerIndex].cels.map(\.startFrame).filter { $0 > startFrame }
        if let nextStart = laterStarts.min() {
            length = min(length, nextStart - startFrame)
        }
        return length > 0 ? length : nil
    }

    @discardableResult
    func addCel(layerIndex: Int, startFrame: Int, frameCount: Int = 1) -> Bool {
        guard layers.indices.contains(layerIndex) else { return false }
        guard activeCelIndex(inLayer: layerIndex, atFrame: startFrame) == nil else { return false }
        guard let length = clampedCelLength(layerIndex: layerIndex, startFrame: startFrame, maxLength: frameCount) else { return false }
        withStructureUndo(name: "Add Frame") {
            let cel = Cel(id: UUID(), startFrame: startFrame, frameCount: length, raster: .empty(size: canvasSize ?? CGSize(width: 1, height: 1)))
            layers[layerIndex].cels.append(cel)
            layers[layerIndex].cels.sort { $0.startFrame < $1.startFrame }
            sceneFrameCount = max(sceneFrameCount, startFrame + length)
            if let idx = activeCelIndex(inLayer: layerIndex, atFrame: startFrame) {
                regenerateThumbnail(layerIndex: layerIndex, celIndex: idx)
            }
        }
        return true
    }

    func duplicateCel(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let source = layers[layerIndex].cels[celIndex]
        let newStart = source.endFrame
        guard let length = clampedCelLength(layerIndex: layerIndex, startFrame: newStart, maxLength: source.frameCount) else { return }
        withStructureUndo(name: "Duplicate Frame") {
            let newCel = Cel(id: UUID(), startFrame: newStart, frameCount: length, raster: source.raster.makeCopy(), fillImage: source.fillImage, bakedImage: source.bakedImage, vector: source.vector?.makeCopy())
            layers[layerIndex].cels.append(newCel)
            layers[layerIndex].cels.sort { $0.startFrame < $1.startFrame }
            sceneFrameCount = max(sceneFrameCount, newStart + length)
            if let idx = activeCelIndex(inLayer: layerIndex, atFrame: newStart) {
                regenerateThumbnail(layerIndex: layerIndex, celIndex: idx)
            }
        }
    }

    /// Snapshots a cel's content (not its position) onto a single clipboard slot, for `pasteCel` to
    /// drop into an empty slot elsewhere. Unlike `duplicateCel` this doesn't touch the timeline at
    /// all — copy and paste are two separate steps, matching the gap-tap "Add Drawing / Paste" menu.
    func copyCel(layerIndex: Int, celIndex: Int) {
        // Copying doesn't change the canvas, but it does snapshot the cel's tiers — including a
        // still-transient fill preview, which `pasteCel` would then plant in the new cel as
        // permanent content while the original fill bakes separately into the source. Bake first so
        // what's copied is what's actually committed.
        beginCanvasEdit()
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let source = layers[layerIndex].cels[celIndex]
        copiedCel = CopiedCel(raster: source.raster.makeCopy(), fillImage: source.fillImage,
                              bakedImage: source.bakedImage, vector: source.vector?.makeCopy(),
                              frameCount: source.frameCount)
    }

    /// Drops the clipboard's content into an empty slot as a new cel, sized to the copied cel's own
    /// length (clamped, like `addCel`, to whatever room is actually free before the next cel).
    @discardableResult
    func pasteCel(layerIndex: Int, startFrame: Int) -> Bool {
        guard let copiedCel, layers.indices.contains(layerIndex) else { return false }
        guard activeCelIndex(inLayer: layerIndex, atFrame: startFrame) == nil else { return false }
        guard let length = clampedCelLength(layerIndex: layerIndex, startFrame: startFrame, maxLength: copiedCel.frameCount) else { return false }
        withStructureUndo(name: "Paste Frame") {
            let newCel = Cel(id: UUID(), startFrame: startFrame, frameCount: length,
                             raster: copiedCel.raster.makeCopy(), fillImage: copiedCel.fillImage,
                             bakedImage: copiedCel.bakedImage, vector: copiedCel.vector?.makeCopy())
            layers[layerIndex].cels.append(newCel)
            layers[layerIndex].cels.sort { $0.startFrame < $1.startFrame }
            sceneFrameCount = max(sceneFrameCount, startFrame + length)
            if let idx = activeCelIndex(inLayer: layerIndex, atFrame: startFrame) {
                regenerateThumbnail(layerIndex: layerIndex, celIndex: idx)
            }
        }
        return true
    }

    /// A layer must always keep at least one cel to stay drawable — every other cel-creating path
    /// (addLayer, addVectorLayer, beginDuplicate, ...) already maintains that invariant, so this is a
    /// no-op on a layer's last remaining cel rather than leaving it with zero (which made
    /// `activeCelIndex` return nil everywhere, permanently blanking the layer and its thumbnail).
    /// Use `clearCel` to empty a cel's content while keeping it.
    func deleteCel(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex),
              layers[layerIndex].cels.count > 1 else { return }
        withStructureUndo(name: "Delete Frame") {
            layers[layerIndex].cels.remove(at: celIndex)
        }
    }

    func extendCelToEnd(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let cel = layers[layerIndex].cels[celIndex]
        withStructureUndo(name: "Extend Frame") {
            resizeCelRightEdge(layerIndex: layerIndex, celIndex: celIndex, newEndFrame: max(sceneFrameCount, cel.endFrame))
        }
    }

    func clearCel(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        withStructureUndo(name: "Clear Frame") {
            let size = canvasSize ?? CGSize(width: 1, height: 1)
            layers[layerIndex].cels[celIndex].raster = .empty(size: size)
            layers[layerIndex].cels[celIndex].fillImage = nil
            layers[layerIndex].cels[celIndex].bakedImage = nil
            if layers[layerIndex].cels[celIndex].vector != nil {
                layers[layerIndex].cels[celIndex].vector = .empty(size: size)
            }
            regenerateThumbnail(layerIndex: layerIndex, celIndex: celIndex)
        }
    }

    /// The open frame range a cel is allowed to occupy, bounded by its neighbors in the same layer.
    private func neighborBounds(layerIndex: Int, celIndex: Int) -> (lowerBound: Int, upperBound: Int) {
        let cel = layers[layerIndex].cels[celIndex]
        let others = layers[layerIndex].cels.enumerated().filter { $0.offset != celIndex }
        let lower = others.map(\.element).filter { $0.endFrame <= cel.startFrame }.map(\.endFrame).max() ?? 0
        let upper = others.map(\.element).filter { $0.startFrame >= cel.startFrame }.map(\.startFrame).min()
        return (lower, upper ?? Int.max)
    }

    /// Drag the block's left edge: keeps the right edge fixed, changes startFrame/frameCount.
    /// Deliberately NOT wrapped in `withStructureUndo` here — `TimelineTrackView`'s pan handler
    /// calls this on every `.changed` event of the drag, so it brackets the whole gesture itself
    /// with `beginStructureGesture()`/`commitStructureGesture(name:)` instead of one step per call.
    func resizeCelLeftEdge(layerIndex: Int, celIndex: Int, newStartFrame: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let cel = layers[layerIndex].cels[celIndex]
        let bounds = neighborBounds(layerIndex: layerIndex, celIndex: celIndex)
        let clampedStart = max(bounds.lowerBound, min(newStartFrame, cel.endFrame - 1))
        layers[layerIndex].cels[celIndex].startFrame = clampedStart
        layers[layerIndex].cels[celIndex].frameCount = cel.endFrame - clampedStart
    }

    /// Drag the block's right edge: keeps the left edge fixed, changes frameCount only. Also used
    /// (as a one-shot call, not a gesture) by `extendCelToEnd`, which supplies its own undo wrap
    /// since this method doesn't register one itself — see `resizeCelLeftEdge`'s comment.
    func resizeCelRightEdge(layerIndex: Int, celIndex: Int, newEndFrame: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let cel = layers[layerIndex].cels[celIndex]
        let bounds = neighborBounds(layerIndex: layerIndex, celIndex: celIndex)
        let clampedEnd = min(bounds.upperBound, max(newEndFrame, cel.startFrame + 1))
        layers[layerIndex].cels[celIndex].frameCount = clampedEnd - cel.startFrame
        sceneFrameCount = max(sceneFrameCount, clampedEnd)
    }

    /// Drag the block body: repositions it (startFrame changes, length unchanged), clamped to not
    /// overlap neighbors. Not wrapped here either — see `resizeCelLeftEdge`'s comment.
    func moveCel(layerIndex: Int, celIndex: Int, newStartFrame: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let cel = layers[layerIndex].cels[celIndex]
        let bounds = neighborBounds(layerIndex: layerIndex, celIndex: celIndex)
        let maxStart = (bounds.upperBound == Int.max) ? Int.max : bounds.upperBound - cel.frameCount
        let clampedStart = max(bounds.lowerBound, min(newStartFrame, max(bounds.lowerBound, maxStart)))
        layers[layerIndex].cels[celIndex].startFrame = clampedStart
        sceneFrameCount = max(sceneFrameCount, clampedStart + cel.frameCount)
    }

    /// Splits a cel into two at `atFrame` (strictly inside the cel); both halves keep the original drawing.
    func splitCel(layerIndex: Int, celIndex: Int, atFrame: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let cel = layers[layerIndex].cels[celIndex]
        guard atFrame > cel.startFrame, atFrame < cel.endFrame else { return }
        withStructureUndo(name: "Split Frame") {
            layers[layerIndex].cels[celIndex].frameCount = atFrame - cel.startFrame
            let secondHalf = Cel(id: UUID(), startFrame: atFrame, frameCount: cel.endFrame - atFrame, raster: cel.raster.makeCopy(), fillImage: cel.fillImage, bakedImage: cel.bakedImage, vector: cel.vector?.makeCopy())
            layers[layerIndex].cels.append(secondHalf)
            layers[layerIndex].cels.sort { $0.startFrame < $1.startFrame }
            if let idx = activeCelIndex(inLayer: layerIndex, atFrame: atFrame) {
                regenerateThumbnail(layerIndex: layerIndex, celIndex: idx)
            }
        }
    }

    /// "Attach a new block to the end" of the given cel: a fresh blank cel immediately following it.
    @discardableResult
    func addBlankCelAfter(layerIndex: Int, celIndex: Int, length: Int = 1) -> Bool {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return false }
        let cel = layers[layerIndex].cels[celIndex]
        return addCel(layerIndex: layerIndex, startFrame: cel.endFrame, frameCount: length)
    }
}
