import SwiftUI
import UIKit

// MARK: - Document
//
// Whole-canvas operations: resizing the canvas, the drawable padding margin around the artwork, and
// mirroring the canvas. All of them rewrite every cel's buffers in place and so are deliberately not
// undoable. Extracted from CanvasManager.swift as an extension — all state still lives on the class
// itself (see that file's header), so every view binding is unchanged.

/// CANVAS_RESIZE.md §2's single resize map `M`, computed once and applied to every tier.
///
/// **One map, expressed once.** Not "a draw rect for the raster and a scale factor for the vector":
/// those are the same geometry written twice, and two expressions of one geometry are how they come
/// to disagree. `RasterLayerTexture.flippedImage`'s doc comment sets the precedent for the flip, in
/// as many words — the three raster tiers move *in exact lockstep* or content lands on the wrong
/// side of the canvas relative to the rest.
///
/// A struct rather than four locals inside the resize so the arithmetic is reachable from a headless
/// test without building a document (`CanvasResizeLogicTests`), and so the inverse — which stage 3's
/// undo runs backwards — has one home rather than being re-derived at the point of use.
///
/// Dimensions here are **buffer** extents (`CanvasManager.canvasSize`, which already includes
/// `canvasPadding` on every side), not artwork extents. At `k == 1` the two agree exactly: padding is
/// symmetric, so `(Nw + 2p − Ow − 2p)/2 == (Nw − Ow)/2`, and centring in either space gives the same
/// offset. See `CanvasManager.resizeCanvas(to:scaleContent:)` for which one the *artist* types.
struct CanvasResizeMap: Equatable {

    let oldSize: CGSize
    let newSize: CGSize

    /// The letterbox factor: `min(Nw/Ow, Nh/Oh)` under scale, exactly `1` under crop/expand.
    ///
    /// `min` and not `max` because the owner asked for *"just scaling the stuff so it fits"* — the
    /// leftover on the axis that did not bind is real paper at the document's background colour, not
    /// a painted bar. `max` (cover, and crop the overflow) is a different feature; §6 asks for it.
    let scale: CGFloat

    /// Where the old canvas's origin lands in the new one. Centred, matching `setCanvasPadding`'s
    /// long-standing placement, and because a drawing on a canvas being grown belongs in the middle
    /// of the larger one.
    let offset: CGPoint

    /// - Parameters:
    ///   - oldSize: the buffer extent the document has now.
    ///   - newSize: the buffer extent it is becoming.
    ///   - scaleContent: false crops/expands (artwork keeps its own size); true letterboxes.
    init(from oldSize: CGSize, to newSize: CGSize, scaleContent: Bool) {
        let k: CGFloat
        if scaleContent, oldSize.width > 0, oldSize.height > 0 {
            k = min(newSize.width / oldSize.width, newSize.height / oldSize.height)
        } else {
            k = 1
        }
        var dx = (newSize.width - k * oldSize.width) / 2
        var dy = (newSize.height - k * oldSize.height) / 2
        // **Whole points when `k == 1`, and deliberately not when it isn't.** A bitmap drawn at a
        // half-point offset is filtered, so a crop/expand that did not round would be a lossy
        // operation pretending not to be. Under scale the draw is a resample anyway, and rounding
        // there would put the raster tier half a point from the vector tier on the same cel — the one
        // thing that must not happen. §5 rule 4.
        if k == 1 { dx.round(); dy.round() }
        self.oldSize = oldSize
        self.newSize = newSize
        self.scale = k
        self.offset = CGPoint(x: dx, y: dy)
    }

    /// Where the old canvas's whole extent lands in the new one — the `placing:` rect every raster
    /// and vector primitive draws into.
    var contentRect: CGRect {
        CGRect(x: offset.x, y: offset.y, width: scale * oldSize.width, height: scale * oldSize.height)
    }

    /// `M` itself: a point `p` of the old canvas maps to `k·p + d`.
    ///
    /// `.scaledBy` *after* `translationX:` is the spelling that means **scale first, then
    /// translate**; the other order reads identically and is wrong.
    var transform: CGAffineTransform {
        CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: scale, y: scale)
    }

    func apply(_ point: CGPoint) -> CGPoint { point.applying(transform) }

    /// The resize that undoes this one.
    ///
    /// At `k == 1` this is **exactly** the identity when composed: `Double.rounded()` rounds half away
    /// from zero, which is symmetric about zero, so `((Ow − Nw)/2).rounded() == −((Nw − Ow)/2).rounded()`
    /// even when the difference is odd. Pinned by
    /// `CanvasResizeLogicTests.testCropExpandOutAndBackIsExactlyTheIdentity`. Under scale the geometry
    /// returns to within float noise and the *pixels* do not — CANVAS_RESIZE.md §2's permanent
    /// vector/raster asymmetry, which stage 3's undo has to announce rather than hide.
    var inverse: CanvasResizeMap {
        CanvasResizeMap(from: newSize, to: oldSize, scaleContent: scale != 1)
    }
}

