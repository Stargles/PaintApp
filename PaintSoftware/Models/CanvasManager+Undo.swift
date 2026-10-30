import SwiftUI

// MARK: - Structural undo (layer/folder/cel-timeline edits)
//
// Snapshot/restore of the document structure, the `withStructureUndo` scope that turns one user
// action into exactly one undo step, and the begin/commit/cancel brackets continuous drags use
// instead. Session 41's nested-scope coalescing and session 50's `beginCanvasEdit` chokepoint are
// both load-bearing here and moved across unchanged.
//
// Extracted from CanvasManager.swift as an extension — all state still lives on the class itself
// (see that file's header). The two stored properties this file drives, `structureUndoDepth` and
// `gestureSnapshot`, therefore stay declared over there, since a Swift extension cannot declare
// stored properties.

extension CanvasManager {

    /// A whole-document-structure snapshot: cheap to take because `Layer`/`Cel`/`LayerFolder`/
    /// `ViewPreset` are all value types — copying these arrays copies no pixel/vector content
    /// (`Cel.raster`/`Cel.vector` are class references, shared rather than duplicated), only the
    /// lightweight struct fields (name, opacity, visibility, frame ranges, folder membership...).
    /// This is what makes it safe and cheap to snapshot before/after every layer/folder/cel-
    /// timeline operation, not just the pixel-editing ones.
    ///
    /// Not `private`: `gestureSnapshot` in CanvasManager.swift is typed with it, and Swift scopes
    /// `private` to the file rather than the type.
    struct StructureSnapshot {
        var layers: [Layer]
        var folders: [LayerFolder]
        var viewPresets: [ViewPreset]
        var activeViewPresetIndex: Int
        var currentLayerIndex: Int
        /// The two document-level interpolation registries. Here rather than given undo machinery of
        /// their own because a single artist action routinely spans both them and `layers` — deleting
        /// a motion group also clears the tag off every stroke carrying it — and one snapshot is what
        /// makes that one undo step. They are arrays of small value types, so they cost the same
        /// almost-nothing the rest of this snapshot does.
        var motionGroups: [MotionGroup]
        var guideStrokes: [GuideStroke]
        /// The keyframe feature's own registry, here for the identical reason: deleting an animation
        /// group has to clear the tag off every element carrying it, and one snapshot is what makes
        /// that one undo step.
        var animationGroups: [AnimationGroup]
        /// **Every video element's crop and speed** — VIDEO.md §2.2 and §2.5, and the one part of a
        /// structural edit that this snapshot cannot reach through `layers`.
        ///
        /// `layers` is copied by value and `Cel.vector` is a **class**, so the snapshot shares the
        /// live `VectorCanvas`: restoring it puts a cel's `startFrame` and `frameCount` back and
        /// leaves whatever the drag wrote *inside* that canvas exactly where the drag left it. No
        /// other structural verb has that problem, because none of them mutates a vector canvas in
        /// place — `splitCel` mints copies. A crop drag is the first that does, and an undo that
        /// gave the block back its length while keeping the new crop would be a retime nobody asked
        /// for.
        ///
        /// Keyed by element id, so it survives a cel being reordered or the array being rebuilt.
        var videoCrops: [UUID: VideoCrop]
        let sourceCosts: RasterUndoCost.Sources
    }

    private func captureStructure() -> StructureSnapshot {
        StructureSnapshot(layers: layers, folders: folders, viewPresets: viewPresets,
                          activeViewPresetIndex: activeViewPresetIndex,
                          currentLayerIndex: currentLayerIndex,
                          motionGroups: motionGroups, guideStrokes: guideStrokes,
                          animationGroups: animationGroups, videoCrops: captureVideoCrops(),
                          sourceCosts: RasterUndoCost.sources(in: layers))
    }

    /// Every video element's crop, by id — see `StructureSnapshot.videoCrops`.
    ///
    /// **Gated on `layer.kind == .vector` and then on `VectorCanvas.holdsVideo`**, which is a
    /// memoized flag rather than a walk, so a document that has never imported a video pays one
    /// enum comparison per vector layer per structural edit and nothing else.
    private func captureVideoCrops() -> [UUID: VideoCrop] {
        var crops: [UUID: VideoCrop] = [:]
        for layer in layers where layer.kind == .vector {
            for cel in layer.cels {
                guard let vector = cel.vector, vector.holdsVideo else { continue }
                for video in vector.videos { crops[video.id] = VideoCrop(of: video) }
            }
        }
        return crops
    }

