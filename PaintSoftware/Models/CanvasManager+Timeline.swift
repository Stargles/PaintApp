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
    /// nearest cel that begins at or after it so the two can't overlap. Nil when there's no room at
    /// all (the caller then does nothing).
    ///
    /// Shared by the three cel creators — `addCel`, `duplicateCel` and `pasteCel` — which each held
    /// a byte-identical copy of this before.
    ///
    /// The filter is `>=`, not `>`. It used to be strict, which made a neighbour beginning at
    /// *exactly* `startFrame` invisible to the clamp — and that is precisely `duplicateCel`'s start
    /// frame, since it copies to the source cel's `endFrame`. With no `activeCelIndex(...) == nil`
    /// guard in front of it either (unlike the other two), duplicating a cel whose neighbour started
    /// at its end frame produced two cels covering the same frames, one of them unreachable but
    /// still rendered. See BUGS.md. Fixed here rather than by adding a fourth guard, so the single
    /// shared chokepoint can no longer hand any caller an overlapping range.
    ///
    /// `>=` is a no-op for `addCel` and `pasteCel`: both are fronted by
    /// `guard activeCelIndex(inLayer:atFrame: startFrame) == nil`, and `activeCelIndex` matches on
    /// `frame >= cel.startFrame && frame < cel.endFrame`, so a cel starting exactly at `startFrame`
    /// is always found by that guard (every cel has `frameCount >= 1` — the creators reject
    /// non-positive lengths here, and `resizeCel*`/`splitCel` all clamp to at least one frame). They
    /// return early and never reach this function with that value.
    func clampedCelLength(layerIndex: Int, startFrame: Int, maxLength: Int) -> Int? {
        var length = maxLength
        let laterStarts = layers[layerIndex].cels.map(\.startFrame).filter { $0 >= startFrame }
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
            let size = canvasSize ?? CGSize(width: 1, height: 1)
            // A new cel on a `.vector` layer needs its own `VectorCanvas`, exactly as the one
            // `addVectorLayer` creates does. Without it the cel has nowhere to put vector content, so
            // `StrokeCanvasView` silently falls back to raster mode and the drawing lands as pixels on
            // a vector layer — invisible to the eraser's geometric modes, to save/load's vector
            // payload, and to interpolation, which reads `cel.vector` and finds nothing.
            let cel = Cel(id: UUID(), startFrame: startFrame, frameCount: length,
                          raster: .empty(size: size),
                          vector: layers[layerIndex].kind == .vector ? .empty(size: size) : nil)
            layers[layerIndex].cels.append(cel)
            layers[layerIndex].cels.sort { $0.startFrame < $1.startFrame }
            sceneFrameCount = max(sceneFrameCount, startFrame + length)
            if let idx = activeCelIndex(inLayer: layerIndex, atFrame: startFrame) {
                scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: idx)
            }
        }
        return true
    }

    /// Copies a cel immediately after itself, at the source's `endFrame`, clamped to whatever room is
    /// free before the next cel.
    ///
    /// When a neighbour begins at *exactly* the source's end frame there is no free space at all, so
    /// `clampedCelLength` returns nil and this is a no-op. That is deliberate — see BUGS.md — and it
    /// is currently silent; a UI affordance for it is logged there as a low-priority follow-up.
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
                scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: idx)
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
                scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: idx)
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
        // Clamped at the next block's start rather than left to `resizeCelRightEdge`'s own ceiling:
        // that one pushes into the neighbour, which is right for a deliberate edge drag but not for
        // a menu item whose whole promise is "fill the empty space after this".
        let stop = neighborBounds(layerIndex: layerIndex, celIndex: celIndex).upperBound
        withStructureUndo(name: "Extend Frame") {
            resizeCelRightEdge(layerIndex: layerIndex, celIndex: celIndex,
                               newEndFrame: min(stop, max(sceneFrameCount, cel.endFrame)))
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
            scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIndex)
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

    /// The block immediately after `celIndex` on the same layer, if any. Cels never overlap, so
    /// "after" is just the smallest start frame among the ones that don't begin before this cel.
    private func nextCelIndex(layerIndex: Int, after celIndex: Int) -> Int? {
        let cel = layers[layerIndex].cels[celIndex]
        return layers[layerIndex].cels.indices
            .filter { $0 != celIndex && layers[layerIndex].cels[$0].startFrame >= cel.startFrame }
            .min { layers[layerIndex].cels[$0].startFrame < layers[layerIndex].cels[$1].startFrame }
    }

    /// The block immediately before `celIndex` on the same layer, if any.
    private func previousCelIndex(layerIndex: Int, before celIndex: Int) -> Int? {
        let cel = layers[layerIndex].cels[celIndex]
        return layers[layerIndex].cels.indices
            .filter { $0 != celIndex && layers[layerIndex].cels[$0].endFrame <= cel.startFrame }
            .max { layers[layerIndex].cels[$0].endFrame < layers[layerIndex].cels[$1].endFrame }
    }

    /// Drag the block's left edge: keeps the right edge fixed, changes startFrame/frameCount.
    /// Deliberately NOT wrapped in `withStructureUndo` here — `TimelineTrackView`'s pan handler
    /// calls this on every `.changed` event of the drag, so it brackets the whole gesture itself
    /// with `beginStructureGesture()`/`commitStructureGesture(name:)` instead of one step per call.
    ///
    /// Dragging past the block before it doesn't stop at that block — it pushes into it, and the
    /// neighbour gives up frames from its trailing edge. See `resizeCelRightEdge` for the floor.
    func resizeCelLeftEdge(layerIndex: Int, celIndex: Int, newStartFrame: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let cel = layers[layerIndex].cels[celIndex]
        let previous = previousCelIndex(layerIndex: layerIndex, before: celIndex)
        let floor = previous.map { layers[layerIndex].cels[$0].startFrame + 1 } ?? 0
        let clampedStart = max(floor, min(newStartFrame, cel.endFrame - 1))

        layers[layerIndex].cels[celIndex].startFrame = clampedStart
        layers[layerIndex].cels[celIndex].frameCount = cel.endFrame - clampedStart

        if let previous, layers[layerIndex].cels[previous].endFrame > clampedStart {
            layers[layerIndex].cels[previous].frameCount =
                clampedStart - layers[layerIndex].cels[previous].startFrame
        }
    }

    /// Drag the block's right edge: keeps the left edge fixed, changes frameCount only. Also used
    /// (as a one-shot call, not a gesture) by `extendCelToEnd`, which supplies its own undo wrap
    /// since this method doesn't register one itself — see `resizeCelLeftEdge`'s comment.
    ///
    /// Extending block A into block B shrinks B from its leading edge rather than stopping A dead at
    /// B's start. B's floor is one frame — a block can't be squeezed out of existence, so A stops at
    /// `B.endFrame - 1`, and a B that is *already* one frame long is an immovable wall. Pulling A
    /// back afterwards leaves B where the push put it (a gap opens instead), which is how timeline
    /// editors generally behave: the push is an edit to B, not a temporary displacement.
    func resizeCelRightEdge(layerIndex: Int, celIndex: Int, newEndFrame: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let cel = layers[layerIndex].cels[celIndex]
        let next = nextCelIndex(layerIndex: layerIndex, after: celIndex)
        let ceiling = next.map { layers[layerIndex].cels[$0].endFrame - 1 } ?? Int.max
        let clampedEnd = min(ceiling, max(newEndFrame, cel.startFrame + 1))

        layers[layerIndex].cels[celIndex].frameCount = clampedEnd - cel.startFrame

        if let next, layers[layerIndex].cels[next].startFrame < clampedEnd {
            let neighbour = layers[layerIndex].cels[next]
            layers[layerIndex].cels[next].startFrame = clampedEnd
            layers[layerIndex].cels[next].frameCount = neighbour.endFrame - clampedEnd
        }

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
                scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: idx)
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