extension InterpolationRecipe {

    /// This recipe with every piece of geometry it owns shifted by `d` — the crop/expand arm of
    /// CANVAS_RESIZE.md §1's interpolation rows.
    ///
    /// An in-between's *content* is derived and so there is nothing here to redraw. What there is, is
    /// the space it is derived **through**: a `Lattice`'s `restOrigin` and `vertices` are canvas
    /// points, and a lattice left behind while the keyframes it interpolates moved would re-pose the
    /// drawing relative to a grid that no longer sits over it.
    ///
    /// **`LocalEdit.stroke` moves too, and moves exactly once.** Its samples are in the lattice's
    /// *rest* space (`Lattice.carriedToRest`), which is a grid laid out in canvas coordinates — so
    /// translating the grid without translating the stroke would slide the stroke into different
    /// cells. Translating both by the same `d` is what "it moves with the lattice" means. The trap §1
    /// names is the other error: mapping it a second time in canvas space, on top of the lattice it
    /// already rode through.
    ///
    /// `cols`, `rows`, `activeCells`, `t`, `spacing`, `guideIDs` and `references` carry no canvas
    /// geometry — cell topology, normalised time and identities — and are untouched. `restCellSize`
    /// is a length and is untouched *at `k == 1`*; stage 2 scales it.
    func translated(by d: CGPoint) -> InterpolationRecipe {
        guard d != .zero else { return self }
        let t = CGAffineTransform(translationX: d.x, y: d.y)
        var moved = self
        moved.groups = groups.map { binding in
            var binding = binding
            binding.lattices = binding.lattices.map { lattice in
                Lattice(cols: lattice.cols, rows: lattice.rows,
                        restOrigin: CGPoint(x: lattice.restOrigin.x + d.x, y: lattice.restOrigin.y + d.y),
                        restCellSize: lattice.restCellSize,
                        vertices: lattice.vertices.map { CGPoint(x: $0.x + d.x, y: $0.y + d.y) },
                        activeCells: lattice.activeCells)
            }
            return binding
        }
        moved.localEdits = localEdits.map { edit in
            var edit = edit
            if case .stroke(let stroke) = VectorCanvas.mapping(.stroke(edit.stroke), throughSimilarity: t) {
                edit.stroke = stroke
            }
            return edit
        }
        return moved
    }
}

extension CanvasManager {

    // MARK: - Resize (CANVAS_RESIZE.md stage 1)

    /// The artwork rect the artist is looking at: `canvasSize` inset by `canvasPadding` on every side.
    ///
    /// Nil before a canvas exists. **This is the number the resize dialog shows and takes**, per §5
    /// rule 9 (owner-confirmed 2026-08-28): the padding is a working margin the artist set with a
    /// *separate* control, so it is preserved literally in canvas points and never scales, and the
    /// typed width/height therefore mean the artwork. The alternative — the typed number being the
    /// buffer, with padding eating into it — makes the two Actions controls fight over one number in
    /// a way neither of them shows.
    var artworkSize: CGSize? {
        guard let canvasSize else { return nil }
        return CGSize(width: max(1, canvasSize.width - 2 * canvasPadding),
                      height: max(1, canvasSize.height - 2 * canvasPadding))
    }

    /// What `resizeCanvas(to:)` will accept for an artwork dimension, given the padding already on
    /// this document.
    ///
    /// **Not simply `1...maxCanvasExtent`, and the difference is the padding.** `canvasSize` includes
    /// the margin, and `maxCanvasExtent` bounds `canvasSize` — so on a document with 1024 pt of
    /// padding the largest *artwork* that fits is 16383 − 2048. `CanvasSizePickerView` needs no such
    /// inset because it creates a document with no padding at all. Clamping rather than refusing, for
    /// the same reason the padding slider clamps: the artist gets the largest thing that fits, not an
    /// error.
    var resizableArtworkExtentRange: ClosedRange<CGFloat> {
        1...max(1, Self.maxCanvasExtent - 2 * canvasPadding)
    }

