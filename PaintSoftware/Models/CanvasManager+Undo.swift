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
        var sceneFrameCount: Int
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
    }

    private func captureStructure() -> StructureSnapshot {
        StructureSnapshot(layers: layers, folders: folders, viewPresets: viewPresets,
                          activeViewPresetIndex: activeViewPresetIndex,
                          currentLayerIndex: currentLayerIndex, sceneFrameCount: sceneFrameCount,
                          motionGroups: motionGroups, guideStrokes: guideStrokes,
                          animationGroups: animationGroups, videoCrops: captureVideoCrops())
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
                for index in elements.indices {
                    guard case .video(var video) = elements[index],
                          let crop = crops[video.id], VideoCrop(of: video) != crop else { continue }
                    video.sourceStart = crop.start
                    video.sourceEnd = crop.end
                    video.speed = crop.speed
                    elements[index] = .video(video)
                    changed = true
                }
                guard changed else { continue }
                vector.elements = elements
                vector.bumpVersion()
            }
        }
    }

    private func restoreStructure(_ snapshot: StructureSnapshot) {
        layers = snapshot.layers
        folders = snapshot.folders
        viewPresets = snapshot.viewPresets
        activeViewPresetIndex = snapshot.activeViewPresetIndex
        currentLayerIndex = snapshot.currentLayerIndex
        sceneFrameCount = snapshot.sceneFrameCount
        // The scene may have been longer when the playhead was last moved — undoing the edit that
        // lengthened it would otherwise leave the playhead parked past the new end, reading as
        // "Frame 14/12". Adding a drawing out beyond the last frame (the timeline scrolls on
        // forever, so that is an ordinary thing to do now) is exactly such an edit.
        currentFrame = min(currentFrame, max(sceneFrameCount - 1, 0))
        motionGroups = snapshot.motionGroups
        guideStrokes = snapshot.guideStrokes
        animationGroups = snapshot.animationGroups
        // After `layers`, because it writes through the canvases the restored cels name.
        restoreVideoCrops(snapshot.videoCrops)
    }

    /// Registers one undo step for a discrete (non-gesture) structural edit — call after the
    /// mutation has already happened, passing a `before` snapshot taken right before it.
    private func recordStructureChange(label: HistoryActionLabel, from: StructureSnapshot, to: StructureSnapshot) {
        recordUndo(label: label, cost: 4096, undo: { [weak self] in
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
            body() // an enclosing scope is already recording this
            return
        }
        // Every structural edit is a canvas edit, so a pending shape/fill bakes first — before the
        // snapshot below, so the transient lands as its own earlier undo step rather than being
        // swallowed into this one (or re-baking afterwards on top of it). This one call is what
        // covers add/delete/merge/duplicate/group/restack/rasterize/clear and every cel-timeline
        // operation: they all funnel through here. See `beginCanvasEdit`.
        beginCanvasEdit()
        let before = captureStructure()
        structureUndoDepth += 1
        defer { structureUndoDepth -= 1 }
        body()
        recordStructureChange(label: label, from: before, to: captureStructure())
    }

    /// Opens a gesture bracket. **Nests**, for the same reason `withStructureUndo` does: only the
    /// outermost scope captures a baseline, so one user action is one undo step even when a bracket
    /// spans another — a mask-edit session (§6.6) is open for as long as a layer's options menu is,
    /// and the rows under it can start an opacity drag inside it.
    func beginStructureGesture() {
        structureGestureDepth += 1
        guard structureGestureDepth == 1 else { return }
        // Same rule as `withStructureUndo`: bake transients before the baseline snapshot, so the
        // drag about to start doesn't span a shape/fill that wasn't committed when it began.
        beginCanvasEdit()
        gestureSnapshot = captureStructure()
    }

    /// Closes a bracket, recording the step only when the outermost one closes. An inner `label` is
    /// discarded rather than winning: the step belongs to the action that spans the others.
    func commitStructureGesture(label: HistoryActionLabel) {
        if structureGestureDepth > 0 { structureGestureDepth -= 1 }
        guard structureGestureDepth == 0, let before = gestureSnapshot else { return }
        gestureSnapshot = nil
        recordStructureChange(label: label, from: before, to: captureStructure())
    }

    /// Drops a gesture's snapshot without recording anything — for a drag that ended up changing
    /// nothing, or was cancelled. Leaving the snapshot in place instead would hand it to whichever
    /// gesture committed next, which would then record an undo step spanning both. Cancelling an
    /// *inner* bracket keeps the outer one's baseline: the enclosing action is still in progress.
    func cancelStructureGesture() {
        if structureGestureDepth > 0 { structureGestureDepth -= 1 }
        guard structureGestureDepth == 0 else { return }
        gestureSnapshot = nil
    }
}
