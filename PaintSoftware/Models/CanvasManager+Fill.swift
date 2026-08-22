import Combine   // objectWillChange.send()
import SwiftUI
import UIKit

// MARK: - Fill (interactive: press to apply, drag to adjust gap-closing / edge-overlap)
//
// The interactive bucket fill: compositing the fill-reference layers, driving the GPU
// `MetalFillSession` on its own queue, the coalesced preview render loop, and committing or
// cancelling the result. Extracted from CanvasManager.swift as an extension — all state still lives
// on the class itself (see that file's header), so the gesture's stored properties and the
// `@Published` fill parameters the sliders bind to stay declared over there.
//
// This subsystem was the candidate for promotion to a real `InteractiveFillService` owned by
// CanvasManager, and it was measured for that rather than assumed. The machinery *is* private —
// nothing outside CanvasManager's own files names `fillQueue`, `fillLock`, `fillSession`, `FillKey`
// or any of the gesture fields. But the operations are not separable from the document: this file
// touches `layers` 29 times (10 of them writes into the `@Published` array, including the vector
// materialisation in `commitInteractiveFill`), plus `selection`, `currentFrame`,
// `currentLayerIndex`, `canvasSize` and `allowsPaintingOutsideSelection`, and it calls back into
// `beginCanvasEdit`, `recordUndo`, `registerUndoableCelChange`, `bakedRasterTexture`,
// `celContentChangedOutsideStroke`, `refreshUndoRedoState`, `scheduleThumbnailRegen`,
// `activeCelIndex`, `refreshDisplay` and `objectWillChange`.
//
// A service object would therefore hold a back-reference to CanvasManager and route all of that
// through it — mutating the `@Published` array from inside a child object, which is exactly the
// republishing failure mode sessions 47, 49 and 50 were spent fixing. The boundary is not clean, so
// it stays an extension.

extension CanvasManager {

    /// The quantized fill parameters, coalesced across a burst of touch-moves.
    ///
    /// Not `private`: `fillPending`/`fillRendered` in CanvasManager.swift are typed with it, and
    /// Swift scopes `private` to the file rather than the type.
    ///
    /// `inset` is `canvasPadding` — carried here rather than read in `drainFillWork` because that
    /// runs on `fillQueue` and `canvasPadding` is `@Published` main-thread state. The key is already
    /// the main-thread-captured carrier for everything the render used, so putting it here keeps
    /// that invariant. It cannot change mid-gesture (`setCanvasPadding` calls
    /// `commitAllInteractiveState` first), so it never needs to trigger a re-render during a drag —
    /// but being part of the key means it would if that guarantee were ever relaxed.
    struct FillKey: Equatable {
        var gap: Int; var threshold: Int; var edge: Int; var edgeIsWall: Bool; var inset: Int
    }

    /// Everything a `fillQueue` render needs from the gesture that asked for it, snapshotted on the
    /// main thread and handed to the worker as a value.
    ///
    /// **This exists because "set before any `fillQueue` work runs, then only read after" was not
    /// true of a second gesture**, which is the whole of the owner's *"using the fill tool more than
    /// once breaks it sometimes"*. `drainFillWork` used to read `fillGestureSeed`,
    /// `fillGestureColor`, `fillGestureLayerID` and `fillGestureCelID` — all main-thread state —
    /// off the fill queue, so a tap that landed while the previous tap's flood was still on the GPU
    /// paired the *new* seed with the *old* session, the old reference composite and the old sampled
    /// colour. Passing a snapshot instead makes that combination unrepresentable rather than merely
    /// warned against.
    ///
    /// `generation` is the gesture's identity: see `CanvasManager.fillGeneration`.
    struct FillGestureContext {
        var generation: UInt64
        var seedX: Int, seedY: Int
        var color: SIMD4<Float>       // premultiplied
        var layerID: UUID, celID: UUID
    }

    /// A finished render, as `fillQueue` produced it — stored under `fillLock` the instant it exists,
    /// *before* the `DispatchQueue.main.async` that installs it as the preview.
    ///
    /// **The commit path reads this, and that is the point.** `cel.fillImage` and
    /// `fillLastRegionRGBA` are both written by that main hop, and `beginCanvasEdit` calls
    /// `commitInteractiveFill` from inside `beginInteractiveFill` — so "the artist tapped twice
    /// quickly" arrives at the commit with the first fill *rendered and about to be shown* but not
    /// yet on the main thread. Against `guard cel.fillImage != nil` alone that fill was silently
    /// dropped: no pixels, no undo entry, no message.
    ///
    /// Not `private`, for `FillKey`'s reason: `fillRenderedRegion` in CanvasManager.swift is typed
    /// with it. Carries no extra memory — `bytes` is the same COW buffer `fillLastRegionRGBA` gets.
    struct FillRenderResult {
        var generation: UInt64
        var bytes: [UInt8]
        var width: Int, height: Int
    }

    /// The live gesture's render inputs, for the two schedulers that don't start a gesture of their
    /// own (`scheduleFillRender`, `endInteractiveFill`). Main thread only.
    private func fillGestureContext(generation: UInt64) -> FillGestureContext? {
        guard let layerID = fillGestureLayerID, let celID = fillGestureCelID else { return nil }
        return FillGestureContext(generation: generation, seedX: fillGestureSeed.x, seedY: fillGestureSeed.y,
                                  color: fillGestureColor, layerID: layerID, celID: celID)
    }

    /// Claims the next gesture generation and resets the render bookkeeping for it. Main thread only;
    /// the write is under `fillLock` so the workers' reads pair with it.
    ///
    /// **Resetting `fillRendered` to the sentinel here is what retires a superseded worker's claim.**
    /// A worker that got as far as `fillRendered = key` before this ran would otherwise have booked
    /// the *new* gesture's key as already rendered, and the new gesture's own worker would then find
    /// `key == fillRendered` and return having drawn nothing at all. The two are ordered by the lock,
    /// so the claim is always either wiped by this or refused by the generation check in
    /// `drainFillWork`.
    private func beginFillGeneration() -> UInt64 {
        fillLock.lock()
        fillGeneration &+= 1
        let generation = fillGeneration
        fillPending = currentFillKey()
        fillRendered = FillKey(gap: .min, threshold: .min, edge: .min, edgeIsWall: false, inset: .min)
        fillRenderedRegion = nil
        // Claimed here so early drag updates don't spawn a second worker. Every caller enqueues a
        // worker of this generation immediately after, which is what lets a *superseded* worker
        // return without clearing the flag: it is the live gesture's to clear, not theirs.
        fillWorkerScheduled = true
        fillLock.unlock()
        return generation
    }

