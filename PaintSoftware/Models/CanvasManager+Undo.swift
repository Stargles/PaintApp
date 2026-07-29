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
    }

    private func captureStructure() -> StructureSnapshot {
        StructureSnapshot(layers: layers, folders: folders, viewPresets: viewPresets,
                          activeViewPresetIndex: activeViewPresetIndex,
                          currentLayerIndex: currentLayerIndex, sceneFrameCount: sceneFrameCount)
    }

    private func restoreStructure(_ snapshot: StructureSnapshot) {
        layers = snapshot.layers
        folders = snapshot.folders
        viewPresets = snapshot.viewPresets
        activeViewPresetIndex = snapshot.activeViewPresetIndex
        currentLayerIndex = snapshot.currentLayerIndex
        sceneFrameCount = snapshot.sceneFrameCount
    }

    /// Registers one undo step for a discrete (non-gesture) structural edit — call after the
    /// mutation has already happened, passing a `before` snapshot taken right before it.
    private func recordStructureChange(name: String, from: StructureSnapshot, to: StructureSnapshot) {
        recordUndo(name: name, cost: 4096, undo: { [weak self] in
            self?.restoreStructure(from)
        }, redo: { [weak self] in
            self?.restoreStructure(to)
        })
    }

    /// Snapshots structure, runs `body`, and records the difference as one undo step named `name`.
    /// This is the call shape for discrete edits; continuous drags use
    /// `beginStructureGesture`/`commitStructureGesture` instead.
    ///
    /// Nests safely: composite operations build on the primitives (merging calls `deleteLayer`,
    /// which is itself wrapped), and a drag bracketed by `beginStructureGesture` may call several
    /// of them. Only the outermost scope captures and records, so one user action is always exactly
    /// one undo step — without this, merging would record a bare "Delete Layer" that reverses half
    /// the operation and leaves the survivor flattened.
    func withStructureUndo(name: String, _ body: () -> Void) {
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
        recordStructureChange(name: name, from: before, to: captureStructure())
    }

    func beginStructureGesture() {
        // Same rule as `withStructureUndo`: bake transients before the baseline snapshot, so the
        // drag about to start doesn't span a shape/fill that wasn't committed when it began.
        beginCanvasEdit()
        gestureSnapshot = captureStructure()
    }

    func commitStructureGesture(name: String) {
        guard let before = gestureSnapshot else { return }
        gestureSnapshot = nil
        recordStructureChange(name: name, from: before, to: captureStructure())
    }

    /// Drops a gesture's snapshot without recording anything — for a drag that ended up changing
    /// nothing, or was cancelled. Leaving the snapshot in place instead would hand it to whichever
    /// gesture committed next, which would then record an undo step spanning both.
    func cancelStructureGesture() {
        gestureSnapshot = nil
    }
}
