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
                // **One pool per cel, and it is the difference between a slow operation and a
                // jetsam.** Each cel autoreleases at least two canvas-sized images here — the
                // `renderToUIImage()` inside `resized`, and the `UIGraphicsImageRenderer` output —
                // and without a pool none of them drain until the whole double loop returns, so the
                // intermediates for *every* cel in the document are resident at once. MEASURED
                // 2026-08-27 (`PerfBaselineTests.testWhatTheCanvasPaddingResizeCosts`): 32 cels at
                // 2048×1024 peaked at 3.5 GB on a document that is 256 MiB at rest. The cost is
                // linear in cel count by construction, so the 300–1000-cel document the owner
                // intends (TODO.md) does not get slow on a 3 GB iPad, it gets killed.
                //
                // `flipCanvas` below is the same loop with the same omission and is deliberately not
                // changed here — see CANVAS_RESIZE.md §0.
                autoreleasepool {
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

// MARK: - Deferred thumbnail backfill (PERFORMANCE.md item 9(c))
//
// **What a project open used to do last, and now does after.** `ProjectStore.load` finished by
// calling `regenerateAllThumbnails()` — a second full walk of every cel, guaranteed cache-cold
// because every texture the decode had just built was a new object identity at version 0. MEASURED
// 2026-08-20 at **96.3 ms of a 303.6 ms open**, a third of the wait, on the main actor, between the
// artist's tap and the canvas appearing.
//
// None of it is needed to *show* the artwork. A thumbnail is a 120-point picture of a cel in the
// timeline; the canvas draws from the cel itself. So the open no longer waits on it: the cels arrive
// with `thumbnail == nil`, which the timeline already renders as an empty bordered block
// (`TimelineTrackView`'s cell hides its image view when there is none) and the layer panel as a white
// square — the placeholder was already there, nothing had ever left it on screen long enough to
// matter.
//
// **The failure mode this is arranged around is a *stale* thumbnail, not a missing one.** Missing is
// loud: an empty timeline that never fills in is the first thing anyone would report. Stale is quiet
// — a thumbnail of the drawing as it was before a stroke, indefinitely, on a cel that looks fine on
// the canvas. So every install re-resolves its layer and cel **by id** and compares a
// `LayerContentVersion` captured *before* the render against the live one, and skips on any
// difference. A skipped cel is not lost: `strokeEnded` schedules its own debounced regen, so the
// artist's own edit is what repaints it, which is the path that was always going to repaint it
// anyway.
extension CanvasManager {

    /// Where the deferred renders run. Concurrent, because `PixelOps.parallelMap` fans out on
    /// whatever thread it lands on; `.utility`, because nothing waits for this — by the time it runs
    /// the artist is looking at their canvas, and it should lose to the touch path rather than
    /// compete with it.
    private static let thumbnailBackfillQueue = DispatchQueue(
        label: "com.paintapp.CanvasManager.thumbnailBackfill", qos: .utility, attributes: .concurrent)

    /// Starts filling in every missing cel thumbnail and returns immediately.
    ///
    /// Cancels any pass already running: two loads in a row would otherwise have two passes writing
    /// the same cels, and the second document's is the one worth having.
    func startThumbnailBackfill() {
        thumbnailBackfillTask?.cancel()
        thumbnailBackfillTask = Task { @MainActor [weak self] in
            await self?.backfillMissingThumbnails()
        }
    }

    /// Renders the missing thumbnails **a layer at a time**, off the main actor, installing each
    /// layer's batch in one main-actor turn.
    ///
    /// **Batched by layer rather than by cel, and that is a judgement about publishing rather than
    /// about rendering.** `cels[i].thumbnail` is `@Published` and `TimelineLayoutKey` carries each
    /// thumbnail's object identity, so one assignment is one relayout of the track. Installing
    /// thirty-two of them individually would trade a 96 ms block for thirty-two relayouts spread
    /// across the next second, which is not obviously the better deal. A layer at a time gives the
    /// timeline something to show while the rest arrives, at one relayout per layer.
    ///
    /// **The loop walks layer *ids*, not indices, and that is not fastidiousness.** It suspends once
    /// per layer, and `layers` is a `@Published` array the artist can add to, delete from or reorder
    /// across any of those suspensions. An index loop would then silently skip a layer — leaving it on
    /// its placeholder until something else happened to repaint it, which is a bug nobody could trace
    /// back to here.
    @MainActor
    func backfillMissingThumbnails() async {
        guard let canvasSize else { return }
        for layerID in layers.map(\.id) {
            if Task.isCancelled { return }
            guard let layerIndex = layers.firstIndex(where: { $0.id == layerID }) else { continue }
            // The version is captured **here, before the render**, and that placement is the whole
            // guard. `Cel.raster` is a class, so a `LayerContentVersion` built from a captured `Cel`
            // at install time would read the *live* counter through the same object and compare equal
            // to itself no matter what the artist drew in between.
            let jobs = ThumbnailBatch(entries: layers[layerIndex].cels
                .filter { $0.thumbnail == nil }
                .map { ThumbnailBatch.Entry(cel: $0, version: LayerContentVersion(cel: $0)) })
            guard !jobs.entries.isEmpty else { continue }

            let rendered: ThumbnailImages = await withCheckedContinuation { continuation in
                Self.thumbnailBackfillQueue.async {
                    let images = PixelOps.parallelMap(jobs.entries.count) {
                        CanvasManager.celThumbnailImage(for: jobs.entries[$0].cel, canvasSize: canvasSize)
                    }
                    continuation.resume(returning: ThumbnailImages(images: images))
                }
            }
            // Counted where the renders were paid for, not where they land: a batch whose layer
            // vanished mid-flight still cost the rasterizes, and `thumbnailRegenerationCount` means
            // cost rather than effect (see `CanvasManager.recordThumbnailRenders`).
            recordThumbnailRenders(rendered.images.count)
            if Task.isCancelled { return }
            install(rendered.images, from: jobs, layerID: layerID)
        }
    }

    /// Puts a batch on its cels, skipping any that moved, vanished, or changed while it rendered.
    @MainActor
    private func install(_ images: [UIImage], from batch: ThumbnailBatch, layerID: UUID) {
        guard let layerIndex = layers.firstIndex(where: { $0.id == layerID }) else { return }
        for (entry, image) in zip(batch.entries, images) {
            guard let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == entry.cel.id })
            else { continue }
            let live = layers[layerIndex].cels[celIndex]
            // Already filled in by a debounced regen that beat this pass, or edited since the capture
            // — either way this image is not the newest answer and must not overwrite one that is.
            guard live.thumbnail == nil, LayerContentVersion(cel: live) == entry.version else { continue }
            installThumbnail(image, layerIndex: layerIndex, celIndex: celIndex)
        }
    }

    /// The cels one layer's batch is about, with the content version each was captured at.
    ///
    /// `@unchecked Sendable` for the reason `ProjectStore.Transfer`'s doc comment gives, with one
    /// difference worth naming: these `Cel`s are **not** unshared — their `RasterLayerTexture` and
    /// `VectorCanvas` are the live ones the artist may be drawing into. What makes that safe is not
    /// exclusivity but the locks those two types already hold for exactly this case (see
    /// `PixelOps.parallelMap`), and what makes it *correct* is the version comparison in `install`:
    /// a texture that moved under the render produces a thumbnail that is then discarded.
    private struct ThumbnailBatch: @unchecked Sendable {
        struct Entry {
            let cel: Cel
            let version: LayerContentVersion
        }
        let entries: [Entry]
    }

    /// One layer's rendered thumbnails, on their way back to the main actor.
    private struct ThumbnailImages: @unchecked Sendable {
        let images: [UIImage]
    }
}