    /// Puts those crops back, touching only the elements whose three fields actually differ — so an
    /// undo of a structural edit that never went near a video bumps no version and re-renders
    /// nothing.
    private func restoreVideoCrops(_ crops: [UUID: VideoCrop]) {
        guard !crops.isEmpty else { return }
        for layer in layers where layer.kind == .vector {
            for cel in layer.cels {
                guard let vector = cel.vector, vector.holdsVideo else { continue }
                var elements = vector.elements
                var changed = false
                var rewritten: Set<UUID> = []
                for index in elements.indices {
                    guard case .video(var video) = elements[index],
                          let crop = crops[video.id], VideoCrop(of: video) != crop else { continue }
                    video.sourceStart = crop.start
                    video.sourceEnd = crop.end
                    video.speed = crop.speed
                    elements[index] = .video(video)
                    rewritten.insert(video.id)
                    changed = true
                }
                guard changed else { continue }
                // The same seam the forward crop and speed writes use, and the same argument
                // (`writeVideoCrop`): a same-id rewrite that moves no rectangle, bounded by the
                // element's own quad rather than `bumpVersion()`'s whole cel — TODO (41).
                vector.restoreElements(elements, changedInk: nil, rewriting: rewritten)
            }
        }
    }

    private func restoreStructure(_ snapshot: StructureSnapshot) {
        structureUndoDepth += 1
        defer { structureUndoDepth -= 1 }
        layers = snapshot.layers
        folders = snapshot.folders
        viewPresets = snapshot.viewPresets
        activeViewPresetIndex = snapshot.activeViewPresetIndex
        currentLayerIndex = snapshot.currentLayerIndex
        // The scene may have been longer when the playhead was last moved — undoing the edit that
        // lengthened it would otherwise leave the playhead parked past the new end, reading as
        // "Frame 14/12". Adding a drawing out beyond the last frame (the timeline scrolls on
        // forever, so that is an ordinary thing to do now) is exactly such an edit.
        //
        // **After `layers`, and that ordering is now load-bearing.** The end of the scene is derived
        // from the cels (`contentEndFrame`) rather than stored beside them, so this clamp reads the
        // *restored* document. It used to read a snapshotted field, which is the field TODO (50)
        // removed — and which, because nothing ever lowered it, made this clamp looser than it
        // claimed to be.
        clampPlayheadToContent()
        motionGroups = snapshot.motionGroups
        guideStrokes = snapshot.guideStrokes
        animationGroups = snapshot.animationGroups
        // After `layers`, because it writes through the canvases the restored cels name.
        restoreVideoCrops(snapshot.videoCrops)
    }

    /// Structural history can remove the last held frame without moving the artist's playhead.
    /// Shared by snapshot restores and narrow layer transfers, after their structure is restored.
    func clampPlayheadToContent() {
        currentFrame = min(currentFrame, max(contentEndFrame - 1, 0))
    }

    /// Registers one undo step for a discrete (non-gesture) structural edit — call after the
    /// mutation has already happened, passing a `before` snapshot taken right before it.
    private func recordStructureChange(label: HistoryActionLabel, from: StructureSnapshot, to: StructureSnapshot) {
        let cost = UndoBudget.addingCost(4096, RasterUndoCost.bytes(from: from.sourceCosts, to: to.sourceCosts))
        recordUndo(label: label, cost: cost, undo: { [weak self] in
            self?.restoreStructure(from)
        }, redo: { [weak self] in
            self?.restoreStructure(to)
        })
    }

    /// Snapshots structure, runs `body`, and records the difference as one undo step named `label`.
    /// This is the call shape for discrete edits; continuous drags use
    /// `beginStructureGesture`/`commitStructureGesture` instead.
    ///
    /// Nests safely: composite operations build on the primitives (merging calls `deleteLayer`,
    /// which is itself wrapped), and a drag bracketed by `beginStructureGesture` may call several
    /// of them. Only the outermost scope captures and records, so one user action is always exactly
    /// one undo step — without this, merging would record a bare "Delete Layer" that reverses half
    /// the operation and leaves the survivor flattened.
    func withStructureUndo(label: HistoryActionLabel, _ body: () -> Void) {
        guard structureUndoDepth == 0, gestureSnapshot == nil else {
            body()
            noteStructureWrite()
            return
        }
        _ = withStructureTransaction(label: label) { body(); return true }
    }