    /// Resizes the whole document to an arbitrary artwork rectangle — the Actions menu's "Resize
    /// Canvas". CANVAS_RESIZE.md stage 1.
    ///
    /// **Exactly `setCanvasPadding`'s contract with an arbitrary rectangle instead of a symmetric
    /// margin**, and literally the same loop: both entry points call `performCanvasResize` below.
    /// Every content tier of every cel of every layer moves, plus document-level guides; transient
    /// state is baked and discarded; `history` is cleared and this is not undoable; it runs
    /// synchronously on the main actor. Undo, off-main work and a busy modal are stage 3 and are
    /// deliberately absent rather than forgotten.
    ///
    /// `newArtworkSize` is the **artwork** rect (see `artworkSize`); the buffer becomes
    /// `newArtworkSize + 2 × canvasPadding`, and `canvasPadding` itself does not move.
    ///
    /// - Parameter scaleContent: stage 2. `true` is **refused** today rather than silently
    ///   crop/expanding, because a caller that asked for a letterbox and got a crop has lost artwork
    ///   and been told it succeeded. The parameter exists now so the call sites stage 2 adds are the
    ///   only thing it has to change.
    /// - Returns: whether the document changed.
    @discardableResult
    func resizeCanvas(to newArtworkSize: CGSize, scaleContent: Bool = false) -> Bool {
        guard !scaleContent else { return false }
        guard canvasSize != nil else { return false }
        let range = resizableArtworkExtentRange
        let clampedArtwork = CGSize(
            width: min(max(newArtworkSize.width.rounded(), range.lowerBound), range.upperBound),
            height: min(max(newArtworkSize.height.rounded(), range.lowerBound), range.upperBound))
        let newSize = CGSize(width: clampedArtwork.width + 2 * canvasPadding,
                             height: clampedArtwork.height + 2 * canvasPadding)
        return performCanvasResize(toBuffer: newSize, padding: canvasPadding, scaleContent: false)
    }

    /// Sets the light-grey drawable margin around the artwork, resizing every layer/cel buffer so the
    /// existing artwork stays centred. Growing the margin shifts content outward; shrinking crops
    /// whatever falls outside the new bounds. Not undoable — buffer dimensions change, so the active
    /// layer's stroke-undo stack is cleared (inactive layers' stacks clear on next activation, see
    /// `updateActiveLayerAndTool`).
    ///
    /// **The artwork does not change size here; the buffer does.** That is why this cannot be written
    /// as a call to `resizeCanvas(to:)` — the two controls move different numbers — and why both go
    /// through `performCanvasResize` instead. Before CANVAS_RESIZE.md stage 1 this held the walk
    /// itself, and the three defects the walk had (guides left behind, a stale clipboard, and a
    /// full-document thumbnail regen) were this function's as much as the resize's; sharing the loop
    /// is what fixes them here for free.
    func setCanvasPadding(_ newPadding: CGFloat) {
        guard let oldSize = canvasSize else { return }
        // **Rounded, because `ActionsMenu`'s slider has no `step:` and this value is folded into
        // `canvasSize` two lines down** — so a padding of 8.4 made the whole *canvas* 80.8 px wide,
        // and a fractional canvas is a document the two compositor backends size differently:
        // Metal rounds, UIKit's `UIGraphicsImageRenderer` ceils (MEASURED 2026-08-27, 80.2 → 80 vs
        // 81, `CompositorParityLogicTests.testBothBackendsAllocateTheSameBufferForAFractionalCanvas`).
        // The artist loses nothing: the slider's own readout is already `Int(…rounded()) px` and
        // `CanvasManager+Fill` already rounds this before using it as a rect. This does not replace
        // `RenderRequest.wholePixels` — `ProjectStore` restores `canvasSize` and `canvasPadding` as
        // two independently decoded Doubles, so a project saved before today still loads fractional —
        // it makes the class unreachable through the UI, which is where it came from.
        let clamped = min(max(newPadding, canvasPaddingRange.lowerBound),
                          canvasPaddingRange.upperBound).rounded()
        let delta = clamped - canvasPadding
        guard delta != 0 else { return }

        let newSize = CGSize(width: oldSize.width + 2 * delta, height: oldSize.height + 2 * delta)
        performCanvasResize(toBuffer: newSize, padding: clamped, scaleContent: false)
    }

