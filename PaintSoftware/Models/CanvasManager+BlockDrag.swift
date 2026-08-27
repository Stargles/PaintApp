import UIKit

// MARK: - Dragging blocks around the timeline
//
// Three motions, one gesture. Picking a block up and putting it down can mean:
//
//   * **re-time it** — same layer, same order, just earlier or later. `moveCel` already did this
//     and still does; it is the only one of the three that clamps against its neighbours.
//   * **shuffle it** — same layer, different *position in the sequence*. Dragging block 3 back past
//     block 2 makes it block 2. Clamping is exactly wrong here: the neighbour is not a wall, it is
//     the thing being traded places with.
//   * **re-home it** — a different layer entirely, subject to the kind rules below.
//
// Which one a drop means is decided from where the finger let go (`TimelineTrackView`), never from
// a mode the artist has to select first.

extension CanvasManager {

    /// Whether a block may be dropped on a layer, and what it costs.
    ///
    /// The asymmetry is the point. A vector block *can* become a raster one — rasterizing is a
    /// well-defined, total operation — but it is lossy and irreversible-in-spirit, so it asks first.
    /// A raster block cannot become a vector one at all: there is no honest way to recover strokes
    /// from pixels, and silently dropping a raster block onto a vector layer would either strand
    /// pixels on a layer whose tools cannot touch them or quietly discard them.
    enum CelDropVerdict: Equatable {
        /// Kinds match (or the block is empty of vector content and the target is raster).
        case allowed
        /// A vector block landing on a raster layer: allowed, but its geometry is flattened to
        /// pixels on the way in, so the artist is asked to confirm.
        case needsRasterization
        /// A raster block landing on a vector layer. Refused outright.
        case rejected(reason: String)
    }

    /// A drop the artist has been asked to confirm, held between the gesture ending and the alert
    /// being answered. Addressed by identity, not by index: the alert is presented across a SwiftUI
    /// update, and a layer or block index can be renumbered by anything that happens in between.
    struct CelDropRequest: Equatable {
        var celID: UUID
        var sourceLayerID: UUID
        var targetLayerID: UUID
        var startFrame: Int
    }

    /// Does this block hold vector geometry? Asked of the *block*, not its layer: a layer that was
    /// rasterized still has `kind == .raster` on every cel, and a cel carries its own tier.
    private func celIsVector(_ cel: Cel) -> Bool {
        cel.vector != nil
    }

    func celDropVerdict(celID: UUID, fromLayer sourceLayerID: UUID, toLayer targetLayerID: UUID) -> CelDropVerdict {
        guard let sourceIndex = layers.firstIndex(where: { $0.id == sourceLayerID }),
              let targetIndex = layers.firstIndex(where: { $0.id == targetLayerID }),
              let celIndex = layers[sourceIndex].cels.firstIndex(where: { $0.id == celID }) else {
            return .rejected(reason: "That block is no longer there.")
        }
        if sourceLayerID == targetLayerID { return .allowed }

        // A layer's last block may not leave it. Every other cel path maintains "a layer always has
        // at least one cel" (see `deleteCel`); a layer with none is undrawable and renders blank
        // forever, so this refuses rather than silently leaving one behind.
        guard layers[sourceIndex].cels.count > 1 else {
            return .rejected(reason: "A layer must keep at least one block. Add another block before moving this one away.")
        }

        let cel = layers[sourceIndex].cels[celIndex]
        switch (celIsVector(cel), layers[targetIndex].kind) {
        case (true, .raster):
            return .needsRasterization
        case (false, .vector):
            return .rejected(reason: "A raster block can't be moved onto a vector layer — its pixels have no strokes to become.")
        default:
            return .allowed
        }
    }

    // MARK: - Shuffle within a layer

    /// The layer's blocks in time order, as indices into `cels`.
    private func orderedCelIndices(layerIndex: Int) -> [Int] {
        layers[layerIndex].cels.indices.sorted { layers[layerIndex].cels[$0].startFrame < layers[layerIndex].cels[$1].startFrame }
    }

    /// Where a block dropped so its leading edge sits at `startFrame` lands in the layer's running
    /// order: how many *other* blocks begin before it.
    ///
    /// Measured against each other block's midpoint rather than its start, so a block has to be
    /// dragged past the *middle* of its neighbour to trade places with it. Against the start, the
    /// order would flip the instant the leading edges crossed by one frame, which makes a small
    /// nudge near a boundary feel like the timeline is snatching blocks around.
    func celInsertionIndex(layerIndex: Int, celIndex: Int, startFrame: Int) -> Int {
        let ordered = orderedCelIndices(layerIndex: layerIndex).filter { $0 != celIndex }
        return ordered.filter { other in
            let cel = layers[layerIndex].cels[other]
            return CGFloat(cel.startFrame) + CGFloat(cel.frameCount) / 2 <= CGFloat(startFrame)
        }.count
    }