    /// Fresh-tier edits can decline without consuming the old structure or recording history.
    @discardableResult
    func withStructureTransaction(label: HistoryActionLabel, _ body: () -> Bool) -> Bool {
        let records = structureUndoDepth == 0 && gestureSnapshot == nil
        // Every structural edit is a canvas edit, so a pending shape/fill bakes first — before the
        // snapshot below, so the transient lands as its own earlier undo step rather than being
        // swallowed into this one (or re-baking afterwards on top of it). This one call is what
        // covers add/delete/merge/duplicate/group/restack/rasterize/clear and every cel-timeline
        // operation: they all funnel through here. See `beginCanvasEdit`.
        if records, !beginCanvasEdit() { return false }
        // A fallible nested edit restores its entry, preserving any earlier enclosing gesture work.
        let before = captureStructure()
        let cropBefore = pendingKeyframeCrop
        structureUndoDepth += 1
        var accepted = false
        defer {
            structureUndoDepth -= 1
            if accepted { noteStructureWrite() }
        }
        guard body() else {
            restoreStructure(before)
            pendingKeyframeCrop = cropBefore
            return false
        }
        accepted = true
        if records {
            recordStructureChange(label: label, from: before, to: captureStructure())
            flushPendingKeyframeCrop()
        }
        return true
    }

    // MARK: - Saying what a span change discarded (TODO 62)

    /// **Hands a span-shortening verb's crop to the artist, once the step that owns it exists.**
    ///
    /// Inside a structure step or a gesture bracket the crop is parked on `pendingKeyframeCrop` and
    /// raised when the step is recorded, so the banner's *"Undo brings them back"* is true at the
    /// moment it is read. A verb called with neither open (which only a test does: the timeline
    /// brackets every handle drag, and every discrete verb wraps itself) registers no step at all, so
    /// that sentence would be false and nothing is raised; the verb's return value is the whole
    /// report there.
    ///
    /// **Replaced inside a gesture, accumulated inside a discrete step — and the depth is what tells
    /// them apart.** A handle drag calls its verb on every `.changed`, each call recomputes the whole
    /// result from `gestureSnapshot`, and the crop is part of that result, so the last call's answer
    /// is the drag's answer and a drag that went past a key and came back reports nothing. A discrete
    /// step is the other shape: a merge splits both layers at every boundary the pair has, and a bake
    /// splits a block once per frame, so one step can crop several times and the banner owes every
    /// one of them. Until 2026-09-11 both shapes replaced, and a later split that cropped nothing set
    /// this to nil over an earlier one that had — the crop went through and the banner did not.
    /// `withStructureUndo` and `withInterpolationUndo` defer to an open gesture without raising the
    /// depth, so inside a drag the depth is 0 whatever the verb wraps itself in, and inside a
    /// discrete step it is at least 1.
    func noteKeyframeCrop(_ crop: KeyframeCrop) {
        guard structureUndoDepth > 0 || gestureSnapshot != nil else { return }
        if structureUndoDepth == 0 {
            pendingKeyframeCrop = crop.isEmpty ? nil : crop
        } else if !crop.isEmpty {
            var merged = pendingKeyframeCrop ?? KeyframeCrop()
            merged.merge(crop)
            pendingKeyframeCrop = merged
        }
    }

    /// Raises the parked crop, if any, against the step just recorded. Called from the three places a
    /// structure step reaches the stack — `withStructureUndo`, `withInterpolationUndo` and
    /// `commitStructureGesture` — and nowhere else. **All three, because a bracket that parks and does
    /// not raise leaks**: the crop stays on `pendingKeyframeCrop` and the next unrelated step announces
    /// it as its own, promising an undo that would not bring the keys back. `withInterpolationUndo`
    /// was that bracket until 2026-09-11 (a video bake splits under it), found by review.
    func flushPendingKeyframeCrop() {
        guard let crop = pendingKeyframeCrop else { return }
        pendingKeyframeCrop = nil
        raise(.keyframesCropped(crop))
    }

    /// Raw snapshot-owned writes count only outside a transaction body. A successful shared
    /// bracket reports acceptance after its depth closes; rollback/restoration writes never count.
    func noteStructureWrite() {
        guard structureGestureDepth > 0, structureUndoDepth == 0 else { return }
        structureGestureHasAcceptedWrite = true
    }