    /// Blocks until `fillQueue` has produced the live gesture's pixels, when it has produced none at
    /// all yet. Called by `commitInteractiveFill` **before** `endFillGeneration`, because the moment
    /// the generation is retired the worker discards its own result.
    ///
    /// **The commit is allowed to be late for the screen. It is not allowed to be late for the
    /// document**, and that distinction is what the generation fix got half of. `fillRenderedRegion`
    /// covers "rendered, hop to main not run yet"; it cannot cover *"not rendered yet"*, and that is
    /// the wider of the two windows by orders of magnitude — it is the whole GPU pass, not one
    /// runloop turn. A second gesture arriving inside it found no pixels anywhere and
    /// `commitInteractiveFill` dropped the first fill in silence: no undo entry, nothing on the cel.
    ///
    /// **Waiting, rather than baking later, is forced by `beginCanvasEdit`'s contract.** Its entire
    /// job is that the edit which follows reads a canvas the transient is already part of — the next
    /// `begin*Fill` composites its wall reference two statements after this returns, and a deferred
    /// bake would have it flood against content that is about to change, which is the reordering bug
    /// that chokepoint exists to prevent. So the bake is synchronous or it is wrong.
    ///
    /// It costs nothing in the ordinary case: the queue is idle by then, and `sync` on an idle serial
    /// queue is a hop. In the case it is for, it costs the remainder of a render the artist was
    /// already waiting to see, once, and it is bounded by one — `fillPending` only changes on the
    /// main thread, which is the thread parked here.
    ///
    /// **Which is why the test for this cannot hold `fillQueue` with a semaphore signalled from the
    /// main thread**: this would park on it and never return. `FillGestureRestartLogicTests` signals
    /// its gate off a background queue for exactly that reason.
    private func awaitFillRenderIfNothingProduced() {
        guard fillLastRegionRGBA == nil else { return }   // a published preview is already pixels
        fillLock.lock()
        let produced = fillRenderedRegion != nil
        fillLock.unlock()
        guard !produced else { return }
        fillQueue.sync {}
    }

    /// Ends the live gesture's claim on `fillQueue`: nothing in flight may publish onto the document
    /// after this. Called by both `commitInteractiveFill` and `cancelInteractiveFill`, and it returns
    /// the render the queue had already produced for the gesture being retired — the bytes the commit
    /// bakes when the main hop has not run yet.
    private func endFillGeneration() -> FillRenderResult? {
        let live = fillGeneration
        fillLock.lock()
        let queued = fillRenderedRegion
        fillGeneration &+= 1
        fillRenderedRegion = nil
        fillLock.unlock()
        return queued?.generation == live ? queued : nil
    }

    /// Begins an interactive fill at `point` (canvas-pixel coords, top-left origin): composites every
    /// fill-reference layer into a reference image once, uploads it to a GPU `MetalFillSession`, samples
    /// the tapped colour, and paints an initial fill. A plain tap is just this immediately followed by
    /// `endInteractiveFill`; a press-and-drag streams `updateInteractiveFill` calls in between. The fill
    /// preview lives in `fillImage` until `commitInteractiveFill` bakes it into the layer proper.
    func beginInteractiveFill(at point: CGPoint) {
        guard !fillFingerDown else { return }
        // A fill is a canvas edit like any other: an earlier adjustable fill (or a pending shape)
        // bakes first, so this fill reads it as a real boundary/recolour target instead of flooding
        // against content that is about to change.
        beginCanvasEdit()
        guard let canvasSize else { return }
        guard layers.indices.contains(currentLayerIndex) else { return }
        let layerIndex = currentLayerIndex
        // Filling a frame with no block spawns one, exactly as a brush stroke there does — the two
        // are the same instruction ("put content on this frame") and it would be arbitrary for one
        // to work and the other to sit inert. See `ensureCelAtCurrentFrame`.
        guard let celIndex = ensureCelAtCurrentFrame(layerIndex: layerIndex) else { return }

        let references = fillReferenceSources()
        let width = Int(canvasSize.width.rounded())
        let height = Int(canvasSize.height.rounded())
        let seedX = min(max(Int(point.x.rounded(.down)), 0), width - 1)
        let seedY = min(max(Int(point.y.rounded(.down)), 0), height - 1)

        fillGestureActive = true
        fillFingerDown = true
        fillGestureIsLasso = false
        fillLastRegionRGBA = nil
        fillGestureSeed = (seedX, seedY)
        fillGestureColor = Self.premultipliedComponents(brushColor.resolvedUIColor(opacity: brushOpacity))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        brushColor.resolvedUIColor(opacity: brushOpacity).getRed(&r, green: &g, blue: &b, alpha: &a)
        fillGestureFillColor = CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
        let layerID = layers[layerIndex].id
        let celID = layers[layerIndex].cels[celIndex].id
        fillGestureLayerID = layerID
        fillGestureCelID = celID
        fillGestureBaseBaked = layers[layerIndex].cels[celIndex].bakedImage
        refreshUndoRedoState() // the fill is undoable from the moment it starts, even on a blank canvas

        let context = FillGestureContext(generation: beginFillGeneration(), seedX: seedX, seedY: seedY,
                                         color: fillGestureColor, layerID: layerID, celID: celID)

        fillQueue.async { [weak self] in
            guard let self, self.isCurrentFillGeneration(context.generation) else { return }
            if let refBytes = Self.compositeReferenceRGBA(references: references, width: width, height: height) {
                let session = MetalFillEngine.shared?.makeSession(referenceRGBA: refBytes, width: width, height: height)
                self.fillSession = session
                self.fillSeedColor = session?.seedColor(atX: seedX, y: seedY) ?? .zero
            }
            // A tap has no fence to redraw. Cleared beside the session it belongs to, so the two can
            // never describe different gestures — see `fillGestureLoopPath`.
            self.fillGestureLoopPath = nil
            self.drainFillWork(context)
        }
    }

