import SwiftUI

// MARK: - Interpolation: registries, recipes and their undo mapping
//
// The document-level motion-group and guide registries live on `CanvasManager` itself (a Swift
// extension cannot declare stored properties); everything that *edits* them lives here, so that
// every interpolation mutation goes through one file with its undo bracket already attached.
//
// Nothing in the app calls any of this yet — the feature is inert until Phase 4. It exists now
// because the undo mapping is the part that is expensive to retrofit: an edit written without a
// bracket looks fine until the artist presses undo.

extension CanvasManager {

    // MARK: - Undo bracket

    /// One undo step for an interpolation edit, covering the document-level registries, the layer
    /// tree, **and** the contents of any vector canvases the edit touches.
    ///
    /// `withStructureUndo` is not sufficient on its own here, and the reason is worth stating
    /// because it is easy to get wrong in the other direction: `StructureSnapshot` copies
    /// `[Layer]`, and `Cel.vector` is a *class reference*, so the snapshot shares each canvas rather
    /// than copying it. Restoring it restores frame ranges and recipes but nothing about the strokes
    /// inside — which is exactly right for a timeline edit, and exactly wrong for a retag, since a
    /// stroke's motion-group tag is a field on `VectorStroke`. So an edit that spans both tiers has
    /// to snapshot both, in one step, which is what this does.
    ///
    /// Pass only the canvases actually affected: each one costs a display-list copy (cheap — the
    /// arrays hold value types whose heavy parts are shared) but the cost is per canvas, and a
    /// document can hold a great many.
    ///
    /// Defers to an enclosing scope the way `withStructureUndo` does. Note the enclosing scope
    /// records only the structure tier, so a vector-content edit nested inside a structural one
    /// would not be undoable; nothing does that today, and the fix if something ever needs to is to
    /// widen the outer bracket rather than to record twice here.
    func withInterpolationUndo(name: String, touching canvases: [VectorCanvas] = [],
                               _ body: () -> Void) {
        guard structureUndoDepth == 0, gestureSnapshot == nil else {
            body()
            return
        }
        // Same rule as `withStructureUndo`: bake a pending shape/fill first, so the transient lands
        // as its own earlier step instead of being swallowed into this one.
        beginCanvasEdit()

        let groupsBefore = motionGroups
        let guidesBefore = guideStrokes
        let layersBefore = layers
        let elementsBefore = canvases.map { $0.elements }

        structureUndoDepth += 1
        body()
        structureUndoDepth -= 1

        let groupsAfter = motionGroups
        let guidesAfter = guideStrokes
        let layersAfter = layers
        let elementsAfter = canvases.map { $0.elements }

        let cost = 4096 + elementsBefore.reduce(0) { $0 + $1.count * 512 }
        recordUndo(name: name, cost: cost, undo: { [weak self] in
            self?.applyInterpolationState(groups: groupsBefore, guides: guidesBefore,
                                          layers: layersBefore, canvases: canvases,
                                          elements: elementsBefore)
        }, redo: { [weak self] in
            self?.applyInterpolationState(groups: groupsAfter, guides: guidesAfter,
                                          layers: layersAfter, canvases: canvases,
                                          elements: elementsAfter)
        })
    }

    private func applyInterpolationState(groups: [MotionGroup], guides: [GuideStroke],
                                         layers restoredLayers: [Layer], canvases: [VectorCanvas],
                                         elements: [[VectorElement]]) {
        motionGroups = groups
        guideStrokes = guides
        layers = restoredLayers
        for (canvas, list) in zip(canvases, elements) {
            canvas.elements = list
            // The setters deliberately do not invalidate — see `VectorCanvas`'s accessor contract —
            // so every wholesale assignment has to bump the version itself.
            canvas.bumpVersion()
        }
    }

    // MARK: - Motion groups

    func motionGroup(withID id: UUID) -> MotionGroup? {
        motionGroups.first { $0.id == id }
    }

    @discardableResult
    func addMotionGroup(name: String, tagColor: CodableColor,
                        mode: GroupInterpolation = .auto) -> MotionGroup {
        let group = MotionGroup(displayName: name, tagColor: tagColor, mode: mode)
        withInterpolationUndo(name: "Add Motion Group") {
            motionGroups.append(group)
        }
        return group
    }