    /// Opens a gesture bracket. **Nests**, for the same reason `withStructureUndo` does: only the
    /// outermost scope captures a baseline, so one user action is one undo step even when a bracket
    /// spans another — a mask-edit session (§6.6) is open for as long as a layer's options menu is,
    /// and the rows under it can start an opacity drag inside it.
    @discardableResult
    func beginStructureGesture() -> Bool {
        if structureGestureDepth > 0 { structureGestureDepth += 1; return true }
        // Same rule as `withStructureUndo`: bake transients before the baseline snapshot, so the
        // drag about to start doesn't span a shape/fill that wasn't committed when it began.
        guard beginCanvasEdit() else { return false }
        structureGestureHasAcceptedWrite = false
        structureGestureDepth = 1
        gestureSnapshot = captureStructure()
        return true
    }

    /// Closes a bracket, recording the step only when the outermost one closes. An inner `label` is
    /// discarded rather than winning: the step belongs to the action that spans the others.
    ///
    /// **`pendingGestureLabel` beats the argument**, and that is the same rule rather than an
    /// exception to it: an action that spans the bracket may have already ended and left its name
    /// behind. See that property for the one case, which is a live take that ran out of scene while
    /// the artist was still holding the slider that started it.
    func commitStructureGesture(label: HistoryActionLabel) {
        if structureGestureDepth > 0 { structureGestureDepth -= 1 }
        guard structureGestureDepth == 0, let before = gestureSnapshot else { return }
        let claimed = pendingGestureLabel
        pendingGestureLabel = nil
        gestureSnapshot = nil
        let accepted = structureGestureHasAcceptedWrite
        structureGestureHasAcceptedWrite = false
        guard accepted else { pendingKeyframeCrop = nil; return }
        recordStructureChange(label: claimed ?? label, from: before, to: captureStructure())
        flushPendingKeyframeCrop()
    }

    /// Drops a gesture's snapshot without recording anything — for a drag that ended up changing
    /// nothing, or was cancelled. Leaving the snapshot in place instead would hand it to whichever
    /// gesture committed next, which would then record an undo step spanning both. Cancelling an
    /// *inner* bracket keeps the outer one's baseline: the enclosing action is still in progress.
    func cancelStructureGesture() {
        if structureGestureDepth > 0 { structureGestureDepth -= 1 }
        guard structureGestureDepth == 0 else { return }
        pendingGestureLabel = nil
        gestureSnapshot = nil
        structureGestureHasAcceptedWrite = false
        // A cancelled drag recorded nothing, so there is no crop to report and no step to undo.
        pendingKeyframeCrop = nil
    }
}

// MARK: - Vector element undo

extension CanvasManager {