    /// Whether `generation` is still the gesture `fillQueue` is working for. Safe from either thread:
    /// only the main thread writes `fillGeneration`, and always under `fillLock`.
    ///
    /// The early-out it guards at the top of each `begin*Fill` worker is not only tidiness — a tap
    /// that has already been superseded would otherwise composite the whole canvas and upload a GPU
    /// session for a gesture nobody is waiting on, which is time the *live* tap is queued behind on a
    /// serial queue.
    func isCurrentFillGeneration(_ generation: UInt64) -> Bool {
        fillLock.lock()
        defer { fillLock.unlock() }
        return generation == fillGeneration
    }

    /// **Edge Overlap is forced to 0 for a lasso gesture, and that is not a tidiness choice.**
    /// `fillExpand` defaults to 2 px and is shared with the flood, where it exists to slip the fill
    /// *under* a line the fill stopped at, hiding the antialiasing seam. The lasso fill has no such
    /// seam — it covers the line (LASSO_FILL.md §6 step 4) — so a positive value here has nothing to
    /// hide and only pushes colour 2 px past the artwork onto clean paper, which is the one thing
    /// §3's rule promises the tool will not do. §6 step 7 says the default is 0 and to say so in the
    /// settings; `FillSettingsPanel` hides the slider in lasso mode for the same reason.
    ///
    /// Internal rather than `private` so `FillBoundaryLogicTests` can assert the wiring: every other
    /// fill test builds a raw buffer and drives `MetalFillSession` directly, which would let a
    /// correct shader ship behind a `canvasPadding` that never reaches it.
    func currentFillKey() -> FillKey {
        FillKey(gap: Int(fillGapClosingDistance.rounded()),
                threshold: Int((fillThreshold * 1000).rounded()),
                edge: fillGestureIsLasso ? 0 : Int(fillExpand.rounded()),
                edgeIsWall: fillCanvasEdgeIsBoundary,
                inset: Int(canvasPadding.rounded()))
    }

    /// Toggles "the canvas edge bounds the fill" and, if a fill is currently adjustable, re-runs it so
    /// the artist sees the difference without re-tapping — the same live-update contract
    /// `setFillSetting` gives the three sliders. Not a `FillAxis`: the sideways drag adjusts a
    /// continuous setting, and there is no useful way to sweep a boolean.
    func setFillCanvasEdgeIsBoundary(_ enabled: Bool) {
        guard fillCanvasEdgeIsBoundary != enabled else { return }
        fillCanvasEdgeIsBoundary = enabled
        if fillGestureActive { scheduleFillRender() }
    }

    /// The layers whose content bounds the fill, bottom-to-top: every layer marked `isFillReference`, at
    /// its active cel for the current frame. Empty when nothing is a reference (the fill then floods the
    /// whole canvas).
    private func fillReferenceSources() -> [(layer: Layer, cel: Cel)] {
        layers.indices.compactMap { i in
            let layer = layers[i]
            guard layer.isFillReference,
                  let celIdx = activeCelIndex(inLayer: i, atFrame: currentFrame) else { return nil }
            return (layer, layer.cels[celIdx])
        }
    }

    /// Updates the in-progress fill's gap-closing (vertical drag), wall threshold (horizontal drag) and
    /// edge-overlap settings — clamped to the slider ranges — and re-fills from the cached GPU session.
    /// Also writes them back to the published settings so the fill sliders mirror the drag live. Cheap to
    /// call on every touch-move: identical quantized values schedule no work, and a burst coalesces.
    func updateInteractiveFill(gapClosing: CGFloat, threshold: CGFloat, edgeOverlap: CGFloat) {
        guard fillGestureActive else { return }
        let clampedGap = min(max(gapClosing, Self.fillGapRange.lowerBound), Self.fillGapRange.upperBound)
        let clampedThreshold = min(max(threshold, Self.fillThresholdRange.lowerBound), Self.fillThresholdRange.upperBound)
        let clampedEdge = min(max(edgeOverlap, Self.fillExpandRange.lowerBound), Self.fillExpandRange.upperBound)
        if fillGapClosingDistance != clampedGap { fillGapClosingDistance = clampedGap }
        if fillThreshold != clampedThreshold { fillThreshold = clampedThreshold }
        if fillExpand != clampedEdge { fillExpand = clampedEdge }
        scheduleFillRender()
    }

    /// Sets one fill setting from the Fill panel: updates the value, makes that setting the axis the
    /// fill tool's sideways drag will adjust next time, and — if a fill is currently adjustable — re-runs
    /// it live so the user sees the change without re-tapping. Called from the panel's slider bindings;
    /// the interactive drag writes the `@Published` values directly instead, so it never re-selects here.
    func setFillSetting(_ axis: FillAxis, _ value: CGFloat) {
        fillSelectedAxis = axis
        switch axis {
        case .gapClosing:
            let v = min(max(value, Self.fillGapRange.lowerBound), Self.fillGapRange.upperBound)
            if fillGapClosingDistance != v { fillGapClosingDistance = v }
        case .threshold:
            let v = min(max(value, Self.fillThresholdRange.lowerBound), Self.fillThresholdRange.upperBound)
            if fillThreshold != v { fillThreshold = v }
        case .edgeOverlap:
            let v = min(max(value, Self.fillExpandRange.lowerBound), Self.fillExpandRange.upperBound)
            if fillExpand != v { fillExpand = v }
        }
        if fillGestureActive { scheduleFillRender() }
    }

    /// Coalesces a re-render of the current fill for the latest `@Published` parameters onto `fillQueue`.
    private func scheduleFillRender() {
        guard let context = fillGestureContext(generation: fillGeneration) else { return }
        fillLock.lock()
        fillPending = currentFillKey()
        let alreadyScheduled = fillWorkerScheduled
        fillWorkerScheduled = true
        fillLock.unlock()
        if !alreadyScheduled {
            fillQueue.async { [weak self] in self?.drainFillWork(context) }
        }
    }