    /// The dragged block's own current position in that running order.
    func celOrderIndex(layerIndex: Int, celIndex: Int) -> Int? {
        orderedCelIndices(layerIndex: layerIndex).firstIndex(of: celIndex)
    }

    /// Re-orders one block within its layer, keeping the run's timing.
    ///
    /// Each block keeps its own length, and the *gaps* keep their positions in the sequence: gap 0
    /// stays the gap after the first block, whichever block that now is. So shuffling changes which
    /// drawing plays when without disturbing the rhythm the artist spaced out — which is the whole
    /// reason to shuffle rather than to drag each block by hand.
    ///
    /// The run is re-laid-out from the first block's original start frame, so a shuffle never drifts
    /// the animation earlier or later in time.
    func shuffleCel(layerIndex: Int, celIndex: Int, toOrderIndex: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let ordered = orderedCelIndices(layerIndex: layerIndex)
        guard ordered.count > 1, let from = ordered.firstIndex(of: celIndex) else { return }
        let to = min(max(toOrderIndex, 0), ordered.count - 1)
        guard to != from else { return }

        // Slot geometry, read off the run as it stands: where it starts, and the gap that follows
        // each position in it.
        let blocks = ordered.map { layers[layerIndex].cels[$0] }
        let origin = blocks[0].startFrame
        let gaps = zip(blocks, blocks.dropFirst()).map { $0.1.startFrame - $0.0.endFrame }

        // Two statements, not `permuted.insert(permuted.remove(at: from), at: to)`: that reads and
        // mutates `permuted` in one expression, which is an overlapping exclusive access.
        var permuted = ordered
        let moved = permuted.remove(at: from)
        permuted.insert(moved, at: to)

        withStructureUndo(label: .shuffleFrame) {
            var cursor = origin
            for (position, index) in permuted.enumerated() {
                layers[layerIndex].cels[index].startFrame = cursor
                cursor += layers[layerIndex].cels[index].frameCount
                if position < gaps.count { cursor += gaps[position] }
            }
            layers[layerIndex].cels.sort { $0.startFrame < $1.startFrame }
            sceneFrameCount = max(sceneFrameCount, cursor)
        }
    }

    // MARK: - Move to another layer

    /// Moves a block to another layer, landing its leading edge as close to `startFrame` as the
    /// target's existing blocks allow.
    ///
    /// Returns false when the drop is refused (see `celDropVerdict`) — the caller then leaves the
    /// block where it was rather than dropping it somewhere unexpected.
    ///
    /// `rasterizing` must be true for a vector block landing on a raster layer; the view layer only
    /// passes it once the artist has confirmed. Passing false for such a drop refuses it, so a
    /// confirmation cannot be skipped by calling straight into the model.
    @discardableResult
    func moveCelToLayer(celID: UUID, fromLayer sourceLayerID: UUID, toLayer targetLayerID: UUID,
                        startFrame: Int, rasterizing: Bool = false) -> Bool {
        let verdict = celDropVerdict(celID: celID, fromLayer: sourceLayerID, toLayer: targetLayerID)
        switch verdict {
        case .rejected:
            return false
        case .needsRasterization where !rasterizing:
            return false
        case .allowed, .needsRasterization:
            break
        }
        guard let sourceIndex = layers.firstIndex(where: { $0.id == sourceLayerID }),
              let targetIndex = layers.firstIndex(where: { $0.id == targetLayerID }),
              let celIndex = layers[sourceIndex].cels.firstIndex(where: { $0.id == celID }) else { return false }
        guard sourceIndex != targetIndex else { return false }
        // No canvas, no rasterization — and a vector block landing on a raster layer with its
        // geometry still attached would be a cel the target layer's tools cannot touch. Refuse
        // instead, rather than moving it into a state nothing can edit.
        if case .needsRasterization = verdict, canvasSize == nil { return false }
        // A block that is about to be flattened takes `rasterizeLayer`'s hazard with it: the
        // `PixelOps.rasterize` below honours a float's suppression and `cel.vector = nil` then
        // destroys the geometry, so a float still open on this cel is baked away as a hole — the
        // whole cel, once Move with no selection lifts every id. Settled before the scope, as there.
        commitVectorFloatIfLifted(fromLayer: sourceLayerID, cel: celID)

        withStructureUndo(label: .moveFrameToLayer) {
            var cel = layers[sourceIndex].cels.remove(at: celIndex)

            if case .needsRasterization = verdict, let canvasSize {
                // Flatten every tier the block carries into `raster` — the one tier a raster layer's
                // eraser can reach. Same rule `rasterizeLayer` follows: a raster cel holds its
                // content in exactly one tier at rest.
                let flattened = PixelOps.rasterize(cel: cel, canvasSize: canvasSize)
                cel.raster = bakedRasterTexture(image: flattened, likeExisting: cel.raster)
                cel.vector = nil
                cel.fillImage = nil
                cel.bakedImage = nil
                // A recipe that re-poses geometry has nothing left to re-pose.
                if cel.interpolation?.mode == .reproject { cel.interpolation = nil }
            }

            cel.startFrame = landingFrame(inLayer: targetIndex, startFrame: startFrame)
            layers[targetIndex].cels.append(cel)
            layers[targetIndex].cels.sort { $0.startFrame < $1.startFrame }
            pushOverlappingCels(inLayer: targetIndex, after: cel.id)

            // Recipes address a cel as (layer, cel) — see `CelRef` — so a block that changes layers
            // takes every reference to it along, or the keyframes it feeds silently stop resolving.
            retargetInterpolationReferences(celID: celID, from: sourceLayerID, to: targetLayerID)

            if let moved = layers[targetIndex].cels.firstIndex(where: { $0.id == celID }) {
                scheduleThumbnailRegen(layerIndex: targetIndex, celIndex: moved)
            }
            sceneFrameCount = max(sceneFrameCount, layers[targetIndex].cels.map(\.endFrame).max() ?? 0)
            currentLayerIndex = targetIndex
        }
        return true
    }

