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

    /// **The tiers a *copy* of `cel` carries** — the one place the 2026-09-03 ruling on copying a
    /// derived cel lives, read by `duplicateCel` and by `copyCel` so the two verbs cannot drift.
    ///
    /// ## What the ruling is
    ///
    /// A copy of an **in-between** is a **flattened still**: it looks exactly like what the artist
    /// saw, as ordinary ink, and stops following the two drawings it derives from. Until this
    /// existed the three copying verbs carried a cel's `transformTracks` and `pendingPoseBaselines`
    /// but not its `interpolation`, and the entry that filed that said "nothing downstream is broken
    /// today by the recipe being dropped". That was wrong in the worst direction: a `.generate`
    /// in-between **stores nothing at all** (see `PixelOps.rasterizeUncached`, and the block drag's
    /// own note that flattening one without the seam "baked the block away as blank"), so a
    /// duplicate or paste of one came out **blank** rather than as a plain drawing. A `.reproject`
    /// one came out as the artist's linework in its *rest* position, un-reposed — wrong by less, and
    /// wrong the same way.
    ///
    /// ## Through `derivedCelContent`, which is the third and fourth site of a flatten that exists
    ///
    /// `rasterizeLayer` and `moveCelToLayer` already flatten a derived cel this way, and already
    /// drop the recipe afterwards for the reason both state: the frame is stored pixels now, so
    /// leaving the recipe would evaluate the in-between a second time over its own bake.
    ///
    /// ## At `cel.startFrame`, and the choice is free rather than approximate
    ///
    /// The frame is a real question — a duplicate lands at the source's `endFrame` and a paste
    /// wherever the artist tapped, so "the picture the artist saw" need not be the picture at the
    /// start of the span. It is settled by which *arm* of `derivedCelContent` this gate takes.
    /// **The gate is `cel.interpolation != nil`, so the arm is always the interpolation one, and
    /// that arm never reads the frame**: `recipe.t` lives on the cel and is constant across every
    /// frame the cel spans (`CelContentProvider` says so in as many words, and it is why
    /// `InterpolatedCelIdentity` deliberately omits the frame). Every frame of the span therefore
    /// derives the same picture, `startFrame` is the cel's canonical frame everywhere else that asks
    /// — the thumbnail, `rasterizeLayer`, the block drag — and for `copyCel` it is the *only*
    /// available answer, since a clipboard carries no frame at all.
    ///
    /// ## Pose is not applied twice, because on this arm it is not applied at all
    ///
    /// A cel can hold both a recipe and pose channels (`interpolate(mode: .reproject, …)` does not
    /// refuse one on a posed cel, though the pose *writer* refuses the reverse — see
    /// `commitTransformPose` and `poseDeltaForKeyframe`, both §2.18). On such a cel the recipe wins
    /// and the tracks are inert: `derivedCelContent` takes the interpolation arm and never reaches
    /// `posedCelContent`. So the flatten below bakes an **un-posed** frame, and there is no doubled
    /// pose to fear — the hazard runs the other way. Carrying the tracks onto a copy that no longer
    /// has a recipe would make them *newly live*, so the copy would animate where its source stood
    /// still. They are dropped, explicitly rather than by defaulting, because defaulting an
    /// unmentioned field is precisely how these two came to be lost in the first place.
    ///
    /// ## A recipe that is not evaluable at this instant
    ///
    /// `PixelOps.rasterize` falls back to the cel's stored tiers when the thunk answers nil (a
    /// recipe mid-repick), so the copy is then whatever a flatten of that cel produces *at that
    /// instant* — byte-for-byte what its own thumbnail, the onion skin and an export would produce.
    /// That is the property worth having and it is true by construction: this is the same call with
    /// the same arguments, not a second implementation of it.
    ///
    /// Returns nil for a cel that shows what it stores, which is every cel in a document that has
    /// never been interpolated, so the ordinary verb costs one optional test and copies verbatim.
    private func flattenedStill(of cel: Cel) -> Cel.CopyTiers? {
        guard cel.interpolation != nil, let canvasSize,
              let derived = derivedCelContent(for: cel, atFrame: cel.startFrame) else { return nil }
        let flat = PixelOps.rasterize(cel: cel, canvasSize: canvasSize, derived: derived)
        // **Everything lands in `bakedImage` and the other tiers are emptied**, because
        // `PixelOps.rasterize` composited all four of them into `flat` — keeping any of them would
        // draw that content twice. `bakedImage` rather than `raster` is the tier for it here, where
        // `rasterizeLayer` and the block drag chose `raster`: those two are *becoming raster layers*,
        // where a cel holds its content in exactly one tier, while a copy made by these verbs stays
        // on the vector layer it came from, and `Cel.bakedImage` is that layer's tier for "flattened
        // raster content baked in by a pixel-level operation" — a list whose examples already
        // include duplicate.
        //
        // **The vector tier is emptied, not removed.** A vector layer's cel with no `VectorCanvas`
        // is a cel `StrokeCanvasView` silently drops back to raster mode on (`addCel` spells the
        // consequences out), so the artist could not draw on the copy at all. An empty canvas over a
        // baked still is exactly the state a select-and-move bake leaves behind, and new ink lands
        // on top of the still because `rasterizeUncached` draws `bakedImage` first.
        return Cel.CopyTiers(raster: .empty(size: cel.raster.size), fillImage: nil, bakedImage: flat,
                             vector: cel.vector.map { .empty(size: $0.size) },
                             transformTracks: [:], pendingPoseBaselines: [:])
    }

    /// The tiers of a copy of `cel`: the flattened still when it derives its picture, and the cel's
    /// own content otherwise.
    private func copyTiers(of cel: Cel) -> Cel.CopyTiers {
        flattenedStill(of: cel) ?? Cel.CopyTiers(
            raster: cel.raster.makeCopy(), fillImage: cel.fillImage, bakedImage: cel.bakedImage,
            vector: cel.vector?.makeCopy(),
            // **The pose channels come with the drawing** — KEYFRAMES.md §3.1's *"it rides the cel
            // through move, split, duplicate and paste for free"*, which was a claim in
            // `Cel.transformTracks`' own doc comment and not true of these verbs until 2026-09-02:
            // a memberwise `Cel(...)` defaults both fields to `[:]`, so duplicating an animated cel
            // produced a copy of the drawing with the animation silently deleted.
            //
            // **Verbatim, including keys past the copy's length.** A copy can be shorter than its
            // source when a neighbour is in the way, and §3.1's resize rule is the one to follow —
            // *"a key pushed outside the new span is held, not deleted"* — so re-growing the copy
            // gives the animation back rather than finding it trimmed.
            transformTracks: cel.transformTracks, pendingPoseBaselines: cel.pendingPoseBaselines)
    }

    /// Copies a cel immediately after itself, at the source's `endFrame`, clamped to whatever room is
    /// free before the next cel.
    ///
    /// When a neighbour begins at *exactly* the source's end frame there is no free space at all, so
    /// `clampedCelLength` returns nil and this is a no-op. That is deliberate — see BUGS.md — and it
    /// is currently silent; a UI affordance for it is logged there as a low-priority follow-up.
    ///
    /// A copy of an in-between is a flattened still and carries no recipe — see `flattenedStill`.
    func duplicateCel(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let source = layers[layerIndex].cels[celIndex]
        let newStart = source.endFrame
        guard let length = clampedCelLength(layerIndex: layerIndex, startFrame: newStart, maxLength: source.frameCount) else { return }
        let tiers = copyTiers(of: source)
        withStructureUndo(label: .duplicateFrame) {
            // No `interpolation:` argument, on either arm — a copy never derives. On the flatten arm
            // that is the ruling; on the verbatim arm the source had no recipe to carry.
            let newCel = Cel(id: UUID(), startFrame: newStart, frameCount: length, raster: tiers.raster, fillImage: tiers.fillImage, bakedImage: tiers.bakedImage, vector: tiers.vector, transformTracks: tiers.transformTracks, pendingPoseBaselines: tiers.pendingPoseBaselines)
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
    ///
    /// **An in-between is flattened here, at copy, rather than at paste** — which is what makes
    /// `CopiedCel` need no `interpolation` field. The clipboard is already a snapshot (`makeCopy()`
    /// on both class tiers), and a recipe is the one thing that cannot be snapshotted by copying it:
    /// it names *other cels*, which the artist may redraw, delete or move to another layer before
    /// pasting. Deferring the flatten would make the paste a picture of the document as it is then,
    /// and the ruling asks for the picture the artist saw when they copied.
    func copyCel(layerIndex: Int, celIndex: Int) {
        // Copying doesn't change the canvas, but it does snapshot the cel's tiers — including a
        // still-transient fill preview, which `pasteCel` would then plant in the new cel as
        // permanent content while the original fill bakes separately into the source. Bake first so
        // what's copied is what's actually committed.
        beginCanvasEdit()
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let source = layers[layerIndex].cels[celIndex]
        let tiers = copyTiers(of: source)
        copiedCel = CopiedCel(raster: tiers.raster, fillImage: tiers.fillImage,
                              bakedImage: tiers.bakedImage, vector: tiers.vector,
                              transformTracks: tiers.transformTracks,
                              pendingPoseBaselines: tiers.pendingPoseBaselines,
                              frameCount: source.frameCount)
    }

    /// Drops the clipboard's content into an empty slot as a new cel, sized to the copied cel's own
    /// length (clamped, like `addCel`, to whatever room is actually free before the next cel).
    ///
    /// **Nothing here knows about interpolation, and that is the point.** `CopiedCel` has no
    /// `interpolation` field, so a paste cannot plant a recipe however hard it tries; the in-between
    /// was already resolved to a flattened still by `copyCel`, which is the only end of this pair
    /// that can still see the drawings it derived from.
    @discardableResult
    func pasteCel(layerIndex: Int, startFrame: Int) -> Bool {
        guard let copiedCel, layers.indices.contains(layerIndex) else { return false }
        guard activeCelIndex(inLayer: layerIndex, atFrame: startFrame) == nil else { return false }
        guard let length = clampedCelLength(layerIndex: layerIndex, startFrame: startFrame, maxLength: copiedCel.frameCount) else { return false }
        withStructureUndo(label: .pasteFrame) {
            let newCel = Cel(id: UUID(), startFrame: startFrame, frameCount: length,
                             raster: copiedCel.raster.makeCopy(), fillImage: copiedCel.fillImage,
                             bakedImage: copiedCel.bakedImage, vector: copiedCel.vector?.makeCopy(),
                             // Paste is the fourth verb in §3.1's *"move, split, duplicate and
                             // paste"*, and it dropped the channel by the same door duplicate did.
                             transformTracks: copiedCel.transformTracks,
                             pendingPoseBaselines: copiedCel.pendingPoseBaselines)
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

    /// **The run of empty frames a gap on a layer's track covers, half-open**, or nil when `frame`
    /// is inside a cel after all — `celFrameRange`'s complement, and it exists for the same caller.
    ///
    /// **Why a gap needs a frame range at all.** §2.4 and §2.26 put keys and marks on the *layer*, in
    /// absolute document frames, so they exist perfectly well at frames the layer has no cel at —
    /// `TimelineLayoutKey.trackMarkers` says so and the marker band spans the whole track because of
    /// it. The cel menu's "Clear Keyframes" is scoped to the block that raised it; the gap menu's has
    /// to be scoped to something, and the only unit the artist can see there is the gap itself. So
    /// the two menus scope to the same thing said twice: *the stretch of track you tapped*.
    ///
    /// **The bounds are the neighbouring cels, and the last gap ends at the scene.** That matches
    /// what `TimelineRowView` draws — its trailing gap runs to the displayed frame count — closely
    /// enough for the artist to recognise, and `handleTapOnGap` has already sent the playhead to the
    /// tapped frame by the time this is asked, which raises `sceneFrameCount` to admit it
    /// (`goToFrame`). The `frame + 1` floor is what makes that true rather than assumed.
    ///
    /// Order-independent by construction: `cels` is not guaranteed sorted, so this is a min and a max
    /// over the neighbours rather than an index walk.
    func gapFrameRange(layerIndex: Int, containing frame: Int) -> Range<Int>? {
        guard layers.indices.contains(layerIndex) else { return nil }
        let cels = layers[layerIndex].cels
        guard !cels.contains(where: { $0.startFrame <= frame && frame < $0.endFrame }) else { return nil }
        let lower = cels.filter { $0.endFrame <= frame }.map(\.endFrame).max() ?? 0
        let upper = cels.filter { $0.startFrame > frame }.map(\.startFrame).min() ?? sceneFrameCount
        return lower ..< max(upper, frame + 1)
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

    /// Whether `splitCel(layerIndex:celIndex:atFrame:)` would do anything at `atFrame` — the cel
    /// menu's Split Drawing row and its tests both ask this rather than duplicating the rule inline,
    /// per VIDEO.md §8 stage 1: "a rule a view holds is a rule the fast tier cannot see."
    ///
    /// One condition: `atFrame` must be strictly inside the cel. An edge cut produces an empty cel,
    /// which `splitCel` already refuses silently — this makes the refusal visible *before* the
    /// attempt, so the row can be disabled rather than offered and then doing nothing. A one-frame
    /// cel has no interior frame at all, so it falls out of this the same way, with no separate
    /// check.
    ///
    /// **Not gated: `transformTracks` or `interpolation`.** VIDEO.md §2.8 reads, on the owner's own
    /// words, as a scope fence rather than a safety claim — *"For now I don't think it will be used
    /// much for keyframe animated cels, so you dont need to add that functionality in"* says the
    /// verb wasn't worth building for that case, not that splitting one is wrong. It didn't need
    /// building because it was already correct: `splitCel` runs
    /// `TransformTrack.split(atCelLocalFrame:)` on every channel regardless of what gates the menu
    /// (§3.1), and `SplitDrawingLogicTests.testSplittingAKeyframedCelKeepsEveryFrameShowingThePoseItShowed`
    /// is the direct proof this rests on — a track with a key that lands on neither side of the cut,
    /// split mid-segment, and every frame's resolved pose, boundary included, comes back unchanged.
    /// An in-between was never a question either way: `splitCel` carries the recipe to both halves
    /// on purpose (VIDEO.md §7).
    func canSplitCel(layerIndex: Int, celIndex: Int, atFrame: Int) -> Bool {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return false }
        let cel = layers[layerIndex].cels[celIndex]
        return atFrame > cel.startFrame && atFrame < cel.endFrame
    }

    /// Splits a cel into two at `atFrame` (strictly inside the cel); both halves keep the original drawing.
    ///
    /// **And both halves keep the pose animation** — KEYFRAMES.md §3.1, which gives `splitCel` a rule
    /// of its own rather than letting it fall out of cel-local time: *"keys before the cut go left,
    /// keys after go right, and a key is inserted at the cut in both so the value is continuous across
    /// it."* `TransformTrack.split(atCelLocalFrame:)` is that rule and carries the argument for the
    /// inserted key; the only thing this function owns is the conversion of the *absolute* cut frame
    /// into the cel-local one the track is numbered in, which is the same conversion
    /// `poseKeyframeFrames(inLayer:)` makes in the other direction.
    ///
    /// **The held baselines go to both halves rather than to one.** A baseline is §2.27's *"the
    /// previous value is held"* — a pose waiting for the next keyframe press to commit it — and it is
    /// not attached to a frame at all, so there is no cut to place it on either side of. Copying it
    /// costs one dictionary entry and loses nothing; sending it to one half would decide, silently and
    /// wrongly half the time, which half the artist is about to press the keyframe button on.
    ///
    /// **And the interpolation recipe goes to both halves, which is where this verb parts company
    /// with duplicate and paste.** Those two make a *copy*, and the 2026-09-03 ruling flattens a copy
    /// of an in-between into a still. A split makes no copy: it cuts one span in two, and both halves
    /// are the same in-between, of the same pair, at the same `t` — carrying the recipe is what makes
    /// them behave alike, exactly the argument the baselines get one paragraph up. Until 2026-09-03
    /// this was the defect half-applied: the left half is mutated in place and kept its recipe while
    /// the right half was built by a memberwise `Cel(...)` that defaulted the field to nil, so one
    /// split gave an in-between beside a blank cel.
    ///
    /// A recipe names *other* cels, never the one it lives on, so the second half's fresh id needs
    /// no rewriting on the way across — and a reference held elsewhere in the document still resolves,
    /// because the half that keeps the original cel id is the one that was mutated in place.
    func splitCel(layerIndex: Int, celIndex: Int, atFrame: Int) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        let cel = layers[layerIndex].cels[celIndex]
        guard atFrame > cel.startFrame, atFrame < cel.endFrame else { return }
        let cut = atFrame - cel.startFrame
        var leftTracks: [String: TransformTrack] = [:]
        var rightTracks: [String: TransformTrack] = [:]
        for (id, track) in cel.transformTracks {
            let halves = track.split(atCelLocalFrame: cut)
            leftTracks[id] = halves.left
            rightTracks[id] = halves.right
        }
        withStructureUndo(label: .splitFrame) {
            layers[layerIndex].cels[celIndex].frameCount = atFrame - cel.startFrame
            layers[layerIndex].cels[celIndex].transformTracks = leftTracks
            let secondHalf = Cel(id: UUID(), startFrame: atFrame, frameCount: cel.endFrame - atFrame, raster: cel.raster.makeCopy(), fillImage: cel.fillImage, bakedImage: cel.bakedImage, vector: cel.vector?.makeCopy(), interpolation: cel.interpolation, transformTracks: rightTracks, pendingPoseBaselines: cel.pendingPoseBaselines)
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