    /// The one walk. Every canvas resize in the app goes through here.
    ///
    /// - Parameters:
    ///   - newSize: the new **buffer** extent (`canvasSize`, padding included).
    ///   - newPadding: what `canvasPadding` becomes — unchanged by `resizeCanvas`, moved by
    ///     `setCanvasPadding`.
    ///   - scaleContent: see `CanvasResizeMap`. Stage 1 only ever passes `false`.
    @discardableResult
    private func performCanvasResize(toBuffer newSize: CGSize, padding newPadding: CGFloat,
                                     scaleContent: Bool) -> Bool {
        guard let oldSize = canvasSize else { return false }
        guard newSize != oldSize else {
            canvasPadding = newPadding
            return false
        }

        // Every transient buffer here is canvas-sized, so all of them have to be baked before the
        // size changes underneath them (a shape/fill preview rendered at the old size would land
        // mis-scaled once it eventually committed).
        commitAllInteractiveState()
        selection = nil

        let map = CanvasResizeMap(from: oldSize, to: newSize, scaleContent: scaleContent)
        let placement = map.contentRect

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
                        layers[layerIndex].cels[celIndex].raster.resized(to: newSize, placing: placement)
                    if let fill = layers[layerIndex].cels[celIndex].fillImage {
                        layers[layerIndex].cels[celIndex].fillImage = PixelOps.resizedCanvasImage(fill, to: newSize, placing: placement)
                    }
                    if let baked = layers[layerIndex].cels[celIndex].bakedImage {
                        layers[layerIndex].cels[celIndex].bakedImage = PixelOps.resizedCanvasImage(baked, to: newSize, placing: placement)
                    }
                    if let vector = layers[layerIndex].cels[celIndex].vector {
                        layers[layerIndex].cels[celIndex].vector = vector.resized(to: newSize, placing: placement)
                    }
                    // An in-between's content is *derived*, so there is nothing here to redraw — but
                    // the lattice it is derived through is geometry in canvas coordinates and would
                    // otherwise stay behind while the keyframes it interpolates moved. §1.
                    if let recipe = layers[layerIndex].cels[celIndex].interpolation {
                        layers[layerIndex].cels[celIndex].interpolation = recipe.translated(by: map.offset)
                    }
                    // Nil rather than re-rendered, and picked up by the deferred backfill below.
                    layers[layerIndex].cels[celIndex].thumbnail = nil
                }
            }
        }

        // **Document-level geometry, missed by this walk until CANVAS_RESIZE.md stage 1.** A guide's
        // `TimedSample.x/y` are absolute canvas points, so every use of the padding slider left every
        // interpolation guide `delta` points off the artwork it was drawn over. `pressure` and `time`
        // are unit-free and untouched.
        for guideIndex in guideStrokes.indices {
            for sampleIndex in guideStrokes[guideIndex].samples.indices {
                let moved = map.apply(guideStrokes[guideIndex].samples[sampleIndex].point)
                guideStrokes[guideIndex].samples[sampleIndex].x = moved.x
                guideStrokes[guideIndex].samples[sampleIndex].y = moved.y
            }
        }

        // **The timeline clipboard is a canvas-sized payload and nothing else clears it.** `pasteCel`
        // does no size check, so a copy-resize-paste installed a cel whose `RasterLayerTexture.size`
        // was the *old* canvas's. Cleared rather than resized: a clipboard is a transient, and §5
        // rule 8 puts it with the interactive state that is baked and discarded above.
        copiedCel = nil

        canvasSize = newSize
        canvasPadding = newPadding

        history.removeAll()
        refreshUndoRedoState()
        // **`startThumbnailBackfill()`, never `regenerateAllThumbnails()`** — §2. The deferred
        // `.utility` pass PERFORMANCE.md item 9(c) already shipped, which batches by layer, walks
        // layer *ids* not indices and version-checks each install. The synchronous regen was 22% of
        // this operation's wall clock (MEASURED 2026-08-27) for a picture nothing is waiting on.
        startThumbnailBackfill()
        return true
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
                layers[layerIndex].cels[celIndex].thumbnail = nil
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
        // Deferred, for the reason the resize walk above states: this is the same whole-document
        // thumbnail pass, and nothing on screen is waiting on it. CANVAS_RESIZE.md §4 names fixing it
        // here as a free consequence of fixing it there.
        startThumbnailBackfill()
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

