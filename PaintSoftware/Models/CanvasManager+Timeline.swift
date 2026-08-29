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

    /// The cel at `currentFrame` on `layerIndex`, **creating a one-frame block there if the frame is
    /// empty**. Returns nil only when the layer index is bad or there is genuinely no room.
    ///
    /// This is what makes drawing on a blank frame work. Every drawing path is gated on
    /// `activeCelIndex` returning something, so parking the playhead on a frame no block covers used
    /// to leave the canvas inert — the touch was swallowed by a layer host that had no raster behind
    /// it and the stroke went nowhere, which reads as the app being broken rather than as "there is
    /// nothing here to draw on". Drawing on an empty frame is a perfectly clear instruction, so it
    /// now means what it says: the block is created and the stroke lands in it.
    ///
    /// One frame long, not stretched to fill the gap: a new drawing is a new drawing, and
    /// `resizeCelRightEdge`/"Extend to End" are how it gets longer. `addCel` already clamps the
    /// length against the next block and gives a `.vector` layer's cel its own `VectorCanvas`, so a
    /// block spawned on a vector layer is a vector block.
    @discardableResult
    func ensureCelAtCurrentFrame(layerIndex: Int) -> Int? {
        guard layers.indices.contains(layerIndex) else { return nil }
        if let existing = activeCelIndex(inLayer: layerIndex, atFrame: currentFrame) { return existing }
        addCel(layerIndex: layerIndex, startFrame: currentFrame, frameCount: 1)
        return activeCelIndex(inLayer: layerIndex, atFrame: currentFrame)
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
        withStructureUndo(label: .addFrame) {
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
        // Cel/block spawn. Worth a line of its own because it usually happens *implicitly* — drawing
        // on an empty frame spawns a block from inside `onStrokeBegan` (see
        // `Coordinator.attachSpawnedCelIfFrameIsEmpty`), so a recording showing a stroke followed by
        // a cel appearing is showing something the artist never asked for by name.
        recordLayerStackChange("added cel on layer \(layerIndex) at frame \(startFrame), length \(frameCount)")
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
        withStructureUndo(label: .duplicateFrame) {
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
        withStructureUndo(label: .pasteFrame) {
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
        withStructureUndo(label: .deleteFrame) {
            layers[layerIndex].cels.remove(at: celIndex)
        }
    }

    /// **The frames one cel block covers, half-open**, or nil if that block is not there any more.
    ///
    /// The bounds check is the point as much as the arithmetic: a menu can outlive the block it was
    /// raised on (undo, another gesture), and a caller that subscripted `cels` directly would trap.
    /// Half-open because that is what every frame-range writer here takes — `clearKeyframes(_:inFrames:)`
    /// most immediately — and because `endFrame` is already the frame *after* the last one drawn.
    func celFrameRange(layerIndex: Int, celIndex: Int) -> Range<Int>? {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex) else { return nil }
        let cel = layers[layerIndex].cels[celIndex]
        return cel.startFrame ..< cel.endFrame
    }

    func extendCelToEnd(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let cel = layers[layerIndex].cels[celIndex]
        // Clamped here at the next block's start rather than left to `resizeCelRightEdge`, which no
        // longer has a ceiling of its own to fall back on — it now pushes a neighbour (and whatever
        // is past it) out of the way instead of stopping at it, on the strength of being a deliberate
        // edge drag the artist is watching happen. A menu item is not that: its whole promise is
        // "fill the empty space after this," so it still needs its own stop, and this clamp is now
        // the only thing standing between it and pushing every block after it down the timeline.
        let stop = neighborBounds(layerIndex: layerIndex, celIndex: celIndex).upperBound
        withStructureUndo(label: .extendFrame) {
            resizeCelRightEdge(layerIndex: layerIndex, celIndex: celIndex,
                               newEndFrame: min(stop, max(sceneFrameCount, cel.endFrame)))
        }
    }

    func clearCel(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        // The cel's `vector` is about to be replaced by a fresh empty one, so a float lifted from
        // this cel would leave its suppression on the old canvas — which the undo snapshot still
        // holds, so undoing the clear would give back a cel whose ink renders nowhere. Same shape as
        // `rasterizeLayer`'s, and the settle has to precede the scope for the same reason.
        commitVectorFloatIfLifted(fromLayer: layers[layerIndex].id,
                                  cel: layers[layerIndex].cels[celIndex].id)
        withStructureUndo(label: .clearFrame) {
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

    /// Drag the block's left edge: keeps the right edge fixed, changes startFrame/frameCount.
    /// Deliberately NOT wrapped in `withStructureUndo` here — `TimelineTrackView`'s pan handler
    /// calls this on every `.changed` event of the drag, so it brackets the whole gesture itself
    /// with `beginStructureGesture()`/`commitStructureGesture(label:)` instead of one step per call.
    ///
    /// **This replaces the old contract, on the owner's explicit instruction, not an oversight.**
    /// It used to stop the drag dead at `previous.startFrame + 1`, shrinking the previous block from
    /// its trailing edge — argued at the time as "how timeline editors generally behave." The owner
    /// disagreed: with two-or-more blocks side by side, extending one into a neighbour is now
    /// supposed to shove that neighbour out of the way, keeping its own length, rather than eat into
    /// it or wall the drag off. So: dragging past the block before this one translates it earlier by
    /// the overlap, `frameCount` unchanged, and — new, since a chain of one-frame blocks used to each
    /// be their own immovable wall — keeps walking earlier through however many further blocks the
    /// push reaches, translating each one in turn. See `resizeCelRightEdge`'s comment for the mirror
    /// image and for why every push is computed from a fixed baseline rather than the live model.
    ///
    /// The one direction `resizeCelRightEdge` doesn't have to answer for: frame 0. A block dragged
    /// far enough left eventually asks something to occupy a negative frame, which doesn't exist.
    /// Two ways to fail to do that: stop the resize once it would (what this does), or let it happen
    /// and clip/wrap silently. Silent clipping was rejected — it would mean the previous block's
    /// reported length disagrees with what the handle visually did, which is a worse bug than the
    /// resize just refusing to go further, and "refusing to go further" is exactly what a floor at
    /// frame 0 already reads as everywhere else in this file (a cel can't be squeezed below one
    /// frame; this is the same shape, applied to the timeline's own edge instead of a neighbour's
    /// minimum length).
    func resizeCelLeftEdge(layerIndex: Int, celIndex: Int, newStartFrame: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        // Baseline for every position in this call — the resized cel's own anchor (its endFrame,
        // which this edge never moves) and every predecessor's untouched start/length — comes from
        // `gestureSnapshot` when a drag has one open, not from `layers` as it currently stands. See
        // `resizeCelRightEdge`'s comment for why: reading the live (already-pushed) state here is
        // exactly the bug that made dragging out and back not restore the neighbours.
        let baseline = gestureSnapshot?.layers ?? layers
        guard baseline.indices.contains(layerIndex), baseline[layerIndex].cels.indices.contains(celIndex) else { return }
        let baselineCel = baseline[layerIndex].cels[celIndex]
        let requestedStart = min(newStartFrame, baselineCel.endFrame - 1)

        // Predecessors this push could reach, nearest first — the direction the cascade walks.
        let predecessors = baseline[layerIndex].cels.enumerated()
            .filter { $0.offset != celIndex && $0.element.endFrame <= baselineCel.startFrame }
            .sorted { $0.element.startFrame > $1.element.startFrame }

        // Provisional cascade at the *requested* start, before the frame-0 floor is applied: walk
        // the predecessors nearest first, and push each one whose baseline end the resize would
        // overlap so its new end sits exactly at the running cursor, then continue from its new
        // (earlier) start. The first predecessor the cursor doesn't reach stops the walk — cels never
        // overlap each other at baseline, so if that one isn't pushed, nothing further back is either.
        var provisional: [(index: Int, newStart: Int, frameCount: Int)] = []
        var cursor = requestedStart
        for (index, predecessor) in predecessors {
            guard predecessor.endFrame > cursor else { break }
            let newStart = cursor - predecessor.frameCount
            provisional.append((index, newStart, predecessor.frameCount))
            cursor = newStart
        }

        // `cursor` is now the leading edge of whichever block this push reaches furthest — the
        // resized block itself if it reached no predecessor, or the earliest pushed predecessor
        // otherwise. Below 0 there's nowhere for it to go, so the *entire* provisional cascade,
        // resized block included, is shifted later by exactly the shortfall. Shifting the whole
        // cascade uniformly can't introduce a new overlap with an un-pushed predecessor further back:
        // the cascade only ever moves later by this shift, i.e. away from them, never toward.
        let deficit = max(0, -cursor)
        let clampedStart = requestedStart + deficit

        layers[layerIndex].cels[celIndex].startFrame = clampedStart
        layers[layerIndex].cels[celIndex].frameCount = baselineCel.endFrame - clampedStart

        let pushedIndices = Set(provisional.map(\.index))
        for entry in provisional {
            guard layers[layerIndex].cels.indices.contains(entry.index) else { continue }
            layers[layerIndex].cels[entry.index].startFrame = entry.newStart + deficit
            layers[layerIndex].cels[entry.index].frameCount = entry.frameCount
        }
        // Every predecessor the cascade *didn't* reach this call is written back to its own baseline
        // — not left alone — so a call that pushed it earlier (a bigger drag, or an earlier `.changed`
        // in the same gesture) and then eases off actually gives it back rather than leaving it
        // wherever the largest push so far put it.
        for (index, predecessor) in predecessors where !pushedIndices.contains(index) {
            guard layers[layerIndex].cels.indices.contains(index) else { continue }
            layers[layerIndex].cels[index].startFrame = predecessor.startFrame
            layers[layerIndex].cels[index].frameCount = predecessor.frameCount
        }
    }

    /// Drag the block's right edge: keeps the left edge fixed, changes frameCount only. Also used
    /// (as a one-shot call, not a gesture) by `extendCelToEnd`, which supplies its own undo wrap
    /// since this method doesn't register one itself — see `resizeCelLeftEdge`'s comment.
    ///
    /// **This replaces the old contract, on the owner's explicit instruction, not an oversight.** It
    /// used to clamp at `next.endFrame - 1`, shrinking the next block from its leading edge, with a
    /// one-frame floor that made an already-short neighbour an immovable wall the drag simply
    /// couldn't push past. That was deliberate at the time — the doc comment here argued it matched
    /// how timeline editors generally behave — but two-or-more-blocks-side-by-side is exactly the
    /// case the owner called out: extending the first one right is supposed to make room by carrying
    /// the second one along, not by eating it or stopping at it. So now: extending into a neighbour
    /// translates it right by the overlap, `frameCount` unchanged (so a one-frame block is no longer
    /// a wall — it just moves, one frame and all), and the push is transitive: if the neighbour's own
    /// new position would in turn overlap *its* neighbour, that one moves too, and so on down the row.
    /// There is no ceiling any more (nothing to stop at), so unlike the left edge this direction has
    /// no floor to enforce either — the scene simply grows to fit, same as it already does with no
    /// neighbour at all.
    ///
    /// **Every push below is computed from a baseline, never from the live model, and this is the
    /// point the whole rewrite hinges on.** `TimelineTrackView`'s pan handler calls this on every
    /// `.changed` event with the SAME already-open gesture — `beginStructureGesture()` at `.began`,
    /// this on every touch-move, `commitStructureGesture(label:)` at `.ended`. A version that read the
    /// neighbour's *current* (possibly already-pushed) position each time was tried first and drifts:
    /// call 1 pushes B forward, call 2 sees B already forward and, once the finger reverses, has no
    /// way to tell "B moved because of an earlier bigger push in this same drag" from "B was drawn
    /// there to begin with" — so retracting the drag back to zero left B stranded downstream instead
    /// of restoring it, because every push only ever ratcheted forward and nothing ever undid one.
    /// `gestureSnapshot` (see `CanvasManager+Undo.swift`) already exists for exactly this shape of
    /// problem and is already captured at `.began` by the same `beginStructureGesture()` call the
    /// resize handles use for undo — reading pushes from it, instead of from `layers`, means every
    /// `.changed` event recomputes the *whole* result fresh from where the gesture started, so an
    /// out-and-back drag lands every block exactly where it began. Outside a gesture (a one-shot call
    /// from a test, or from `extendCelToEnd`) `gestureSnapshot` is nil and the live model stands in
    /// for it, which is just "the baseline is wherever things currently are" — correct for a single
    /// call, same as it always was.
    func resizeCelRightEdge(layerIndex: Int, celIndex: Int, newEndFrame: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let baseline = gestureSnapshot?.layers ?? layers
        guard baseline.indices.contains(layerIndex), baseline[layerIndex].cels.indices.contains(celIndex) else { return }
        let baselineCel = baseline[layerIndex].cels[celIndex]
        let clampedEnd = max(newEndFrame, baselineCel.startFrame + 1)

        layers[layerIndex].cels[celIndex].startFrame = baselineCel.startFrame
        layers[layerIndex].cels[celIndex].frameCount = clampedEnd - baselineCel.startFrame

        // Successors this push could reach, nearest first, from the same baseline the resized cel's
        // own new end was just computed from.
        let successors = baseline[layerIndex].cels.enumerated()
            .filter { $0.offset != celIndex && $0.element.startFrame >= baselineCel.endFrame }
            .sorted { $0.element.startFrame < $1.element.startFrame }

        // Walk forward: push every successor the running cursor still overlaps, translating it by
        // however much (frameCount unchanged) and advancing the cursor past it, exactly mirroring the
        // left edge's backward walk. The first successor not overlapped stops the cascade — and every
        // successor at or past that point is written back to its own baseline explicitly, for the
        // same "give it back on retraction" reason `resizeCelLeftEdge` does.
        var cursor = clampedEnd
        var pushing = true
        for (index, successor) in successors {
            guard layers[layerIndex].cels.indices.contains(index) else { continue }
            if pushing, successor.startFrame < cursor {
                layers[layerIndex].cels[index].startFrame = cursor
                layers[layerIndex].cels[index].frameCount = successor.frameCount
                cursor += successor.frameCount
            } else {
                pushing = false
                layers[layerIndex].cels[index].startFrame = successor.startFrame
                layers[layerIndex].cels[index].frameCount = successor.frameCount
            }
        }

        sceneFrameCount = max(sceneFrameCount, cursor)
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
        withStructureUndo(label: .splitFrame) {
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