    func setMotionGroupMode(_ mode: GroupInterpolation, forGroup id: UUID) {
        guard let index = motionGroups.firstIndex(where: { $0.id == id }),
              motionGroups[index].mode != mode else { return }
        withInterpolationUndo(name: "Change Group Mode") {
            motionGroups[index].mode = mode
        }
    }

    /// Deletes a group, clears its tag off every stroke carrying it, and drops the per-keyframe
    /// bindings that referenced it — all as one undo step, because they are one action.
    ///
    /// Guides bound to the group are left alone on purpose. Emptying a guide's `boundGroups` would
    /// silently *promote* it to a whole-frame guide (empty means "every group" — PLAN §10 decision
    /// 6), which is a much worse outcome than leaving a dangling id: a dangling id simply makes the
    /// guide drive nothing, which is what deleting its group means.
    func removeMotionGroup(_ id: UUID) {
        guard motionGroups.contains(where: { $0.id == id }) else { return }
        let tagged = canvasesContainingStrokes { $0.motionGroupID == id }
        withInterpolationUndo(name: "Delete Motion Group", touching: tagged) {
            motionGroups.removeAll { $0.id == id }
            retag(in: tagged, to: nil) { $0.motionGroupID == id }
            for layerIndex in layers.indices {
                for celIndex in layers[layerIndex].cels.indices {
                    layers[layerIndex].cels[celIndex].interpolation?.groups.removeAll { $0.groupID == id }
                }
            }
        }
    }

    /// Assigns (or with a nil `groupID`, clears) the motion-group tag on the named strokes, wherever
    /// in the document they live. One step, spanning as many layers and cels as the selection does —
    /// which is the point of groups being document-level.
    func setMotionGroup(_ groupID: UUID?, forStrokeIDs strokeIDs: Set<UUID>) {
        guard !strokeIDs.isEmpty else { return }
        let affected = canvasesContainingStrokes { strokeIDs.contains($0.id) }
        guard !affected.isEmpty else { return }
        withInterpolationUndo(name: groupID == nil ? "Clear Motion Group" : "Tag Motion Group",
                              touching: affected) {
            retag(in: affected, to: groupID) { strokeIDs.contains($0.id) }
        }
    }

    /// Every vector canvas in the document holding at least one stroke matching `predicate`.
    private func canvasesContainingStrokes(_ predicate: (VectorStroke) -> Bool) -> [VectorCanvas] {
        layers.flatMap { $0.cels.compactMap(\.vector) }
            .filter { canvas in canvas.elements.contains { ($0.stroke.map(predicate)) == true } }
    }

    private func retag(in canvases: [VectorCanvas], to groupID: UUID?,
                       where predicate: (VectorStroke) -> Bool) {
        for canvas in canvases {
            canvas.elements = canvas.elements.map { element in
                guard case .stroke(var stroke) = element, predicate(stroke) else { return element }
                stroke.motionGroupID = groupID
                return .stroke(stroke)
            }
            canvas.bumpVersion()
        }
    }

    // MARK: - Recipes

    /// Locates a cel by identity rather than by index, because a recipe outlives the timeline edits
    /// that renumber cels around it.
    func celIndices(forCel celID: UUID, inLayer layerID: UUID) -> (layer: Int, cel: Int)? {
        guard let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
              let celIndex = layers[layerIndex].cels.firstIndex(where: { $0.id == celID })
        else { return nil }
        return (layerIndex, celIndex)
    }

    /// Attaches, replaces or (with nil) removes a cel's recipe. Removing one leaves whatever content
    /// the cel already had — the recipe is what *derives* content, not the content itself, so
    /// dropping it must never delete a drawing.
    func setInterpolation(_ recipe: InterpolationRecipe?, forCel celID: UUID, inLayer layerID: UUID) {
        guard let at = celIndices(forCel: celID, inLayer: layerID) else { return }
        withInterpolationUndo(name: recipe == nil ? "Remove Interpolation" : "Interpolate") {
            layers[at.layer].cels[at.cel].interpolation = recipe
        }
    }

    /// The slider's touch-down. Pairs with `commitInterpolationDrag` to make a whole drag **one**
    /// undo step rather than one per tick — the trap PLAN §9 calls out by name, and the same bracket
    /// `resizeCelLeftEdge` uses for the timeline's drags.
    ///
    /// `t` lives in the `Cel` struct, so the plain structure bracket is enough: no vector canvas
    /// changes while the slider moves, because the display list is *derived* from the recipe rather
    /// than rewritten by it.
    func beginInterpolationDrag() {
        beginStructureGesture()
    }