// MARK: - Baking full-precision strokes back onto the grid (TODO item (14))
//
// The owner: *"then there is an item in actions to bake any strokes stored as doubles on the canvas
// as 16bit integers."* **On the canvas** is their word and it is the scope: every layer, every cel,
// not the one the artist happens to be standing on — the precise strokes a Move made are spread
// wherever they moved things, and an artist who wants their file back to size wants all of them.
//
// **Unlike `setCanvasPadding` and `flipCanvas` above, this one is undoable**, and it has to be: those
// two rewrite every cel's *buffers*, which is why they clear the history instead. This rewrites
// geometry, which is what `registerVectorElementsUndo` already swaps whole for a fill, a text commit
// and every Move nudge. So it follows that path rather than `withStructureUndo` — which would not
// work here anyway: a `StructureSnapshot` copies the `Layer` structs, and `Cel.vector` is a *class
// reference*, so the snapshot and the document share the very array this walk mutates.

extension CanvasManager {

    /// How many strokes in the document are stored at full precision — what the Actions row counts,
    /// and what greys it out at zero.
    ///
    /// Computed rather than cached: a Move writes the flag inside an undo step, so a cached count
    /// would need invalidating from `applyToVectorFloat`, from both directions of every undo of one,
    /// and from a project load. The walk is over value-type arrays with no rasterization anywhere in
    /// it, and it runs when the Actions panel lays out.
    var preciseStrokeCount: Int {
        layers.reduce(0) { total, layer in
            total + layer.cels.reduce(0) { $0 + ($1.vector?.strokes.filter(\.precise).count ?? 0) }
        }
    }

    /// Snaps every precise stroke in the document onto the quarter-pixel grid and clears the flags —
    /// **one undo step**, whatever it touched.
    ///
    /// The snap is `PackedSampleRun` itself, about the same origin `ProjectStore.writeCel` encodes
    /// about (the centre of the canvas), so what the artist gets is exactly the geometry the next save
    /// would have written had the stroke never been marked. Doing it through the codec rather than by
    /// rounding here is what keeps the two from drifting: there is one definition of "on the grid",
    /// and pressure is 8 bits on that grid too.
    ///
    /// `commitAllInteractiveState()` first, for the reason `flipCanvas` states: a float still under
    /// the artist's finger holds geometry this walk would otherwise bake at the wrong pose — and, on
    /// this path specifically, a float whose strokes this very session marked precise.
    @discardableResult
    func bakePreciseStrokes() -> Int {
        commitAllInteractiveState()

        struct Edit {
            let canvas: VectorCanvas
            let layerID: UUID
            let celID: UUID
            let before: [VectorElement]
            let after: [VectorElement]
        }

        var edits: [Edit] = []
        var baked = 0
        for layer in layers {
            for cel in layer.cels {
                guard let vector = cel.vector else { continue }
                let before = vector.elements
                var touched = 0
                let after = before.map { element -> VectorElement in
                    guard case .stroke(var stroke) = element, stroke.precise else { return element }
                    touched += 1
                    // `vector.size` rather than `canvasSize` only where the document has none: the
                    // encoder measures from the *document* canvas's centre, and a per-canvas centre
                    // would put the bake on a different grid from the save.
                    let extent = canvasSize ?? vector.size
                    let centre = CGPoint(x: extent.width / 2, y: extent.height / 2)
                    stroke.samples = PackedSampleRun(stroke.samples, about: centre).samples
                    if var lattice = stroke.lattice {
                        lattice.samples = PackedSampleRun(lattice.samples, about: centre).samples
                        lattice.precise = false
                        stroke.lattice = lattice
                    }
                    stroke.precise = false
                    return .stroke(stroke)
                }
                guard touched > 0 else { continue }
                baked += touched
                edits.append(Edit(canvas: vector, layerID: layer.id, celID: cel.id,
                                  before: before, after: after))
            }
        }
        guard !edits.isEmpty else { return 0 }

        for edit in edits {
            edit.canvas.elements = edit.after
            edit.canvas.bumpVersion()
            celContentChangedOutsideStroke(layerID: edit.layerID, celID: edit.celID)
        }

        // One `recordUndo` over every cel it touched — the whole point of collecting `edits` first
        // rather than registering per cel, which would cost the artist one press per cel to take back
        // a single menu tap.
        let cost = edits.reduce(0) { $0 + ($1.before.count + $1.after.count) * 512 }
        recordUndo(label: .bakePrecision, cost: cost, undo: { [weak self] in
            for edit in edits {
                edit.canvas.elements = edit.before
                edit.canvas.bumpVersion()
                self?.celContentChangedOutsideStroke(layerID: edit.layerID, celID: edit.celID)
            }
        }, redo: { [weak self] in
            for edit in edits {
                edit.canvas.elements = edit.after
                edit.canvas.bumpVersion()
                self?.celContentChangedOutsideStroke(layerID: edit.layerID, celID: edit.celID)
            }
        })
        return baked
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