    /// Whether `point` (canvas-pixel coords, top-left origin) lands on a pixel the current adjustable fill
    /// already covers. Used so a re-tap inside the just-filled region resumes drag-adjusting it, rather
    /// than starting a new fill.
    ///
    /// **Half the gesture's own opacity, not "any alpha at all", and the lasso is why.** Its output
    /// carries a coverage ramp along the artwork's antialiased fringe (LASSO_FILL.md §6 step 6), so a
    /// pixel can be 1/255 opaque and still be *outside* the shape the artist sees. Against a bare
    /// `> 0` test the whole soft edge of the drawing would count as "inside the fill", and a tap
    /// there would resume adjusting instead of starting a new one.
    func isPointInPendingFill(at point: CGPoint) -> Bool {
        guard fillGestureActive, let bytes = fillLastRegionRGBA, fillLastRegionW > 0 else { return false }
        let x = Int(point.x.rounded(.down)), y = Int(point.y.rounded(.down))
        guard x >= 0, x < fillLastRegionW, y >= 0, y < fillLastRegionH else { return false }
        return bytes[(y * fillLastRegionW + x) * 4 + 3] >= fillHalfCoverageAlpha
    }

    /// Half the alpha a fully-covered pixel of the current gesture carries — the cut between "in the
    /// fill" and "in its antialiased fringe".
    ///
    /// Relative to the gesture rather than a constant 128 because `fillGestureColor` is premultiplied
    /// by the brush opacity: a fill at 30% opacity paints its *solid* interior at alpha 77, so a fixed
    /// 128 would call the entire fill empty. At least 1, so a fully transparent brush still hit-tests
    /// against the pixels it nominally covers rather than against none of them.
    var fillHalfCoverageAlpha: UInt8 {
        UInt8(max(1, min(255, Int((fillGestureColor.w * 255).rounded()) / 2)))
    }

    /// Re-arms drag-adjusting of the existing adjustable fill (same session/seed) when a finger presses
    /// back down inside it. No new session or reference composite — it just keeps adjusting what's there.
    func resumeInteractiveFillDrag() {
        guard fillGestureActive else { return }
        fillFingerDown = true
    }

    /// Ends the finger press but leaves the fill *adjustable*: the last-requested parameters are flushed
    /// and the preview stays visible with its GPU session alive, so panel sliders re-run it live and a
    /// re-tap inside it resumes dragging. It's baked (committed) only later, by `commitInteractiveFill`.
    func endInteractiveFill() {
        guard fillGestureActive, fillFingerDown else { return }
        fillFingerDown = false
        guard let context = fillGestureContext(generation: fillGeneration) else { return }
        fillQueue.async { [weak self] in self?.drainFillWork(context) } // render anything still pending; keep session
    }

    /// Bakes the current adjustable fill into the layer as a single "Fill" undo step and tears the
    /// session down. The layer's kind decides the destination outright, with no fallback between
    /// them — each tier is invisible to the other's renderer:
    ///
    /// - **vector layer** → a `VectorFillElement` (a closed path) on the `VectorCanvas`, which is
    ///   the only thing such a layer draws.
    /// - **raster layer** → flattened straight into `Cel.raster`, the tier the eraser stamps, so the
    ///   fill can be erased afterwards (see `registerUndoableCelChange`'s doc comment).
    func commitInteractiveFill() {
        guard fillGestureActive else { return }
        fillGestureActive = false
        fillFingerDown = false
        let label: HistoryActionLabel = fillGestureIsLasso ? .lassoFill : .fill
        fillGestureIsLasso = false
        // Let the queue finish this gesture if it has not started publishing yet, *then* retire it
        // and take back whatever it rendered. The order is load-bearing both ways round: waiting
        // after the retirement would wait for a worker that has already thrown its result away.
        //
        // **The two of these together are the owner's bug, and they are two different windows.**
        // `fillLastRegionRGBA` is written by the render's hop to main, and this method is called
        // from `beginCanvasEdit` at the top of the *next* `begin*Fill` — so a second gesture arrives
        // here either with the first fill rendered but its hop not yet run (`endFillGeneration`
        // hands back the bytes off the queue's side of `fillLock`), or with it not rendered at all
        // (`awaitFillRenderIfNothingProduced` waits for them to exist). Reading only the
        // main-thread copy dropped the fill in both.
        awaitFillRenderIfNothingProduced()
        let queuedRender = endFillGeneration()
        // Capture the mask bytes before clearing — needed for the vector-path extraction below.
        var regionBytes = fillLastRegionRGBA
        var regionW = fillLastRegionW, regionH = fillLastRegionH
        if regionBytes == nil, let queuedRender {
            regionBytes = queuedRender.bytes; regionW = queuedRender.width; regionH = queuedRender.height
        }
        fillLastRegionRGBA = nil
        fillQueue.async { [weak self] in self?.fillSession = nil }
        let fillColor = fillGestureFillColor
        let coverageCut = fillHalfCoverageAlpha
        defer { fillGestureBaseBaked = nil; fillGestureLayerID = nil; fillGestureCelID = nil; refreshUndoRedoState() }
        guard let layerID = fillGestureLayerID, let celID = fillGestureCelID,
              let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
              let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) else { return }
        // The preview may be rendered but not yet installed (see `endFillGeneration` above). Build it
        // from the bytes the queue produced, clipped exactly as the hop would have clipped it, so the
        // guard below asks *"was anything filled?"* rather than *"did the main thread get there in
        // time?"*. An empty lasso result stores no bytes at all, so §7.1's "no undo entry for a loop
        // that enclosed nothing" still falls out of that same guard.
        if layers[layerIndex].cels[celIndex].fillImage == nil, let bytes = regionBytes,
           regionW > 0, regionH > 0, let rebuilt = Self.imageFromRGBA(bytes, width: regionW, height: regionH) {
            setFillImage(layerIndex: layerIndex, celIndex: celIndex,
                         image: clippedForSelection(rebuilt, layerIndex: layerIndex, celIndex: celIndex))
        }
        guard layers[layerIndex].cels[celIndex].fillImage != nil else { return }  // nothing was previewed