    /// Sets `t` mid-drag. Records nothing — the bracket owns the step.
    func setInterpolationT(_ t: CGFloat, forCel celID: UUID, inLayer layerID: UUID) {
        guard let at = celIndices(forCel: celID, inLayer: layerID),
              layers[at.layer].cels[at.cel].interpolation != nil else { return }
        layers[at.layer].cels[at.cel].interpolation?.t = min(max(t, 0), 1)
    }

    func commitInterpolationDrag() {
        commitStructureGesture(name: "Adjust Timing")
    }

    // MARK: - Render-cache eviction

    /// How many vector cels may keep a memoized render at once.
    ///
    /// A canvas-sized RGBA image is ~16 MB at 2048² and ~64 MB at 4000², so the bound is what keeps
    /// a long animation on a vector layer from holding one per cel. Twelve covers the frames a
    /// scrub or an onion skin actually reaches while leaving the rest evictable.
    static let vectorRenderCacheLimit = 12

    /// Drops memoized renders from the vector cels furthest from the current frame, keeping at most
    /// `limit` of them.
    ///
    /// `VectorCanvas.cachedImage` had no eviction at all, which was survivable while one cel per
    /// layer was live — PLAN §8 flags it as the thing to fix before interpolation ships, because an
    /// interpolated cel is *derived* and so multiplies how many canvases exist at once.
    ///
    /// The policy is distance from `currentFrame` rather than least-recently-used: it needs no
    /// per-canvas bookkeeping, it is deterministic (so it is testable), and it matches how the
    /// caches are actually reached — scrubbing and onion skin both work outward from the current
    /// frame. Dropping a cache is never a correctness question; the next render recomputes it.
    func evictDistantVectorRenderCaches(limit: Int = CanvasManager.vectorRenderCacheLimit) {
        var cached: [(distance: Int, canvas: VectorCanvas)] = []
        for layer in layers {
            for cel in layer.cels {
                guard let canvas = cel.vector, canvas.hasCachedImage else { continue }
                cached.append((distance: Self.frameDistance(from: currentFrame, to: cel), canvas: canvas))
            }
        }
        guard cached.count > max(0, limit) else { return }
        // Stable by construction: `sorted(by:)` is not stable in Swift, but ties are broken only
        // between canvases at the same distance, and which of those is dropped does not matter.
        for entry in cached.sorted(by: { $0.distance < $1.distance }).dropFirst(max(0, limit)) {
            entry.canvas.dropCachedImage()
        }
    }

    /// Frames between `frame` and the nearest frame `cel` occupies. Zero while the cel is on screen.
    private static func frameDistance(from frame: Int, to cel: Cel) -> Int {
        if frame >= cel.startFrame && frame < cel.endFrame { return 0 }
        return frame < cel.startFrame ? cel.startFrame - frame : frame - (cel.endFrame - 1)
    }

    // MARK: - Guides

    @discardableResult
    func addGuideStroke(_ guide: GuideStroke) -> GuideStroke {
        withInterpolationUndo(name: "Add Guide") {
            guideStrokes.append(guide)
        }
        return guide
    }

    /// Replaces a guide in place, keeping its id — which is what makes an edit propagate to every
    /// interval referencing it (PLAN §6.4's "link", as opposed to "duplicate").
    func updateGuideStroke(_ guide: GuideStroke) {
        guard let index = guideStrokes.firstIndex(where: { $0.id == guide.id }) else { return }
        withInterpolationUndo(name: "Edit Guide") {
            guideStrokes[index] = guide
        }
    }

    func removeGuideStroke(id: UUID) {
        guard guideStrokes.contains(where: { $0.id == id }) else { return }
        withInterpolationUndo(name: "Delete Guide") {
            guideStrokes.removeAll { $0.id == id }
            for layerIndex in layers.indices {
                for celIndex in layers[layerIndex].cels.indices {
                    layers[layerIndex].cels[celIndex].interpolation?.guideIDs.removeAll { $0 == id }
                    guard var recipe = layers[layerIndex].cels[celIndex].interpolation else { continue }
                    for groupIndex in recipe.groups.indices {
                        recipe.groups[groupIndex].guideIDs.removeAll { $0 == id }
                    }
                    layers[layerIndex].cels[celIndex].interpolation = recipe
                }
            }
        }
    }
}