    /// One undo step that swaps a vector canvas's **whole `elements` array** between two snapshots.
    ///
    /// **The kind-filtered setters cannot express what these callers do.** Text is interleaved with
    /// strokes by construction (`upsertText` appends a new object above whatever is already there) and
    /// since 2026-08-21 so are fills (`addFill` appends — LASSO_FILL.md §2a). `splicing` preserves the
    /// z-position of every element that still exists, but an undo *adds* or *removes* one, and there
    /// is no position to preserve for an element that is not in the list yet: a bucket-shaped undo has
    /// to guess, and it guessed "at the first one's index", which would drag a fill the artist had
    /// just put on top back underneath the line art. The whole-array swap has nothing to reconstruct.
    ///
    /// Used by stroke gestures, the text commit, both fill commits (adjustable and Fill-on-selection)
    /// and Clear-on-selection. Resolves the cel by ID (not a captured index) when the thumbnail regen
    /// fires, since other structural edits may have shifted indices by then.
    ///
    /// **What a caller knows about the shape of its own edit** — the answer
    /// `registerVectorElementsUndo` needs before it can put the swap through
    /// `VectorCanvas.restoreElements(_:changedInk:rewriting:)` instead of `bumpVersion()`.
    ///
    /// There are two questions and they are separate, which is why this is one type rather than two
    /// parameters: a rectangle is meaningless beside a set of rewritten ids, since the canvas derives
    /// a rewrite's rectangle itself, and the pair `(rewritesInPlace: someIDs, ink: someRect)` should
    /// not be expressible.
    enum ElementSwap {
        /// **At least one element in the new list carries the old list's id with different content**
        /// — a recolour, an Apply Brush, a text object re-edited under the id it already had — and
        /// these are the ids that may.
        ///
        /// `restoreElements` chooses the footprints it drops by *id difference*, so a rewritten
        /// element it was not told about would keep a measured footprint that is no longer true of
        /// it, and a later region edit could skip it on that footprint and draw the wrong picture.
        /// Told, it forgets that element's footprint and bounds the swap by the union of where the
        /// element was and where it will be — `restoreElements(_:changedInk:rewriting:)` carries the
        /// argument. Until TODO (41)'s last box this case was `bumpVersion()`'s `.everything`, which
        /// was the only safe answer while nothing said *which* ids.
        ///
        /// **Over-declare rather than under-declare**: an id here that did not change costs its own
        /// footprint's worth of repair, an id left out that did change is a wrong picture. A
        /// selection's whole membership is a correct answer and is what the two selection verbs pass.
        case rewritesInPlace(Set<UUID>)
        /// **The new list is the old one with elements added and removed, none rewritten.**
        ///
        /// - Parameter ink: a rectangle containing the ink of every element the *new* list carries
        ///   that the old one does not, or nil when the caller cannot prove one. Nil is right — not
        ///   merely permitted — when what arrives is a **stroke that has been in this canvas before**:
        ///   `VectorCanvas.vacatedInk` kept what it painted on the way out and bounds it exactly,
        ///   where a caller could only estimate.
        ///
        ///   **Since TODO (41) nil is also right for a fill, a placed image, a video and a text
        ///   object**, whose extents are stored geometry rather than a dab walk:
        ///   `VectorCanvas.derivedFootprint(of:lowestResolution:)` reads each off the element itself
        ///   — a text object's by measuring the glyph outlines its recipe lays out — so a caller
        ///   passing a rectangle for one of those is supplying an answer the canvas already has. A
        ///   rectangle is still worth passing where the caller has one anyway —
        ///   `addFill(canvasSpacePath:)` returns it — because it costs nothing and covers the arrival
        ///   of an element the canvas has never seen.
        case addsAndRemoves(ink: CGRect?)
    }

    /// Coarse-grained is what every other element kind already does; this adds no new undo machinery,
    /// only a wider slice of the same one.
    ///
    /// **`swap` is what decides whether a press costs the rectangle or the cel**, and it has no
    /// default on purpose: `bumpVersion()` declares `Damage.everything`, so before it was asked for,
    /// undoing a fill on a 2,000-stroke cel re-stamped all 472,000 dabs — MEASURED at 1.1 s a press
    /// (PERFORMANCE.md §11.11). Every call site answers, and since TODO (41)'s last box both answers
    /// are bounded: a rewrite names its ids and `restoreElements(_:changedInk:rewriting:)` reads each
    /// one's old footprint off the canvas at the press and derives its new one.
    ///
    /// **Neither closure captures a rectangle**, and for a rewrite that is load-bearing rather than
    /// tidy: the departing half of a rewrite is the footprint the *last render* measured, which the
    /// forward edit could not know, and a remembered rectangle would under-declare it wherever the
    /// render had to widen. Both directions read the canvas as it stands.
    func registerVectorElementsUndo(vectorCanvas: VectorCanvas,
                                    oldElements: [VectorElement], newElements: [VectorElement],
                                    layerID: UUID, celID: UUID, label: HistoryActionLabel,
                                    swap: ElementSwap) {
        // See `VectorUndoCost`: the flat 512 an element it replaces was a proxy for
        // `MemoryLayout<VectorElement>.stride`, which is 576 today, and it charged the two lists
        // where a run of steps holds one array apiece.
        let cost = VectorUndoCost.bytes(from: oldElements, to: newElements)
        let ink: CGRect?
        let rewritten: Set<UUID>
        switch swap {
        case .addsAndRemoves(let rect): ink = rect; rewritten = []
        case .rewritesInPlace(let ids): ink = nil; rewritten = ids
        }
        // One rectangle bounds every pixel where the two lists differ in either direction.
        // The rewritten set reads the same way too — the ids are the same ids.
        recordUndo(label: label, cost: cost, undo: { [weak self] in
            vectorCanvas.restoreElements(oldElements, changedInk: ink, rewriting: rewritten)
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        }, redo: { [weak self] in
            vectorCanvas.restoreElements(newElements, changedInk: ink, rewriting: rewritten)
            self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        })
    }

}