        if layers[layerIndex].kind == .vector {
            // --- Vector layer: the fill becomes a VectorFillElement, never raster pixels ---
            // A vector layer's on-screen content is `VectorCanvas.render()` alone (see
            // `StrokeCanvasView.refreshDisplay`), so this must NOT fall through to the raster branch
            // below when the contour can't be extracted: `PixelOps.rasterize` *does* read the raster
            // tier, so a fill left there would vanish from the canvas while still showing up in
            // thumbnails, fill references, Move lifts and merges — the vector twin of the raster
            // "ghost layer" bug. An unextractable mask means an empty fill, so dropping the preview
            // is the correct outcome; nothing is recorded.
            if layers[layerIndex].cels[celIndex].vector == nil, let canvasSize {
                layers[layerIndex].cels[celIndex].vector = .empty(size: canvasSize)
            }
            // Clear the transient raster preview either way so it isn't drawn a second time.
            setFillImage(layerIndex: layerIndex, celIndex: celIndex, image: nil)
            // `minimumAlpha` because a vector fill is a *path*: it has no coverage ramp to inherit, so
            // the lasso's antialiased fringe (LASSO_FILL.md §6 step 6) has to be rounded to one side
            // or the other. Half the gesture's own opacity puts the contour where the artwork's line
            // is half covered, which is the same place the raster tier's ramp crosses 50% — without
            // it the traced path would run right out to the full threshold band and the two tiers
            // would disagree about the shape of the same gesture.
            guard let vectorCanvas = layers[layerIndex].cels[celIndex].vector,
                  let bytes = regionBytes, regionW > 0, regionH > 0,
                  let path = PixelOps.pathFromAlphaMask(bytes: bytes, width: regionW, height: regionH,
                                                        minimumAlpha: coverageCut) else { return }
            let fillsBefore = vectorCanvas.fills
            // The mask is measured against the *rendered* canvas, so it's canvas-space — this
            // overload maps it back through the layer's transform (see its doc comment).
            vectorCanvas.addFill(canvasSpacePath: path, color: fillColor)
            registerVectorFillUndo(vectorCanvas: vectorCanvas, oldFills: fillsBefore, newFills: vectorCanvas.fills,
                                   layerID: layerID, celID: celID, label: label)
        } else {
            let cel = layers[layerIndex].cels[celIndex]
            guard let preview = cel.fillImage else { return }
            // --- Raster path: flatten into `raster` directly ---
            // `fillGestureBaseBaked` is only the pre-gesture `bakedImage` tier (see where it's
            // captured in `beginInteractiveFill`); the live raster strokes sit *above* both baked and
            // fill in render order (see `PixelOps.rasterize`), so they have to be composited back on
            // top explicitly here rather than just carried over via `newRaster: cel.raster` — leaving
            // the fill's own pixels stuck underneath a `raster` tier the eraser stamps into but the
            // fill itself never touched.
            let belowStrokes = PixelOps.compositeOver(base: fillGestureBaseBaked, overlay: preview)
            let finalImage = PixelOps.compositeOver(base: belowStrokes, overlay: cel.raster.renderToUIImage())
            registerUndoableCelChange(layerID: layerID, celID: celID,
                                      oldRaster: cel.raster, oldBaked: fillGestureBaseBaked, oldFill: nil,
                                      newRaster: bakedRasterTexture(image: finalImage, likeExisting: cel.raster),
                                      newBaked: nil, newFill: nil,
                                      label: label)
        }
    }

    // MARK: - Lasso fill

    /// Begins a lasso fill from the loop the artist just drew — the fill tool's `.lasso` type.
    ///
    /// **The rule, for an artist** (LASSO_FILL.md §3, and it has no branch in it): *the loop is a
    /// fence, and ink is a wall. Anything inside your fence that the fence can walk to — the paper
    /// around your drawing, and anywhere it can slip into through a gap — is left untouched.
    /// Everything else inside the fence is filled solid, lines and all. So the colour lands inside
    /// your shapes and nowhere else: not on the paper between the fence and the drawing, and never on
    /// the fence itself.*
    ///
    /// **It is not the bucket fill with a bigger seed**, which is what it used to be and is what the
    /// owner reported as a bug: *"when i circle something the entire canvas gets filled."* Seeding
    /// every open pixel inside the loop meant that circling a shape seeded the paper *around* it, and
    /// the flood ran from there over the whole page. The replacement is morphological hole filling
    /// marked from the loop — Krita ships it as *Enclose and Fill* — and it runs in five steps
    /// (LASSO_FILL.md §6 has the pixel-level statement):
    ///
    ///  1. Rasterise the closed loop, non-zero winding, clipped to the canvas → the stencil.
    ///  2. Take its one-pixel inner **ring**, and the colours that ring mostly sits on → the collar's
    ///     reference set (`LassoFillMask.ringMask` / `.referenceColours`).
    ///  3. Flood from the ring, through pixels close to a reference, **never leaving the stencil**.
    ///  4. Paint the stencil *minus* everything that flood reached (`lassoInvert`).
    ///  5. If that is empty, commit nothing and say so — see `drainFillWork` and §7.
    ///
    /// Step 4 is where each of the tool's promises comes from, and they are one line of code rather
    /// than three features: the fill cannot touch the loop because nothing outside the stencil is
    /// written; interior line art is painted over because the collar cannot walk through ink; and a
    /// face's eyes fill with the face because their interiors are walled off from the collar too.
    ///
    /// **What it will not do, on purpose.** A loop around blank paper, or one whose enclosure leaks
    /// through a gap wider than Gap Closing, fills *nothing* — the two are indistinguishable to the
    /// algorithm (§4 case 11), and falling back to painting the loop's own shape would dump a slab of
    /// colour over the artist's line art on the leak case. A shape that pokes out of the loop is not
    /// filled either (§4 case 12), because the loop passes through its interior and the collar seeds
    /// there. Both match Krita and Clip Studio Paint.
    ///
    /// Everything else — the reference composite, the wall threshold, gap closing, the canvas-edge
    /// boundary, the live re-run when a slider moves, the vector-versus-raster commit and the
    /// selection clip — is the machinery already there, which is why this stays a type option under
    /// the fill tool rather than a tool of its own. Edge Overlap is the exception: it is forced to 0
    /// (see `currentFillKey`).
    ///
    /// Left *adjustable* on purpose, exactly as a tap is: the caller follows with
    /// `endInteractiveFill()`, the preview stays live, and moving a slider re-runs this same loop.
    /// That matters most on the empty result, where nudging Threshold or Gap Closing can recover a
    /// near-miss without redrawing the loop.
    func beginInteractiveLassoFill(path: CGPath) {
        guard !fillFingerDown else { return }
        beginCanvasEdit()
        guard let canvasSize else { return }
        guard layers.indices.contains(currentLayerIndex) else { return }
        let layerIndex = currentLayerIndex

        let width = Int(canvasSize.width.rounded())
        let height = Int(canvasSize.height.rounded())
        guard let lassoMask = LassoFillMask.rasterize(path: path, width: width, height: height) else { return }
        // **A loop enclosing nothing is a cancelled gesture, not a failed fill** — LASSO_FILL.md §6
        // step 0 / §4 case 13: silent, no message, no undo entry, and no cel spawned by
        // `ensureCelAtCurrentFrame` below either, which is why this guard sits above it.
        //
        // Counted off the rasterisation that the fill will actually use, rather than off the path's
        // bounding box. The box test this replaced was an *or* of two extents, so a 100x1 px stylus
        // twitch — which encloses nothing at all — sailed through it, while this cannot: an area
        // measured on the winding-rule mask is the same number the algorithm goes on to work with.
        var enclosed = 0
        for byte in lassoMask where byte != 0 {
            enclosed += 1
            if enclosed >= Self.lassoFillMinimumArea { break }
        }
        guard enclosed >= Self.lassoFillMinimumArea else { return }

        guard let celIndex = ensureCelAtCurrentFrame(layerIndex: layerIndex) else { return }
        let references = fillReferenceSources()

        fillGestureActive = true
        fillFingerDown = true
        fillGestureIsLasso = true
        fillLastRegionRGBA = nil
        fillGestureSeed = (0, 0)   // unused: a lasso session seeds from its mask
        fillGestureColor = Self.premultipliedComponents(brushColor.resolvedUIColor(opacity: brushOpacity))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        brushColor.resolvedUIColor(opacity: brushOpacity).getRed(&r, green: &g, blue: &b, alpha: &a)
        fillGestureFillColor = CodableColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
        let layerID = layers[layerIndex].id
        let celID = layers[layerIndex].cels[celIndex].id
        fillGestureLayerID = layerID
        fillGestureCelID = celID
        fillGestureBaseBaked = layers[layerIndex].cels[celIndex].bakedImage
        refreshUndoRedoState()

        // A lasso session seeds from its mask, so the seed coordinate is unused — but the generation
        // is not, and this begin is exposed to a second gesture exactly as the bucket fill's is.
        let context = FillGestureContext(generation: beginFillGeneration(), seedX: 0, seedY: 0,
                                         color: fillGestureColor, layerID: layerID, celID: celID)
        // A new loop supersedes the last one's §7 picture, even mid-fade: whatever the artist is
        // about to be told is about *this* gesture. The presenter clears it on its own timer too;
        // this is the case that timer cannot cover, because it fires from a fill, not a clock.
        lassoFillDiagnostic = nil

        fillQueue.async { [weak self] in
            guard let self, self.isCurrentFillGeneration(context.generation) else { return }
            self.lassoFillReportedEmpty = false
            self.fillGestureLoopPath = path
            if let refBytes = Self.compositeReferenceRGBA(references: references, width: width, height: height) {
                let session = MetalFillEngine.shared?.makeSession(referenceRGBA: refBytes, width: width,
                                                                 height: height, lassoMask: lassoMask)
                self.fillSession = session
                // The session derives the collar's reference colours from the ring itself (§6 2a) and
                // ignores whatever is handed to `fill(seedColor:)`. Mirroring its answer here keeps
                // the two from reading differently to anyone debugging a gesture.
                self.fillSeedColor = session?.referenceColours.0 ?? .zero
            }
            self.drainFillWork(context)
        }
    }

    /// The smallest area, in canvas pixels of the rasterised loop, a lasso must enclose before it
    /// counts as an edit — LASSO_FILL.md §4 case 13's "under 4 px²".
    static let lassoFillMinimumArea = 4

    /// Registers one undo step that swaps a vector layer's `.fills` between `oldFills`/`newFills` —
    /// used by an adjustable-fill commit and by Fill/Clear-on-selection for vector layers (see
    /// `SelectionModels.swift`). Resolves the cel by ID (not a captured index) when the thumbnail
    /// regen fires, since other structural edits may have shifted indices by then.
    func registerVectorFillUndo(vectorCanvas: VectorCanvas,
                                oldFills: [VectorFillElement], newFills: [VectorFillElement],
                                layerID: UUID, celID: UUID, label: HistoryActionLabel) {
        let cost = (oldFills.count + newFills.count) * 512
        recordUndo(label: label, cost: cost, undo: { [weak self] in
            vectorCanvas.fills = oldFills
            vectorCanvas.bumpVersion()
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        }, redo: { [weak self] in
            vectorCanvas.fills = newFills
            vectorCanvas.bumpVersion()
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        })
    }

    /// Abandons the interactive fill without committing, discarding the preview. Used when an undo/redo
    /// tap takes over, or via `cancelInteractiveFillDrag` when a two-finger transform starts mid-drag.
    func cancelInteractiveFill() {
        guard fillGestureActive else { return }
        fillGestureActive = false // stops any in-flight render from applying (its main hop checks this)
        fillFingerDown = false
        fillGestureIsLasso = false
        _ = endFillGeneration()   // …and retires it on `fillQueue`, so a restart can't inherit its work
        fillLastRegionRGBA = nil
        if let layerID = fillGestureLayerID, let celID = fillGestureCelID,
           let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
           let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID }) {
            setFillImage(layerIndex: layerIndex, celIndex: celIndex, image: nil)
        }
        fillGestureLayerID = nil
        fillGestureCelID = nil
        fillQueue.async { [weak self] in self?.fillSession = nil }
        refreshUndoRedoState()
    }

    /// Discards the fill only if a finger is actively dragging it; an already-lifted adjustable fill
    /// survives (so a two-finger pan/zoom to inspect the canvas doesn't wipe it out).
    func cancelInteractiveFillDrag() {
        guard fillFingerDown else { return }
        cancelInteractiveFill()
    }

    /// Runs on `fillQueue`. Recomputes the fill for the latest requested parameters and pushes the painted
    /// preview to the active cel, looping until pending == last-rendered so a burst of drag updates
    /// collapses to a single trailing render.
    ///
    /// **`context` is the gesture this worker belongs to, and every step re-checks that it is still the
    /// live one** — before it claims a key, before it stores the result, and again on the main thread
    /// before it installs one. Without that a worker whose gesture has been replaced does three
    /// separate kinds of damage, all of which the artist reads as *"filling twice breaks it"*: it
    /// books the new gesture's key as rendered (so the new gesture's own worker draws nothing at all),
    /// it renders the new seed against the old session, and its result installs itself as the new
    /// gesture's preview because the main hop only ever asked whether *some* fill was active.
    ///
    /// A superseded worker returns **without clearing `fillWorkerScheduled`**: the flag belongs to
    /// whichever gesture is live, and `begin*Fill` both sets it and enqueues a worker of its own, so
    /// it is always some live worker's job to clear it.
    private func drainFillWork(_ context: FillGestureContext) {
        while true {
            fillLock.lock()
            guard context.generation == fillGeneration else { fillLock.unlock(); return }
            let key = fillPending
            if key == fillRendered {
                fillWorkerScheduled = false
                fillLock.unlock()
                return
            }
            fillRendered = key
            fillLock.unlock()

            guard let session = fillSession else {
                fillLock.lock(); fillWorkerScheduled = false; fillLock.unlock()
                return
            }
            let bytes = session.fill(seedX: context.seedX, seedY: context.seedY,
                                     seedColor: fillSeedColor,
                                     threshold: Float(Double(key.threshold) / 1000.0),
                                     gapRadius: Float(key.gap), edgeOverlap: Float(key.edge),
                                     canvasEdgeIsWall: key.edgeIsWall, edgeInset: Float(key.inset),
                                     fillColor: context.color)
            // **The lasso's empty result, and it must leave no trace** (LASSO_FILL.md §6 step 5, §7.1).
            // A loop that encloses nothing — because it leaked through a gap, or because there was
            // nothing inside it — has to commit nothing *and push no undo entry*: a no-op that eats
            // an undo slot is a bug artists notice immediately (§8). The mechanism is simply that no
            // preview is installed, which makes `commitInteractiveFill`'s existing
            // `guard ... fillImage != nil` return before it records anything.
            //
            // `session.isLasso` rather than `fillGestureIsLasso`: this runs on `fillQueue` and that
            // flag is main-thread state. The count is the session's own, read on the same queue that
            // just wrote it.
            let enclosedNothing = session.isLasso && session.lastFilledPixelCount < Self.lassoFillMinimumArea
            let regionW = session.width, regionH = session.height
            // **Publish to the commit path before publishing to the screen.** `commitInteractiveFill`
            // reads this the moment a second tap arrives, which is long before the hop below runs.
            // Empty means empty here too, so §7.1's no-undo-entry rule still holds by the same
            // mechanism (nothing to bake, so nothing recorded).
            let rendered = (enclosedNothing ? nil : bytes).map {
                FillRenderResult(generation: context.generation, bytes: $0, width: regionW, height: regionH)
            }
            fillLock.lock()
            let stillCurrent = context.generation == fillGeneration
            if stillCurrent { fillRenderedRegion = rendered }
            fillLock.unlock()
            // Superseded while the GPU was busy: neither the result nor the loop's next iteration
            // belongs to anybody. The gesture that replaced us has its own worker enqueued behind us.
            guard stillCurrent else { return }
            // **Moved below the guard: a retired worker touches no live-gesture state and builds no
            // picture nobody will see.** `lassoFillReportedEmpty` is a latch over the *live*
            // gesture's streak of empty results and `lassoEmptyDiagnostic` reads `fillGestureLoopPath`,
            // so both are §7's version of the thing the generation stamp exists to stop. **No
            // reachable defect today** — `fillQueue` is FIFO, so a superseded worker always runs
            // *ahead* of the worker that replaced it, and `beginInteractiveLassoFill` re-arms the
            // latch from that later worker — but that is correctness by queue ordering rather than
            // by the stamp, and the two arguments should not be different. It is also a canvas-sized
            // tint that was being built for a gesture nobody is waiting on.
            let image = enclosedNothing ? nil
                : bytes.flatMap { Self.imageFromRGBA($0, width: regionW, height: regionH) }
            // Said once per empty *streak*, not once per render. The gesture stays adjustable, so a
            // drag across the Threshold slider produces a burst of empty results through the
            // coalescing loop above; re-raising on each would flicker the banner and strobe the tint
            // under the artist's finger. Re-arms as soon as a fill lands, so losing it again is
            // reported. Latched here rather than on the main thread because the tint below is built
            // from this session's buffers, which only this queue may read — see the property's doc.
            let firstEmpty = enclosedNothing && !lassoFillReportedEmpty
            lassoFillReportedEmpty = enclosedNothing
            // **§7.2 and §7.4: the picture that goes with the sentence.** Built only on the first
            // empty result of a streak, so the canvas-sized tint costs nothing on the renders that
            // fill something and nothing on the repeats that would not be shown anyway.
            let diagnostic = firstEmpty ? lassoEmptyDiagnostic(from: session) : nil
            DispatchQueue.main.async { [weak self] in
                guard let self, context.generation == self.fillGeneration, self.fillGestureActive,
                      let layerIndex = self.layers.firstIndex(where: { $0.id == context.layerID }),
                      let celIndex = self.layers[layerIndex].cels.firstIndex(where: { $0.id == context.celID }) else { return }
                let clipped = self.clippedForSelection(image, layerIndex: layerIndex, celIndex: celIndex)
                self.setFillImage(layerIndex: layerIndex, celIndex: celIndex, image: clipped)
                self.fillLastRegionRGBA = enclosedNothing ? nil : bytes
                self.fillLastRegionW = regionW
                self.fillLastRegionH = regionH
                // The two halves of §7, raised together: the sentence naming both causes, and the
                // picture that lets the artist tell which one it was. `diagnostic` is non-nil exactly
                // when this is the first empty result of a streak, so the latch that keeps the banner
                // from flickering is the same one that keeps the tint from strobing.
                if let diagnostic {
                    self.lassoFillDiagnostic = diagnostic
                    self.raise(.nothingEnclosed)
                } else if !enclosedNothing {
                    // A fill that landed retires the last one's picture rather than leaving it under
                    // the new colour: the artist recovered the near-miss on a slider, and the tint is
                    // now describing a state that no longer exists.
                    self.lassoFillDiagnostic = nil
                }
            }
        }
    }

    /// Builds LASSO_FILL.md §7's picture for a lasso session that has just come back empty: the
    /// collar it reached, tinted, paired with the fence the artist drew.
    ///
    /// **The collar is where the paint went, and on this path that is the fence's whole interior.**
    /// An empty result *means* the collar reached everything (`lassoInvert` keeps only what it could
    /// not reach), so the tint says the thing the message names: the fence walked everywhere, and
    /// there was nothing in there to hold out. Paired with §7.4's redrawn fence it separates the two
    /// causes the sentence lists — a loop that enclosed blank paper looks different from one that
    /// closed early somewhere the artist did not intend. It is *not* a picture of a leak; see
    /// `MetalFillSession.lastReachedMask` for why a leak never reaches this path at all.
    ///
    /// Runs on `fillQueue`. Both of its inputs belong to that queue — the session's buffers, and
    /// `fillGestureLoopPath` — and neither is safe to read anywhere else. Returns nil without a loop
    /// rather than showing a tint with no fence beside it: half the picture invites the wrong reading
    /// (that the tinted area is what *would* have been filled), and §7.4 is there precisely because
    /// the fence is the thing most likely to be somewhere other than the artist believes.
    private func lassoEmptyDiagnostic(from session: MetalFillSession) -> LassoFillDiagnostic? {
        guard let loop = fillGestureLoopPath, let reached = session.lastReachedMask() else { return nil }
        let tint = LassoFillMask.collarTintRGBA(reached: reached, width: session.width, height: session.height)
        let collar = tint.isEmpty ? nil : Self.imageFromRGBA(tint, width: session.width, height: session.height)
        return LassoFillDiagnostic(collar: collar, loop: loop)
    }

    /// Clips a fill preview to the active selection's path when the fill lands on the exact layer/cel
    /// the selection belongs to and outside interaction is denied — the flood-fill tool analogue of
    /// `StrokeCanvasView.selectionClipPath`, so a bucket fill can't paint outside the marching ants
    /// any more than a brush stroke can. Runs on the main thread — from the `fillQueue` render's
    /// `DispatchQueue.main.async` hop, and from `commitInteractiveFill` on the path where that hop
    /// has not run yet — same as every other read of `selection`/`allowsPaintingOutsideSelection`
    /// here. Both callers must clip, or a fill baked by a second tap would ignore the selection that
    /// the same fill previewed inside.
    private func clippedForSelection(_ image: UIImage?, layerIndex: Int, celIndex: Int) -> UIImage? {
        guard let image, let selection, !allowsPaintingOutsideSelection,
              layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex),
              layers[layerIndex].id == selection.layerID, layers[layerIndex].cels[celIndex].id == selection.celID else { return image }
        return PixelOps.maskedComposite(base: nil, overlay: image, insidePath: selection.path)
    }

    // MARK: - Fill helpers

    /// Premultiplied RGBA components (0..1) of a UIColor, resolved against a fixed light trait so
    /// dynamic colours don't silently return black (the getRed-on-dynamic-colour pitfall).
    private static func premultipliedComponents(_ color: UIColor) -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4<Float>(Float(r * a), Float(g * a), Float(b * a), Float(a))
    }

    /// Composites the fill-reference layers (bottom-to-top) into a top-left-origin, premultiplied-last
    /// RGBA byte buffer the GPU reads its walls from. Excludes each layer's own transient fill preview
    /// (`fillImage`) but includes committed fills (now baked into `bakedImage`), so recolouring works.
    private static func compositeReferenceRGBA(references: [(layer: Layer, cel: Cel)], width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: PixelOps.transparentFormat())
        let composited = renderer.image { _ in
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            for source in references {
                source.cel.bakedImage?.draw(in: rect)
                source.cel.raster.renderToUIImage().draw(in: rect)
                source.cel.vector?.render().draw(in: rect)
            }
        }
        guard let cg = composited.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let bytesPerRow = width * 4
        let ok: Bool = bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: PixelOps.deviceRGBColorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .none
            // No flip: drawing a top-down UIImage's cgImage into a default bitmap context already lands
            // its top row at buffer row 0. (The old engine's translate/scale(-1) here was the long-latent
            // vertical-mirror bug — invisible on the centred shapes every earlier test used.)
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? bytes : nil
    }

    /// Wraps a top-left-origin premultiplied-last RGBA byte buffer into a UIImage for the fill preview.
    /// Built via a `CGDataProvider`, which is canonically top-down (data row 0 is the top) — matching the
    /// top-down reference the GPU fills against, so the painted region displays where it was tapped.
    private static func imageFromRGBA(_ bytes: [UInt8], width: Int, height: Int) -> UIImage? {
        guard width > 0, height > 0, bytes.count >= width * height * 4 else { return nil }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: PixelOps.deviceRGBColorSpace,
                               bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                               shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }


    func setFillImage(layerIndex: Int, celIndex: Int, image: UIImage?) {
        guard layers.indices.contains(layerIndex), layers[layerIndex].cels.indices.contains(celIndex) else { return }
        layers[layerIndex].cels[celIndex].fillImage = image
        scheduleThumbnailRegen(layerIndex: layerIndex, celIndex: celIndex)
    }}