    /// Where a block dropped at `startFrame` actually lands on a layer: never straddling the block
    /// it was dropped onto, so it either takes that block's place or follows it. Whatever it
    /// displaces is pushed along afterwards rather than overwritten (`pushOverlappingCels`).
    private func landingFrame(inLayer layerIndex: Int, startFrame: Int) -> Int {
        var landing = max(startFrame, 0)
        for cel in layers[layerIndex].cels.sorted(by: { $0.startFrame < $1.startFrame }) {
            // Dropped inside an existing block: land after it if the finger was past its midpoint,
            // otherwise take its place and push it along.
            guard landing >= cel.startFrame, landing < cel.endFrame else { continue }
            let midpoint = cel.startFrame + cel.frameCount / 2
            landing = landing >= midpoint ? cel.endFrame : cel.startFrame
        }
        return landing
    }

    /// Slides blocks later until nothing overlaps the newly-landed one, preserving their order and
    /// their lengths. Only ever pushes forward: a drop adds content to a layer, so the blocks that
    /// were already there make room rather than being trimmed away.
    private func pushOverlappingCels(inLayer layerIndex: Int, after celID: UUID) {
        guard let landedIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) else { return }
        let landed = layers[layerIndex].cels[landedIndex]

        // Selected by start frame rather than by position in the sorted order, and with `>=` so a
        // block the newcomer landed exactly on top of is included. Two cels sharing a start frame
        // sort against each other arbitrarily, so a position-based walk could start *after* the very
        // block it needs to push and leave the overlap in place.
        let following = layers[layerIndex].cels.indices
            .filter { $0 != landedIndex && layers[layerIndex].cels[$0].startFrame >= landed.startFrame }
            .sorted { layers[layerIndex].cels[$0].startFrame < layers[layerIndex].cels[$1].startFrame }

        var cursor = landed.endFrame
        for index in following {
            let cel = layers[layerIndex].cels[index]
            guard cel.startFrame < cursor else { cursor = cel.endFrame; continue }
            layers[layerIndex].cels[index].startFrame = cursor
            cursor += cel.frameCount
        }
        layers[layerIndex].cels.sort { $0.startFrame < $1.startFrame }
    }

    /// Re-points every interpolation reference to a cel that has changed layers.
    ///
    /// A `CelRef` is a (layer, cel) pair, so moving a block between layers invalidates the layer
    /// half of every reference to it. Left stale, `isWellFormed` still passes — the reference count
    /// is unchanged — and the recipe simply evaluates against a cel that no longer resolves, which
    /// shows up as an in-between quietly rendering wrong rather than as an error.
    private func retargetInterpolationReferences(celID: UUID, from oldLayerID: UUID, to newLayerID: UUID) {
        let stale = CelRef(layerID: oldLayerID, celID: celID)
        for layerIndex in layers.indices {
            for celIndex in layers[layerIndex].cels.indices {
                guard var recipe = layers[layerIndex].cels[celIndex].interpolation else { continue }
                var changed = false
                for referenceIndex in recipe.references.indices {
                    for refIndex in recipe.references[referenceIndex].cels.indices
                    where recipe.references[referenceIndex].cels[refIndex] == stale {
                        recipe.references[referenceIndex].cels[refIndex].layerID = newLayerID
                        changed = true
                    }
                }
                if changed { layers[layerIndex].cels[celIndex].interpolation = recipe }
            }
        }
    }
}
