import SwiftUI

// MARK: - Interpolation: registries, recipes and their undo mapping
//
// The document-level motion-group and guide registries live on `CanvasManager` itself (an
// extension cannot declare stored properties); everything that edits them lives here with the
// undo bracket attached.

extension CanvasManager {

    // MARK: - Undo bracket

    /// One undo step for an interpolation edit: document-level registries, layer tree, and the
    /// contents of any vector canvases the edit touches. `withStructureUndo` alone is not enough —
    /// it copies `[Layer]`, but `Cel.vector` is a class reference and gets shared rather than
    /// copied, wrong for a retag since a stroke's motion-group tag lives on `VectorStroke`. Pass
    /// only the canvases actually affected. Defers to an enclosing scope like `withStructureUndo`.
    func withInterpolationUndo(name: String, touching canvases: [VectorCanvas] = [],
                               _ body: () -> Void) {
        guard structureUndoDepth == 0, gestureSnapshot == nil else {
            body()
            return
        }
        // Bake a pending shape/fill first, so it lands as its own earlier step.
        beginCanvasEdit()

        let groupsBefore = motionGroups
        let guidesBefore = guideStrokes
        let layersBefore = layers
        let elementsBefore = canvases.map { $0.elements }

        // `defer` guards against `body` exiting early and leaving undo disabled.
        do {
            structureUndoDepth += 1
            defer { structureUndoDepth -= 1 }
            body()
        }

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
            // Setters don't invalidate, so a wholesale assignment bumps the version itself.
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
    /// bindings that referenced it, all as one undo step. Guides bound to the group are left alone:
    /// emptying a guide's `boundGroups` would silently promote it to a whole-frame guide (empty
    /// means "every group"), worse than the dangling id.
    func removeMotionGroup(_ id: UUID) {
        guard motionGroups.contains(where: { $0.id == id }) else { return }
        let tagged = celsContainingStrokes { $0.motionGroupID == id }.map(\.canvas)
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

    /// Assigns (or with nil, clears) the motion-group tag on the named strokes, wherever in the
    /// document they live, one step spanning every layer and cel touched. Re-registers every recipe
    /// reading a touched cel in the same step — a tag is only half of a motion group, the other
    /// half being the fitted lattice, so retagging alone would change the colour-coding but leave
    /// the motion as it was.
    func setMotionGroup(_ groupID: UUID?, forStrokeIDs strokeIDs: Set<UUID>) {
        guard !strokeIDs.isEmpty else { return }
        let affected = celsContainingStrokes { strokeIDs.contains($0.id) }
        guard !affected.isEmpty else { return }
        let touched = Set(affected.map(\.ref))
        withInterpolationUndo(name: groupID == nil ? "Clear Motion Group" : "Tag Motion Group",
                              touching: canvasesReached(byRetagging: touched)) {
            retag(in: affected.map(\.canvas), to: groupID) { strokeIDs.contains($0.id) }
            reregisterInterpolations(reading: touched)
        }
    }

    /// Re-runs registration for every recipe reading any of `cels`, keeping each recipe's `t`, mode,
    /// guides and local edits, replacing only its group bindings. Records no undo step of its own —
    /// the caller owns the bracket, and it must be `touching: canvasesReached(byRetagging:)`, since
    /// re-registration writes tags onto every keyframe of every recipe it re-runs.
    func reregisterInterpolations(reading cels: Set<CelRef>) {
        let provider = interpolationContentProvider
        var targets: [(layer: Int, cel: Int)] = []
        for layerIndex in layers.indices {
            for celIndex in layers[layerIndex].cels.indices {
                guard let recipe = layers[layerIndex].cels[celIndex].interpolation,
                      recipe.referencedCels.contains(where: cels.contains) else { continue }
                targets.append((layerIndex, celIndex))
            }
        }
        for at in targets {
            guard var recipe = layers[at.layer].cels[at.cel].interpolation else { continue }
            let frames = recipe.references.map {
                Self.registrationFrame(of: $0.cels.flatMap(provider))
            }
            let registration = Self.registerGroups(frames: frames, existing: motionGroups)
            recipe.groups = registration.bindings
            motionGroups.append(contentsOf: registration.invented)
            applyMotionGroupTags(registration.assignments, to: recipe.references)
            layers[at.layer].cels[at.cel].interpolation = recipe
        }
    }

    // MARK: - The groups the bar shows, and the retagging gesture

    /// One chip's worth of state — a registered group plus how much of the current keyframes is
    /// actually in it.
    struct MotionGroupChip: Identifiable {
        var group: MotionGroup
        /// Strokes carrying this group's id across every flagged keyframe. Zero is meaningful — a
        /// group the artist emptied — so it stays shown rather than hidden as unreachable.
        var strokeCount: Int
        var isArmed: Bool
        var isHidden: Bool
        var id: UUID { group.id }
    }

    /// The groups `InterpolateBar` puts on screen, in registry order — the registry, not the active
    /// recipe's bindings, since a `MotionGroup` is document-level (one group can span a lineart and
    /// a flats layer). Counts are over the flagged keyframes. The default whole-frame binding has no
    /// registry entry and contributes no chip; `hasAnonymousWholeFrameGroup` says so in words.
    var motionGroupChips: [MotionGroupChip] {
        let provider = interpolationContentProvider
        var counts: [UUID: Int] = [:]
        for reference in interpolationKeyframes {
            for element in reference.cels.flatMap(provider) {
                guard let id = element.stroke?.motionGroupID else { continue }
                counts[id, default: 0] += 1
            }
        }
        return motionGroups.map {
            MotionGroupChip(group: $0, strokeCount: counts[$0.id] ?? 0,
                            isArmed: armedMotionGroupID == $0.id,
                            isHidden: hiddenMotionGroups.contains($0.id))
        }
    }

    /// True when the cel under the playhead derives from a recipe whose grouping is the default
    /// anonymous whole-frame binding — one part, no registry entry, nothing tagged.
    var hasAnonymousWholeFrameGroup: Bool {
        guard let at = interpolationTarget,
              let recipe = layers[at.layer].cels[at.cel].interpolation,
              recipe.groups.count == 1 else { return false }
        return motionGroup(withID: recipe.groups[0].groupID) == nil
    }

    /// Arms a group for tap-to-assign, or disarms it when already armed. Arming a different group
    /// while one is armed just moves the arming.
    func toggleArmedMotionGroup(_ id: UUID) {
        armedMotionGroupID = armedMotionGroupID == id ? nil : id
    }

    /// The retagging gesture: assign the stroke under `point` on the current layer to the armed
    /// group, or nil when nothing was armed, the layer isn't vector, or the tap landed on bare
    /// canvas. Tapping a stroke already in the armed group clears its tag instead, so it is
    /// re-decided by geometry on the next registration (`InterpolationMotionGroupLogicTests` pins
    /// this). Goes through `setMotionGroup`, so it re-registers and undoes in one step.
    @discardableResult
    func assignArmedMotionGroup(atCanvasPoint point: CGPoint) -> UUID? {
        guard let armed = armedMotionGroupID, isInterpolateMode,
              let at = interpolationTarget,
              let canvas = layers[at.layer].cels[at.cel].vector,
              let stroke = canvas.topmostStroke(atCanvasPoint: point) else { return nil }
        setMotionGroup(stroke.motionGroupID == armed ? nil : armed, forStrokeIDs: [stroke.id])
        return stroke.id
    }

    // MARK: - "What did it decide?" — the tinted overlay

    /// A keyframe's own drawing, with every stroke repainted in its motion group's tag colour — the
    /// "what did it decide?" legibility pass. Nil unless interpolate mode and the overlay are on and
    /// something is tagged. Returns the whole display list, not just tagged strokes: the seam it
    /// renders through replaces the cel's display, so tinted strokes alone would make every fill and
    /// placed image vanish. Untagged strokes are grey, to show they ride the first binding.
    func motionGroupOverlayImage(forCel celID: UUID, inLayer layerID: UUID) -> UIImage? {
        guard isInterpolateMode, showMotionGroupOverlay,
              let at = celIndices(forCel: celID, inLayer: layerID),
              let canvas = layers[at.layer].cels[at.cel].vector else { return nil }
        let elements = canvas.elements
        guard elements.contains(where: { $0.stroke?.motionGroupID != nil }) else { return nil }

        let untagged = CodableColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1)
        let tinted: [VectorElement] = elements.map { element in
            guard case .stroke(var stroke) = element, stroke.composite == .paint else { return element }
            stroke.color = stroke.motionGroupID.flatMap { motionGroup(withID: $0)?.tagColor } ?? untagged
            stroke.opacity = 1
            return .stroke(stroke)
        }
        return VectorCanvas(size: canvas.size, elements: tinted).render(quality: .preview)
    }

    // MARK: - Solo and mute

    /// Hides or shows one group in the interpolated preview.
    func toggleMotionGroupHidden(_ id: UUID) {
        if hiddenMotionGroups.contains(id) { hiddenMotionGroups.remove(id) }
        else { hiddenMotionGroups.insert(id) }
    }

    /// Solo: show only this group. Pressing it again on the already-alone group clears the filter
    /// instead of hiding everything, so solo can be its own off switch.
    func soloMotionGroup(_ id: UUID) {
        let others = Set(motionGroups.map(\.id)).subtracting([id])
        hiddenMotionGroups = hiddenMotionGroups == others ? [] : others
    }

    // MARK: - Tag by stroke colour

    /// **Tag by stroke colour** — a one-shot populate. Clusters the strokes of `cels` by paint
    /// colour and writes one motion group per cluster, then re-registers. A populate, never a live
    /// binding: recolouring a stroke afterward does not move it to a different group. Mitigates
    /// automatic grouping's inability to separate an attached limb from its torso
    /// (VECTOR_INTERPOLATION.md §4 item 1). Erasers are skipped and left untagged, riding the
    /// recipe's first binding. Returns the groups it created, in cluster order.
    @discardableResult
    func tagMotionGroupsByStrokeColour(in cels: [CelRef],
                                       tolerance: CGFloat = 0.08) -> [MotionGroup] {
        let resolved: [(ref: CelRef, canvas: VectorCanvas)] = cels.compactMap { ref in
            celIndices(forCel: ref.celID, inLayer: ref.layerID)
                .flatMap { layers[$0.layer].cels[$0.cel].vector }
                .map { (ref, $0) }
        }
        guard !resolved.isEmpty else { return [] }

        // One pass in document order, so clusters and group names come out the same every run.
        var representatives: [CodableColor] = []
        var clusterOfStroke: [UUID: Int] = [:]
        for (_, canvas) in resolved {
            for element in canvas.elements {
                guard case .stroke(let stroke) = element, stroke.composite != .erase else { continue }
                if let existing = representatives.firstIndex(where: {
                    Self.colourDistance($0, stroke.color) <= tolerance
                }) {
                    clusterOfStroke[stroke.id] = existing
                } else {
                    clusterOfStroke[stroke.id] = representatives.count
                    representatives.append(stroke.color)
                }
            }
        }
        // One colour is not a grouping — it's the whole-frame group the drawing already had.
        guard representatives.count > 1 else { return [] }

        var created: [MotionGroup] = []
        for index in representatives.indices {
            let slot = motionGroups.count + index
            created.append(MotionGroup(displayName: "Colour \(index + 1)",
                                       tagColor: Self.motionGroupPalette[slot % Self.motionGroupPalette.count]))
        }

        let touched = Set(resolved.map(\.ref))
        withInterpolationUndo(name: "Tag by Stroke Colour",
                              touching: canvasesReached(byRetagging: touched)) {
            motionGroups.append(contentsOf: created)
            for (_, canvas) in resolved {
                var elements = canvas.elements
                var changed = false
                for index in elements.indices {
                    guard case .stroke(var stroke) = elements[index],
                          let cluster = clusterOfStroke[stroke.id],
                          stroke.motionGroupID != created[cluster].id else { continue }
                    stroke.motionGroupID = created[cluster].id
                    elements[index] = .stroke(stroke)
                    changed = true
                }
                if changed {
                    canvas.elements = elements
                    canvas.bumpVersion()
                }
            }
            reregisterInterpolations(reading: touched)
        }
        return created
    }

    /// How far apart two paint colours are, as the largest single-channel difference. Max-channel
    /// rather than Euclidean, so the tolerance means "no channel differs by more than this". Alpha
    /// is included: half opacity is a different paint choice from the same hue at full.
    private static func colourDistance(_ a: CodableColor, _ b: CodableColor) -> CGFloat {
        max(max(abs(a.red - b.red), abs(a.green - b.green)),
            max(abs(a.blue - b.blue), abs(a.alpha - b.alpha)))
    }

    /// Every vector cel in the document holding at least one stroke matching `predicate`, with the
    /// ref that addresses it.
    private func celsContainingStrokes(_ predicate: (VectorStroke) -> Bool)
        -> [(ref: CelRef, canvas: VectorCanvas)] {
        var result: [(ref: CelRef, canvas: VectorCanvas)] = []
        for layer in layers {
            for cel in layer.cels {
                guard let canvas = cel.vector,
                      canvas.elements.contains(where: { ($0.stroke.map(predicate)) == true })
                else { continue }
                result.append((CelRef(layerID: layer.id, celID: cel.id), canvas))
            }
        }
        return result
    }

    /// The canvases a retag of `cels` can write to: those cels themselves, plus every keyframe of
    /// every recipe that reads one of them — because re-registration tags all of them.
    private func canvasesReached(byRetagging cels: Set<CelRef>) -> [VectorCanvas] {
        var wanted = cels
        for layer in layers {
            for cel in layer.cels {
                guard let recipe = cel.interpolation,
                      recipe.referencedCels.contains(where: cels.contains) else { continue }
                wanted.formUnion(recipe.referencedCels)
            }
        }
        return wanted.compactMap { ref in
            celIndices(forCel: ref.celID, inLayer: ref.layerID)
                .flatMap { layers[$0.layer].cels[$0.cel].vector }
        }
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
    /// the cel already had — a recipe derives content, it isn't the content, so dropping it must
    /// never delete a drawing.
    func setInterpolation(_ recipe: InterpolationRecipe?, forCel celID: UUID, inLayer layerID: UUID) {
        guard let at = celIndices(forCel: celID, inLayer: layerID) else { return }
        withInterpolationUndo(name: recipe == nil ? "Remove Interpolation" : "Interpolate") {
            layers[at.layer].cels[at.cel].interpolation = recipe
        }
    }

    /// The slider's touch-down. Pairs with `commitInterpolationDrag` to make a whole drag one undo
    /// step. `t` lives in `Cel`, so the plain structure bracket suffices — the display list is
    /// derived from the recipe, not rewritten, so no vector canvas changes while the slider moves.
    func beginInterpolationDrag() {
        isScrubbingInterpolation = true
        beginStructureGesture()
    }

    /// Sets `t` mid-drag. Records nothing — the bracket owns the step.
    func setInterpolationT(_ t: CGFloat, forCel celID: UUID, inLayer layerID: UUID) {
        guard let at = celIndices(forCel: celID, inLayer: layerID),
              layers[at.layer].cels[at.cel].interpolation != nil else { return }
        layers[at.layer].cels[at.cel].interpolation?.t = min(max(t, 0), 1)
    }

    func commitInterpolationDrag() {
        isScrubbingInterpolation = false
        commitStructureGesture(name: "Adjust Timing")
    }

    // MARK: - Editing at an in-between

    /// The interpolated cel a layer is showing at the playhead, or nil when it is showing an
    /// ordinary drawing. Gated on "the cel carries a recipe", not "interpolate mode is on" — an
    /// interpolated cel shows its derived in-between in every mode. By layer, not by cel, since the
    /// caller is a layer's own canvas view; deliberately not `interpolationTarget` (the current
    /// layer's cel) — a touch is answered by the view it landed in.
    func inBetweenCelID(inLayer layerID: UUID) -> UUID? {
        guard let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
              let celIndex = activeCelIndex(inLayer: layerIndex, atFrame: currentFrame),
              layers[layerIndex].cels[celIndex].interpolation != nil
        else { return nil }
        return layers[layerIndex].cels[celIndex].id
    }

    /// The current layer is showing an interpolated cel at the playhead. The whole-content vector
    /// transform (`isVectorTransforming`) is refused on one: it writes onto the cel's own empty
    /// `VectorCanvas`, which the evaluated image doesn't come from.
    var activeCelIsInBetween: Bool {
        guard layers.indices.contains(currentLayerIndex) else { return false }
        return inBetweenCelID(inLayer: layers[currentLayerIndex].id) != nil
    }

    /// Records a stroke drawn at the in-between. Returns false when the recipe cannot take it, and
    /// the caller should fall back to committing the stroke normally.
    /// `InterpolationEvaluator.planLocalEdit` embeds the stroke in the deformed lattice at `t`,
    /// grows the lattice by whole rings if it falls outside, and maps it back to rest space; this
    /// writes the result and gives it τ = `t` so it doesn't appear before the frame it was drawn at.
    /// Samples go in without the canvas→local transform the ordinary stroke path applies, since the
    /// pipeline works in the display lists' own space.
    @discardableResult
    func recordLocalEdit(canvasSpaceStroke stroke: VectorStroke,
                         forCel celID: UUID, inLayer layerID: UUID) -> Bool {
        guard let at = celIndices(forCel: celID, inLayer: layerID),
              let recipe = layers[at.layer].cels[at.cel].interpolation,
              let plan = InterpolationEvaluator.planLocalEdit(
                recipe: recipe, at: recipe.t, points: stroke.samples.map(\.point),
                guides: guides(driving: recipe), options: interpolationOptions),
              plan.restPoints.count == stroke.samples.count
        else { return false }

        var stored = stroke
        stored.samples = zip(stroke.samples, plan.restPoints).map {
            VectorSample(x: $1.x, y: $1.y, pressure: $0.pressure)
        }
        // τ = `t`: enforced by the evaluator's `t >= τ` test, so sliding earlier than where it was
        // drawn hides the edit again.
        stored.visibilityThreshold = recipe.t
        // Group lives on `LocalEdit`, not the stroke's own tag — the edit belongs to neither
        // keyframe's drawing.
        stored.motionGroupID = nil

        let edit = LocalEdit(stroke: stored, groupID: plan.groupID)
        withInterpolationUndo(name: stroke.composite == .erase ? "Erase at In-Between"
                                                               : "Draw at In-Between") {
            // Grown lattices go back by reference, never index: a ring shifts every index.
            if let grown = plan.grownLattices, let index = plan.bindingIndex {
                layers[at.layer].cels[at.cel].interpolation?.groups[index].lattices = grown
            }
            layers[at.layer].cels[at.cel].interpolation?.localEdits.append(edit)
        }
        return true
    }

    // MARK: - Render-cache eviction

    /// How many vector cels may keep a memoized render at once. A canvas-sized RGBA image is ~16 MB
    /// at 2048² and ~64 MB at 4000²; twelve covers the frames a scrub or onion skin actually reaches.
    static let vectorRenderCacheLimit = 12

    /// Drops memoized renders from the vector cels furthest from the current frame, keeping at most
    /// `limit` of them. Distance from `currentFrame` rather than LRU: no per-canvas bookkeeping, and
    /// it matches how scrubbing and onion skin reach caches — outward from the current frame.
    func evictDistantVectorRenderCaches(limit: Int = CanvasManager.vectorRenderCacheLimit) {
        // Counted before locking anything — `hasCachedImage` takes each canvas's lock, which a
        // background `render()` can hold for tens of ms.
        let vectorCels = layers.reduce(0) { $0 + $1.cels.lazy.filter { $0.vector != nil }.count }
        guard vectorCels > max(0, limit) else { return }

        var cached: [(distance: Int, canvas: VectorCanvas)] = []
        for layer in layers {
            for cel in layer.cels {
                guard let canvas = cel.vector, canvas.hasCachedImage else { continue }
                cached.append((distance: Self.frameDistance(from: currentFrame, to: cel), canvas: canvas))
            }
        }
        guard cached.count > max(0, limit) else { return }
        for entry in cached.sorted(by: { $0.distance < $1.distance }).dropFirst(max(0, limit)) {
            entry.canvas.dropCachedImage()
        }
    }

    /// Frames between `frame` and the nearest frame `cel` occupies. Zero while the cel is on screen.
    private static func frameDistance(from frame: Int, to cel: Cel) -> Int {
        if frame >= cel.startFrame && frame < cel.endFrame { return 0 }
        return frame < cel.startFrame ? cel.startFrame - frame : frame - (cel.endFrame - 1)
    }

    // MARK: - Interpolate mode

    /// Enters interpolate mode with a clean reference selection.
    func enterInterpolateMode() {
        interpolationReferences.removeAll()
        isInterpolateMode = true
    }

    /// Leaves the mode and drops the reference selection. Recipes stay attached — the selection is a
    /// transient, the recipe is document content — so re-entering keeps every in-between working.
    func exitInterpolateMode() {
        isInterpolateMode = false
        interpolationReferences.removeAll()
        // View state meaningful only inside the mode; left set, each would turn the next gesture
        // into something unintended (silent retag, missing content, a stray guide).
        armedMotionGroupID = nil
        hiddenMotionGroups.removeAll()
        isDrawingGuide = false
        isEditingGuideSpacing = false
    }

    func isInterpolationReference(celID: UUID, inLayer layerID: UUID) -> Bool {
        interpolationReferences.contains(CelRef(layerID: layerID, celID: celID))
    }

    /// Flags or unflags a cel as a keyframe — `InterpolateBar`'s Set as Reference. Not undoable:
    /// this is a selection, like which layer is current. The recipe that results from a selection
    /// is undoable, in one step (`interpolate(...)`).
    func toggleInterpolationReference(celID: UUID, inLayer layerID: UUID) {
        let ref = CelRef(layerID: layerID, celID: celID)
        if let existing = interpolationReferences.firstIndex(of: ref) {
            interpolationReferences.remove(at: existing)
        } else {
            interpolationReferences.append(ref)
        }
    }

    /// The flagged cels grouped into keyframes, in time order. Cels that start on the same frame are
    /// one keyframe: a flagged lineart cel and the flats cel under it become one reference holding
    /// both, so they warp through one lattice. Grouped by `startFrame` rather than overlap, which
    /// would fold a long held cel in with every short cel beside it.
    var interpolationKeyframes: [InterpolationReference] {
        var byFrame: [Int: [CelRef]] = [:]
        for ref in interpolationReferences {
            guard let at = celIndices(forCel: ref.celID, inLayer: ref.layerID) else { continue }
            byFrame[layers[at.layer].cels[at.cel].startFrame, default: []].append(ref)
        }
        return byFrame.keys.sorted().map { InterpolationReference(cels: byFrame[$0] ?? []) }
    }

    /// Resolves a `CelRef` to the display list that cel holds — the evaluator's `ContentProvider`.
    /// Passed as a closure rather than the evaluator reaching for `CanvasManager` itself, so render
    /// tests can run without a document.
    var interpolationContentProvider: InterpolationEvaluator.ContentProvider {
        { [weak self] ref in
            guard let self, let at = self.celIndices(forCel: ref.celID, inLayer: ref.layerID) else {
                return []
            }
            return self.layers[at.layer].cels[at.cel].vector?.elements ?? []
        }
    }

    var interpolationOptions: InterpolationEvaluator.Options {
        var options = InterpolationEvaluator.Options()
        options.thicknessFade = interpolationThicknessFade ? .weighted(exponent: 1) : .none
        // Only inside the mode: a group left muted must not follow the artist out and quietly
        // blank part of every export.
        options.hiddenGroups = isInterpolateMode ? hiddenMotionGroups : []
        return options
    }

    /// `interpolationOptions` with solo/mute forced off — required for any evaluation written to the
    /// document (today, Commit), since baking with a group muted would delete that content for good.
    /// `thicknessFade` is kept: it's a rendering choice, not a filter.
    var interpolationCommitOptions: InterpolationEvaluator.Options {
        var options = interpolationOptions
        options.hiddenGroups = []
        return options
    }

    // MARK: - Creating a recipe

    /// Why `interpolate(...)` declined, for a UI that has to say something more useful than nothing.
    enum InterpolationRefusal: Equatable {
        /// Fewer than two keyframes are flagged.
        case notEnoughReferences
        /// The target cel is itself one of the flagged keyframes.
        case targetIsAReference
        /// The target cel is not on a vector layer.
        case notAVectorLayer
        /// Every flagged keyframe is empty, so there is nothing to register.
        case referencesAreEmpty
        /// The target cel already derives from a recipe — Generate would stack a second one on top.
        case alreadyInterpolated
        /// Reproject was asked for on a cel with no drawing of its own to repose.
        case nothingToReproject
        /// Commit was asked for on a cel that derives from nothing — there is no frame to bake.
        case nothingToCommit
        /// Commit was asked for on a recipe `evaluate` cannot render, so there is no frame *yet*.
        case interpolationNotEvaluable
        /// A guide was drawn on a frame with no recipe to attach it to — a guide constrains a
        /// motion, so a motion must exist first.
        case noInterpolationToGuide

        var message: String {
            switch self {
            case .notEnoughReferences: return "Set at least two reference frames first."
            case .targetIsAReference: return "This frame is a reference. Pick a different frame."
            case .notAVectorLayer: return "Interpolation works on vector layers."
            case .referencesAreEmpty: return "The reference frames have nothing to interpolate."
            case .alreadyInterpolated: return "This frame is already interpolated."
            case .nothingToReproject: return "Reproject needs a drawing in this frame."
            case .nothingToCommit: return "Commit needs an interpolated frame."
            case .interpolationNotEvaluable: return "This interpolation is not ready to commit."
            case .noInterpolationToGuide: return "Generate an in-between first, then guide it."
            }
        }
    }

    /// Whether `interpolate` would succeed for this cel, and why not if it would not.
    func interpolationRefusal(mode: InterpolationMode, layerIndex: Int, celIndex: Int) -> InterpolationRefusal? {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex),
              layers[layerIndex].cels[celIndex].vector != nil else { return .notAVectorLayer }
        // Generate on a cel that already has a recipe would silently replace it. Reproject does not
        // inherit this refusal: re-running it re-registers the same linework and replaces nothing.
        if mode == .generate, layers[layerIndex].cels[celIndex].interpolation != nil {
            return .alreadyInterpolated
        }
        if mode == .reproject, layers[layerIndex].cels[celIndex].vector?.elements.isEmpty != false {
            return .nothingToReproject
        }
        let target = CelRef(layerID: layers[layerIndex].id, celID: layers[layerIndex].cels[celIndex].id)
        return referenceRefusal(excludingTarget: target)
    }

    /// The refusal about the references rather than the target, reusable by the playhead check for
    /// a cel that does not exist yet.
    private func referenceRefusal(excludingTarget target: CelRef?) -> InterpolationRefusal? {
        let keyframes = interpolationKeyframes
        guard keyframes.count >= 2 else { return .notEnoughReferences }
        if let target, interpolationReferences.contains(target) { return .targetIsAReference }
        let provider = interpolationContentProvider
        guard keyframes.contains(where: { !$0.cels.flatMap(provider).isEmpty }) else {
            return .referencesAreEmpty
        }
        return nil
    }

    // MARK: - The playhead as the target

    /// The cel every interpolate command acts on: the one under the playhead on the current layer.
    /// Nil for an empty slot, which Generate treats as "make one" (see `interpolateAtPlayhead`).
    var interpolationTarget: (layer: Int, cel: Int)? {
        let layerIndex = currentLayerIndex
        guard layers.indices.contains(layerIndex),
              let celIndex = activeCelIndex(inLayer: layerIndex, atFrame: currentFrame) else { return nil }
        return (layerIndex, celIndex)
    }

    /// Whether Generate/Reproject would succeed at the playhead, **including** the case where there
    /// is no block there yet and one would be created.
    func interpolationRefusalAtPlayhead(mode: InterpolationMode) -> InterpolationRefusal? {
        if let at = interpolationTarget {
            return interpolationRefusal(mode: mode, layerIndex: at.layer, celIndex: at.cel)
        }
        // No block at the playhead: Reproject has nothing of the artist's own to repose.
        if mode == .reproject { return .nothingToReproject }
        // A missing block is not a refusal for Generate — it creates one.
        guard layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].kind == .vector else { return .notAVectorLayer }
        return referenceRefusal(excludingTarget: nil)
    }

    /// **Generate** — attach a recipe deriving this cel from the flagged keyframes. Does not write a
    /// display list into the cel: an in-between is derived, never stored, so moving the slider is a
    /// parameter change, not a regeneration. Baking is the separate, one-way **Commit** action.
    /// Registration runs here — an ARAP fit per reference, synchronous, so
    /// `isRegisteringInterpolation` brackets it for the caller. Returns the refusal reason, or nil.
    @discardableResult
    func interpolate(mode: InterpolationMode, layerIndex: Int, celIndex: Int) -> InterpolationRefusal? {
        if let refusal = interpolationRefusal(mode: mode, layerIndex: layerIndex, celIndex: celIndex) {
            return refusal
        }
        let keyframes = interpolationKeyframes
        isRegisteringInterpolation = true
        defer { isRegisteringInterpolation = false }

        let provider = interpolationContentProvider
        let frames = keyframes.map { Self.registrationFrame(of: $0.cels.flatMap(provider)) }

        // Reproject registers the cel's own drawing, not the keyframes' parts; no grouping runs.
        if mode == .reproject {
            let subject = Self.registrationFrame(of: layers[layerIndex].cels[celIndex].vector?.elements ?? [])
            guard let binding = Self.registerReprojection(subject: subject, frames: frames) else {
                return .nothingToReproject
            }
            let recipe = InterpolationRecipe(references: keyframes, t: 0.5, mode: .reproject,
                                             groups: [binding])
            // The structural bracket suffices: reprojection writes a value type and touches no stroke.
            withStructureUndo(name: "Reproject") {
                layers[layerIndex].cels[celIndex].interpolation = recipe
            }
            return nil
        }

        let registration = Self.registerGroups(frames: frames, existing: motionGroups)

        let recipe = InterpolationRecipe(references: keyframes, t: 0.5, mode: mode,
                                         groups: registration.bindings)
        // `withInterpolationUndo`: `StructureSnapshot` shares canvases rather than copying them, so
        // the structure bracket would restore the recipe but leave the tags on.
        withInterpolationUndo(name: "Interpolate", touching: interpolationReferenceCanvases) {
            motionGroups.append(contentsOf: registration.invented)
            applyMotionGroupTags(registration.assignments, to: keyframes)
            layers[layerIndex].cels[celIndex].interpolation = recipe
        }
        return nil
    }

    /// Every vector canvas the flagged keyframes live in — what a registration that writes tags back
    /// has to snapshot for undo.
    var interpolationReferenceCanvases: [VectorCanvas] {
        var seen = Set<UUID>()
        return interpolationKeyframes.flatMap(\.cels).compactMap { ref in
            guard seen.insert(ref.celID).inserted,
                  let at = celIndices(forCel: ref.celID, inLayer: ref.layerID) else { return nil }
            return layers[at.layer].cels[at.cel].vector
        }
    }

    /// Writes registration's grouping decision back onto the keyframes' own strokes, making the
    /// grouping visible and editable. Only strokes can carry a tag; a fill or placed image takes
    /// part in the partition but falls back to the first binding (VECTOR_INTERPOLATION.md §4 item
    /// 11). Call inside an undo bracket `touching:` these canvases.
    func applyMotionGroupTags(_ assignments: [[UUID?]], to keyframes: [InterpolationReference]) {
        for (frameIndex, reference) in keyframes.enumerated() where frameIndex < assignments.count {
            let tags = assignments[frameIndex]
            // Assignments are in `cels.flatMap(provider)` order; a cursor lines them back up here.
            var cursor = 0
            for celRef in reference.cels {
                guard let at = celIndices(forCel: celRef.celID, inLayer: celRef.layerID),
                      let canvas = layers[at.layer].cels[at.cel].vector else { continue }
                var elements = canvas.elements
                var changed = false
                for index in elements.indices {
                    let slot = cursor + index
                    guard slot < tags.count, case .stroke(var stroke) = elements[index],
                          stroke.motionGroupID != tags[slot] else { continue }
                    stroke.motionGroupID = tags[slot]
                    elements[index] = .stroke(stroke)
                    changed = true
                }
                cursor += elements.count
                if changed {
                    canvas.elements = elements
                    // Bumps the version, which re-keys the preview memo so the retag shows up.
                    canvas.bumpVersion()
                }
            }
        }
    }

    /// **Generate/Reproject as the bar presses them** — act on the playhead, creating the block if
    /// there is not one there yet. The block and recipe land as one undo step: `addCel` and
    /// `interpolate` both defer to an enclosing bracket, so the outer bracket here is all it takes —
    /// it must be the interpolation bracket, not the structure one, since registration tags strokes.
    @discardableResult
    func interpolateAtPlayhead(mode: InterpolationMode) -> InterpolationRefusal? {
        if let refusal = interpolationRefusalAtPlayhead(mode: mode) { return refusal }
        let layerIndex = currentLayerIndex
        if let at = interpolationTarget {
            return interpolate(mode: mode, layerIndex: at.layer, celIndex: at.cel)
        }
        let frame = currentFrame
        var result: InterpolationRefusal? = nil
        withInterpolationUndo(name: "Interpolate", touching: interpolationReferenceCanvases) {
            guard addCel(layerIndex: layerIndex, startFrame: frame, frameCount: 1),
                  let celIndex = activeCelIndex(inLayer: layerIndex, atFrame: frame) else {
                result = .notAVectorLayer
                return
            }
            result = interpolate(mode: mode, layerIndex: layerIndex, celIndex: celIndex)
        }
        return result
    }

    // MARK: - Commit

    /// **Commit** — bake the frame this cel currently derives at into ordinary content and drop the
    /// recipe. One-way and explicit, but undoable. Also the missing link for Reproject on an
    /// in-between: a `.generate` cel stores no strokes of its own, so Generate → Commit → Reproject
    /// is how it becomes reposable. Lossy at an interior `t` (`t = 0`/`t = 1` are bit-exact) — see
    /// `InterpolationEvaluator.flattened` for why. Returns the refusal reason, or nil on success.
    @discardableResult
    func commitInterpolation(layerIndex: Int, celIndex: Int) -> InterpolationRefusal? {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex),
              let canvas = layers[layerIndex].cels[celIndex].vector else { return .notAVectorLayer }
        guard let recipe = layers[layerIndex].cels[celIndex].interpolation else { return .nothingToCommit }
        // The cel's own display list is the subject for reprojection, ignored for generation.
        let subject = recipe.mode == .reproject ? canvas.elements : []
        // `interpolationCommitOptions`: committing with a group muted would delete content for good.
        guard let evaluation = InterpolationEvaluator.evaluate(
            recipe: recipe, at: recipe.t, content: interpolationContentProvider,
            subject: subject, guides: guides(driving: recipe),
            options: interpolationCommitOptions)
        else { return .interpolationNotEvaluable }

        let baked = InterpolationEvaluator.flattened(evaluation)
        // `withInterpolationUndo`: the structure bracket would restore the recipe but none of the ink.
        withInterpolationUndo(name: "Commit Interpolation", touching: [canvas]) {
            canvas.elements = baked
            canvas.bumpVersion()
            layers[layerIndex].cels[celIndex].interpolation = nil
        }
        return nil
    }

    /// Whether `commitInterpolation` would succeed, without performing it. Shares every check
    /// including the evaluation. Runs `evaluate`, an ARAP solve per motion group, so it is too
    /// expensive for a SwiftUI `body` — call only from an event handler.
    func commitRefusal(layerIndex: Int, celIndex: Int) -> InterpolationRefusal? {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex),
              let canvas = layers[layerIndex].cels[celIndex].vector else { return .notAVectorLayer }
        guard let recipe = layers[layerIndex].cels[celIndex].interpolation else { return .nothingToCommit }
        let subject = recipe.mode == .reproject ? canvas.elements : []
        guard InterpolationEvaluator.evaluate(recipe: recipe, at: recipe.t,
                                              content: interpolationContentProvider,
                                              subject: subject, guides: guides(driving: recipe),
                                              options: interpolationCommitOptions) != nil
        else { return .interpolationNotEvaluable }
        return nil
    }

    /// Commit the cel under the playhead on the current layer — what the bar's button calls.
    @discardableResult
    func commitInterpolationAtPlayhead() -> InterpolationRefusal? {
        guard let at = interpolationTarget else { return .nothingToCommit }
        return commitInterpolation(layerIndex: at.layer, celIndex: at.cel)
    }

    /// Removes a cel's recipe, leaving whatever content it already had.
    func removeInterpolation(layerIndex: Int, celIndex: Int) {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex),
              layers[layerIndex].cels[celIndex].interpolation != nil else { return }
        withStructureUndo(name: "Remove Interpolation") {
            layers[layerIndex].cels[celIndex].interpolation = nil
        }
    }

    // MARK: - Registration

    /// One binding covering the whole frame — the default, single automatic motion group. The group
    /// id is fresh per recipe and no `MotionGroup` is registered for it, since inventing one per
    /// recipe would surface document state nobody asked for. Nil when there is nothing to register,
    /// leaving a recipe with no bindings — legal, meaning "warp nothing".
    static func registerWholeFrameGroup(frames: [RegistrationFrame]) -> MotionGroupBinding? {
        guard let first = frames.first, !first.cloud.isEmpty, frames.count >= 2 else { return nil }

        // Lattice built over the first keyframe; later keyframes are fits of it.
        let rest = Lattice(covering: first.cloud,
                           targetCellSize: Self.latticeCellSize(covering: first.cloud), padding: 1)
        var lattices: [Lattice] = [rest]
        for frame in frames.dropFirst() {
            guard !frame.cloud.isEmpty else {
                // Nothing to fit to — "do not move" is the only non-invented answer.
                lattices.append(rest)
                continue
            }
            // Capped here, not inside `fit`: past a couple hundred samples, extra points buy no accuracy.
            let cloud = ARAPRegistration.subsampled(
                frame.cloud, to: ARAPRegistration.Options().maxRegistrationSamples)
            let fit = ARAPRegistration.fit(lattice: rest, source: first.cloud,
                                           target: PointCloudIndex(cloud),
                                           correspondence: first.correspondence(to: frame))
            lattices.append(fit.lattice)
        }
        return MotionGroupBinding(groupID: UUID(), lattices: lattices)
    }

    /// **Reproject** — the target cel's own drawing, registered so its pose can slide along the A→C
    /// motion while its linework is never touched. Differs from `registerWholeFrameGroup` in which
    /// drawing the rest lattice covers: it's drawn over the subject, and every entry in `lattices`,
    /// including the first, is a fit of that grid to a reference — a `t = 0` rest endpoint would
    /// show a reprojected cel unposed and snap the instant the slider moved. Nil when there is
    /// nothing to repose or nothing to repose it along.
    static func registerReprojection(subject: RegistrationFrame,
                                     frames: [RegistrationFrame]) -> MotionGroupBinding? {
        guard !subject.cloud.isEmpty, frames.count >= 2 else { return nil }

        let rest = Lattice(covering: subject.cloud,
                           targetCellSize: latticeCellSize(covering: subject.cloud), padding: 1)
        let ceiling = ARAPRegistration.Options().maxRegistrationSamples
        var lattices: [Lattice] = []
        for frame in frames {
            // Nothing to target — "stay where it was drawn", same rule as the Generate path.
            guard !frame.cloud.isEmpty else { lattices.append(rest); continue }
            let cloud = ARAPRegistration.subsampled(frame.cloud, to: ceiling)
            let fit = ARAPRegistration.fit(lattice: rest, source: subject.cloud,
                                           target: PointCloudIndex(cloud),
                                           correspondence: subject.correspondence(to: frame))
            lattices.append(fit.lattice)
        }
        return MotionGroupBinding(groupID: UUID(), lattices: lattices)
    }

    // MARK: - Registration with motion groups

    /// What registration decided about a drawing's parts: geometry in the recipe (`bindings`),
    /// artist-facing identity in the document registry (`invented`), and membership on the strokes
    /// themselves (`assignments`) — without which the decision would live only inside the recipe,
    /// invisible and uncorrectable.
    struct GroupRegistration {
        /// One per part, in the order the parts came back. A recipe's `groups`.
        var bindings: [MotionGroupBinding]

        /// Groups registration had to create. Empty when the answer was one whole-frame group.
        var invented: [MotionGroup]

        /// Per keyframe, per element, the group it landed in. Empty for the anonymous whole-frame
        /// answer.
        var assignments: [[UUID?]]

        static let none = GroupRegistration(bindings: [], invented: [], assignments: [])
    }

    /// Tag colours for groups registration invents, cycled in order. Unrelated to any stroke's paint
    /// colour — this is metadata, not a live binding of appearance.
    static let motionGroupPalette: [CodableColor] = [
        CodableColor(red: 1.00, green: 0.32, blue: 0.32, alpha: 1),   // red
        CodableColor(red: 0.30, green: 0.68, blue: 1.00, alpha: 1),   // blue
        CodableColor(red: 0.42, green: 0.85, blue: 0.42, alpha: 1),   // green
        CodableColor(red: 1.00, green: 0.75, blue: 0.20, alpha: 1),   // amber
        CodableColor(red: 0.78, green: 0.51, blue: 1.00, alpha: 1),   // violet
        CodableColor(red: 0.20, green: 0.83, blue: 0.80, alpha: 1),   // teal
        CodableColor(red: 1.00, green: 0.55, blue: 0.80, alpha: 1),   // pink
        CodableColor(red: 0.72, green: 0.72, blue: 0.36, alpha: 1),   // olive
    ]

    /// Split the drawing into parts that move together, and fit each part on its own. One algorithm
    /// with two seeds: the artist's tags if any, else one group covering everything, both going
    /// through `MotionGrouping.group`, which refines a seeded partition exactly as it splits an
    /// unseeded one. A drawing that groups into one part takes the default whole-frame path
    /// unchanged. `existing` is the document's group registry, consulted so re-registering after a retag reuses
    /// the artist's own groups instead of minting a parallel set.
    static func registerGroups(frames: [RegistrationFrame],
                               existing: [MotionGroup]) -> GroupRegistration {
        guard let first = frames.first, !first.cloud.isEmpty, frames.count >= 2,
              let last = frames.last, !last.cloud.isEmpty else {
            return wholeFrameRegistration(frames: frames)
        }

        // Measured against the last keyframe: two parts that move differently separate most there.
        let ceiling = ARAPRegistration.Options().maxRegistrationSamples
        let target = PointCloudIndex(ARAPRegistration.subsampled(last.cloud, to: ceiling))
        let parts = MotionGrouping.group(strokes: first.elements.map(\.points), target: target,
                                         seeds: tagSeeds(first.elements))
        guard parts.count > 1 else { return wholeFrameRegistration(frames: frames) }

        // One id per part, reusing whatever the members agree on so a retag survives re-registration.
        var claimed = Set<UUID>()
        var invented: [MotionGroup] = []
        var ids: [UUID] = []
        for part in parts {
            if let reused = dominantTag(of: part.strokes, in: first.elements, excluding: claimed) {
                claimed.insert(reused)
                ids.append(reused)
                continue
            }
            let index = existing.count + invented.count
            let group = MotionGroup(displayName: "Group \(index + 1)",
                                    tagColor: motionGroupPalette[index % motionGroupPalette.count])
            claimed.insert(group.id)
            invented.append(group)
            ids.append(group.id)
        }

        // Frame 0's assignment is the partition itself; later frames are assigned by geometry.
        var assignments: [[UUID?]] = [Array(repeating: nil, count: first.elements.count)]
        for (partIndex, part) in parts.enumerated() {
            for element in part.strokes where assignments[0].indices.contains(element) {
                assignments[0][element] = ids[partIndex]
            }
        }
        for frame in frames.dropFirst() {
            assignments.append(assign(frame, toParts: parts, ids: ids, source: first))
        }

        var bindings: [MotionGroupBinding] = []
        for (partIndex, part) in parts.enumerated() {
            let id = ids[partIndex]
            let source = first.restricted(to: part.strokes)
            guard !source.cloud.isEmpty else { continue }
            let rest = Lattice(covering: source.cloud,
                               targetCellSize: latticeCellSize(covering: source.cloud), padding: 1)
            var lattices: [Lattice] = [rest]
            for (frameIndex, frame) in frames.enumerated().dropFirst() {
                let members = assignments[frameIndex].indices
                    .filter { assignments[frameIndex][$0] == id }
                let slice = frame.restricted(to: Array(members))
                // No counterpart at this keyframe — "do not move", same as the whole-frame path
                // (temporal visibility thresholds, VECTOR_INTERPOLATION.md §4 item 34, not built).
                guard !slice.cloud.isEmpty else { lattices.append(rest); continue }
                let cloud = ARAPRegistration.subsampled(slice.cloud, to: ceiling)
                let fit = ARAPRegistration.fit(lattice: rest, source: source.cloud,
                                               target: PointCloudIndex(cloud),
                                               correspondence: source.correspondence(to: slice))
                lattices.append(fit.lattice)
            }
            bindings.append(MotionGroupBinding(groupID: id, lattices: lattices))
        }

        // A part with no binding must not leave its tag behind, or a stroke references a group the recipe cannot warp.
        let bound = Set(bindings.map(\.groupID))
        for frameIndex in assignments.indices {
            for element in assignments[frameIndex].indices
            where assignments[frameIndex][element].map({ !bound.contains($0) }) == true {
                assignments[frameIndex][element] = nil
            }
        }
        invented.removeAll { !bound.contains($0.id) }

        return GroupRegistration(bindings: bindings, invented: invented, assignments: assignments)
    }

    /// The default answer, in the grouped registration's shape: one anonymous binding and nothing else.
    private static func wholeFrameRegistration(frames: [RegistrationFrame]) -> GroupRegistration {
        guard let binding = registerWholeFrameGroup(frames: frames) else { return .none }
        return GroupRegistration(bindings: [binding], invented: [], assignments: [])
    }

    /// The artist's tagging as a seed partition, or nil when nothing is tagged. Order is
    /// first-appearance. Untagged elements are left out — `MotionGrouping.group` gathers them into
    /// one extra group, so a partial tagging still produces a complete partition.
    private static func tagSeeds(_ elements: [RegistrationElement]) -> [[Int]]? {
        var order: [UUID] = []
        var members: [UUID: [Int]] = [:]
        for (index, element) in elements.enumerated() {
            guard let id = element.groupID else { continue }
            if members[id] == nil { order.append(id) }
            members[id, default: []].append(index)
        }
        return order.isEmpty ? nil : order.map { members[$0] ?? [] }
    }

    /// The tag a part's members already agree on, if any — the most common one not already taken by
    /// an earlier part. Not unanimous, since grouping can move an element between seeded parts.
    /// Excluding already-claimed ids keeps two parts from collapsing onto one group when a seed
    /// splits in two: the larger half keeps the name, the splinter gets a new one.
    private static func dominantTag(of members: [Int], in elements: [RegistrationElement],
                                    excluding claimed: Set<UUID>) -> UUID? {
        var counts: [UUID: Int] = [:]
        var order: [UUID] = []
        for index in members {
            guard elements.indices.contains(index), let id = elements[index].groupID,
                  !claimed.contains(id) else { continue }
            if counts[id] == nil { order.append(id) }
            counts[id, default: 0] += 1
        }
        // Ties broken by first appearance, so the answer does not depend on dictionary order.
        return order.max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
    }

    /// Which part each element of a later keyframe belongs to.
    ///
    /// An element that already carries one of the parts' tags keeps it — the artist's say-so
    /// overrules geometry. Everything else joins whichever part's *moved* source (each part's fitted
    /// similarity applied to its own source points) it sits nearest to — nearest to the moved
    /// source, not the original, or an arm that swung across the body would join the torso's group.
    private static func assign(_ frame: RegistrationFrame, toParts parts: [MotionGrouping.Group],
                               ids: [UUID], source: RegistrationFrame) -> [UUID?] {
        let moved = parts.map { part -> PointCloudIndex in
            PointCloudIndex(part.strokes.flatMap { index -> [CGPoint] in
                guard source.elements.indices.contains(index) else { return [] }
                return source.elements[index].points.map { part.fit.applied(to: $0) }
            })
        }
        let known = Set(ids)
        return frame.elements.map { element -> UUID? in
            if let tagged = element.groupID, known.contains(tagged) { return tagged }
            guard !element.points.isEmpty else { return nil }
            var best: (part: Int, score: CGFloat)?
            for (partIndex, index) in moved.enumerated() where !index.isEmpty {
                var total: CGFloat = 0
                for point in element.points {
                    total += index.nearest(to: point)?.distanceSquared.squareRoot() ?? 0
                }
                let mean = total / CGFloat(element.points.count)
                if best == nil || mean < best!.score { best = (partIndex, mean) }
            }
            return best.map { ids[$0.part] }
        }
    }

    /// One element of one keyframe, as registration sees it. Elements rather than one summed point
    /// cloud, since grouping partitions a keyframe and both the grouping algorithm and the
    /// per-group fit want the frame sliced along the partition.
    struct RegistrationElement {
        /// What this element contributes to the point cloud. See `registrationPoints(of:)`.
        var points: [CGPoint]

        /// Its polyline when it is a stroke, nil for a fill or placed image — a non-stroke poisons
        /// the whole frame's `RegistrationFrame.strokes` for 1:1 correspondence.
        var stroke: [CGPoint]?

        /// The motion group it is tagged with, seeding the grouping. Nil is untagged.
        var groupID: UUID?
    }

    /// One keyframe's geometry, as registration sees it. Three views of the same content: the
    /// fallback fit wants every point regardless of what drew it, 1:1 correspondence wants strokes
    /// kept apart to pair them, and grouping wants the frame sliceable one part at a time.
    struct RegistrationFrame {
        /// The frame's elements in display-list order — also the order tags are written back in.
        var elements: [RegistrationElement]

        /// Every point the display list contributes.
        var cloud: [CGPoint]

        /// The frame's strokes in drawing order, or nil when the frame holds anything that is not a
        /// stroke — any fill or placed image forces the whole frame onto the point-cloud path.
        var strokes: [[CGPoint]]?

        init(elements: [RegistrationElement]) {
            self.elements = elements
            self.cloud = elements.flatMap(\.points)
            var runs: [[CGPoint]]? = []
            for element in elements {
                guard let stroke = element.stroke else { runs = nil; break }
                runs?.append(stroke)
            }
            self.strokes = runs
        }

        /// The sub-frame holding only the elements at `indices`, in their original order. Sliced
        /// rather than re-derived so a part inherits the frame's all-or-nothing stroke rule: a group
        /// made entirely of strokes keeps its correspondence even when a fill elsewhere on the
        /// keyframe made the whole frame's `strokes` nil (the lineart-plus-flats case).
        func restricted(to indices: [Int]) -> RegistrationFrame {
            RegistrationFrame(elements: indices.compactMap {
                elements.indices.contains($0) ? elements[$0] : nil
            })
        }

        /// The 1:1 correspondence between these two frames, or nil when they cannot be paired that
        /// way — different stroke counts (the N:M case, deferred, VECTOR_INTERPOLATION.md §4 item
        /// 33), or either frame holding something that is not a stroke.
        func correspondence(to other: RegistrationFrame) -> ARAPRegistration.StrokeCorrespondence? {
            guard let mine = strokes, let theirs = other.strokes else { return nil }
            let candidate = ARAPRegistration.StrokeCorrespondence(source: mine, target: theirs)
            return candidate.isPairable ? candidate : nil
        }
    }

    /// Roughly ten cells across the longer side, floored so a small drawing doesn't get a grid finer
    /// than its own strokes. Sets registration cost, since ARAP factorises over lattice vertices.
    private static func latticeCellSize(covering points: [CGPoint]) -> CGFloat {
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return 32 }
        return max(max(maxX - minX, maxY - minY) / 10, 8)
    }

    /// What registration sees of one keyframe: one `RegistrationElement` per display-list entry, in
    /// the same order — which is what lets the tags come back out again in that order.
    static func registrationFrame(of elements: [VectorElement]) -> RegistrationFrame {
        RegistrationFrame(elements: elements.map { element in
            switch element {
            case .stroke(let stroke):
                let points = stroke.samples.map(\.point)
                return RegistrationElement(points: points, stroke: points,
                                           groupID: stroke.motionGroupID)
            default:
                // A fill or placed image cannot carry a tag (`motionGroupID` is a `VectorStroke`
                // field only, VECTOR_INTERPOLATION.md §4 item 11), so it rides the first binding.
                return RegistrationElement(points: registrationPoints(of: [element]), stroke: nil,
                                           groupID: nil)
            }
        })
    }

    /// Every point a display list contributes to registration: a stroke's samples, a fill's path
    /// control points, a placed image's centre (all of it that can travel). A stroke's `lattice`
    /// parent walk is skipped — it duplicates the stroke's own path and would overweight a split
    /// piece's parent.
    static func registrationPoints(of elements: [VectorElement]) -> [CGPoint] {
        var points: [CGPoint] = []
        for element in elements {
            switch element {
            case .stroke(let stroke):
                points.append(contentsOf: stroke.samples.map(\.point))
            case .fill(let fill):
                guard let path = fill.cgPath else { continue }
                path.applyWithBlock { element in
                    let type = element.pointee.type
                    let count = type == .addQuadCurveToPoint ? 2 : (type == .addCurveToPoint ? 3 : (type == .closeSubpath ? 0 : 1))
                    for i in 0..<count { points.append(element.pointee.points[i]) }
                }
            case .image(let image):
                points.append(image.transform.position)
            }
        }
        return points
    }

    // MARK: - Evaluating for display

    /// The interpolated frame's pixels, or nil when the cel has no recipe or the recipe is not yet
    /// evaluable. Nil is "not yet", not an error — the caller should fall back to the cel's own
    /// content rather than show a failure. `at` overrides the recipe's stored `t` so a live drag can
    /// render without writing to the document on every tick.
    func interpolatedImage(forCel celID: UUID, inLayer layerID: UUID, at t: CGFloat? = nil,
                           quality: RenderQuality = .full) -> UIImage? {
        guard let canvasSize,
              let at = celIndices(forCel: celID, inLayer: layerID),
              let recipe = layers[at.layer].cels[at.cel].interpolation else { return nil }
        // A reprojection's content is the cel's own display list, which no `ContentProvider` can
        // reach — the recipe holds no reference to the cel it lives on, by design.
        let subject = recipe.mode == .reproject ? (layers[at.layer].cels[at.cel].vector?.elements ?? []) : []
        return InterpolationEvaluator.render(recipe: recipe, at: t ?? recipe.t, size: canvasSize,
                                             content: interpolationContentProvider, subject: subject,
                                             guides: guides(driving: recipe),
                                             quality: quality, options: interpolationOptions)
    }

    // MARK: - Guides

    /// The guides `recipe` references, deduplicated and in a stable order.
    ///
    /// **One resolver, used by both the evaluation and the preview key**, deliberately. Guides live
    /// here, not on any `VectorCanvas`, and `updateGuideStroke` replaces one **keeping its id**, so
    /// no cache key can see a guide edit by version alone — having the key and the evaluator read
    /// the same list is what keeps them in sync.
    func guides(driving recipe: InterpolationRecipe) -> [GuideStroke] {
        var wanted = recipe.guideIDs
        for binding in recipe.groups { wanted.append(contentsOf: binding.guideIDs) }
        guard !wanted.isEmpty else { return [] }
        var seen: Set<UUID> = []
        return wanted.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return guideStrokes.first { $0.id == id }
        }
    }

    /// Records a guide the artist just drew and binds it to the frame under the playhead.
    ///
    /// **Whole-frame by default** — `boundGroups` empty, and the id goes on the recipe rather than
    /// on a binding: the artist drew one arc over the whole drawing, and narrowing it to a group is
    /// a later, deliberate act. The interval is the recipe's own span, first reference to last,
    /// which scopes the guide library (`GuideStroke.interval`) without binding the guide to this
    /// recipe — the binding runs the other way, from `guideIDs`, making reuse a reference rather
    /// than a copy.
    ///
    /// Returns the refusal reason, or nil on success.
    @discardableResult
    func recordGuideStroke(samples: [TimedSample]) -> InterpolationRefusal? {
        guard samples.count >= 2 else { return .noInterpolationToGuide }
        guard let at = interpolationTarget,
              let recipe = layers[at.layer].cels[at.cel].interpolation,
              let first = recipe.references.first?.cels.first,
              let last = recipe.references.last?.cels.last
        else { return .noInterpolationToGuide }

        let guide = GuideStroke(samples: samples,
                                interval: KeyframeInterval(start: first, end: last),
                                boundGroups: [], role: .both)
        // One step covering both halves — an undo leaving the guide registered but unbound to
        // anything would be a leak the artist cannot see.
        withInterpolationUndo(name: "Add Guide") {
            guideStrokes.append(guide)
            layers[at.layer].cels[at.cel].interpolation?.guideIDs.append(guide.id)
        }
        return nil
    }

    /// Why `recordGuideStroke` would refuse, without drawing anything — what greys the bar's toggle
    /// out. Cheap enough for a SwiftUI `body`, unlike `commitRefusal`.
    var guideRefusal: InterpolationRefusal? {
        guard let at = interpolationTarget else { return .noInterpolationToGuide }
        return layers[at.layer].cels[at.cel].interpolation == nil ? .noInterpolationToGuide : nil
    }

    /// The guides to *draw* right now: those bound to the frame under the playhead. Deliberately the
    /// recipe's own list, not every guide in the document — showing all of them would bury the arc
    /// the artist is working on under every arc they have ever drawn.
    var visibleGuideStrokes: [GuideStroke] {
        guard isInterpolateMode, let at = interpolationTarget,
              let recipe = layers[at.layer].cels[at.cel].interpolation else { return [] }
        return guides(driving: recipe)
    }

    @discardableResult
    func addGuideStroke(_ guide: GuideStroke) -> GuideStroke {
        withInterpolationUndo(name: "Add Guide") {
            guideStrokes.append(guide)
        }
        return guide
    }

    /// Replaces a guide in place, keeping its id — what makes an edit propagate to every interval
    /// referencing it ("link", as opposed to "duplicate").
    func updateGuideStroke(_ guide: GuideStroke) {
        guard let index = guideStrokes.firstIndex(where: { $0.id == guide.id }) else { return }
        withInterpolationUndo(name: "Edit Guide") {
            guideStrokes[index] = guide
        }
    }

    // MARK: - Guide handles

    /// The positions to draw `guide`'s editable handles at, and the sample each one edits.
    ///
    /// A thin pass-through to `GuideHandles`, kept here so the view layer never has to know how a
    /// handle is placed — it receives positions and reports back the index it was given.
    func guideHandlePositions(for guide: GuideStroke) -> [(sampleIndex: Int, position: CGPoint)] {
        GuideHandles.indices(in: guide.samples).map { ($0, guide.samples[$0].point) }
    }

    /// A handle drag's touch-down. Uses `beginStructureGesture`, the same bracket the `t` slider
    /// uses — sufficient here, unlike the retag case, because `StructureSnapshot` carries
    /// `guideStrokes` outright: a guide is a document-level value, not stroke content behind a class
    /// reference. `updateGuideStroke`'s own bracket defers to this gesture rather than recording per
    /// move.
    func beginGuideHandleDrag(guideID: UUID) {
        guard let guide = guideStrokes.first(where: { $0.id == guideID }) else { return }
        guideHandleDrag = (guideID, guide.samples)
        beginStructureGesture()
    }

    /// Moves the handle mid-drag. Records nothing — the bracket owns the step.
    ///
    /// Re-derived from the touch-down geometry every time, which is what makes the result depend on
    /// where the finger *is* rather than on how it got there.
    func dragGuideHandle(sampleIndex: Int, to destination: CGPoint) {
        guard let drag = guideHandleDrag,
              var guide = guideStrokes.first(where: { $0.id == drag.guideID }) else { return }
        guide.samples = GuideHandles.dragged(drag.samples, index: sampleIndex, to: destination)
        updateGuideStroke(guide)
    }

    /// The lift. Records the step, or drops it when the handle came back to where it started — a tap
    /// is not an edit, and identical-geometry undo steps just make undo tedious.
    func commitGuideHandleDrag() {
        guard let drag = guideHandleDrag else { return }
        guideHandleDrag = nil
        let moved = guideStrokes.first { $0.id == drag.guideID }?.samples != drag.samples
        if moved { commitStructureGesture(name: "Edit Guide") } else { cancelStructureGesture() }
    }

    /// A second finger landing mid-drag. Puts the guide back exactly as it was and records nothing —
    /// a snapshot left in place would be handed to whichever gesture committed next.
    func cancelGuideHandleDrag() {
        guard let drag = guideHandleDrag else { return }
        guideHandleDrag = nil
        if let index = guideStrokes.firstIndex(where: { $0.id == drag.guideID }) {
            guideStrokes[index].samples = drag.samples
        }
        cancelStructureGesture()
    }

    // MARK: - The guide list, link and duplicate

    /// One guide on the bar's list.
    struct GuideChip: Identifiable {
        var guide: GuideStroke
        /// 1-based, in the order the recipe names them — a guide has no name of its own.
        var number: Int
        /// True when some *other* interval references this same guide: editing a shared guide's
        /// handles moves the motion on every frame that uses it, a nasty surprise if you thought you
        /// had a copy, so it's worth flagging.
        var isShared: Bool
        var id: UUID { guide.id }
    }

    /// The guides bound to the frame under the playhead, as the bar shows them.
    var guideChips: [GuideChip] {
        let visible = visibleGuideStrokes
        guard !visible.isEmpty else { return [] }
        var uses: [UUID: Int] = [:]
        for layer in layers {
            for cel in layer.cels {
                guard let recipe = cel.interpolation else { continue }
                for id in Set(recipe.guideIDs + recipe.groups.flatMap(\.guideIDs)) {
                    uses[id, default: 0] += 1
                }
            }
        }
        return visible.enumerated().map { index, guide in
            GuideChip(guide: guide, number: index + 1, isShared: (uses[guide.id] ?? 0) > 1)
        }
    }

    /// Guides elsewhere in the document that this frame does not already use — the reuse library.
    /// Every guide in the registry, not only those whose `KeyframeInterval` matches — fetching the
    /// arc from *another* frame is the whole point.
    var linkableGuideStrokes: [GuideStroke] {
        guard let at = interpolationTarget,
              let recipe = layers[at.layer].cels[at.cel].interpolation else { return [] }
        let alreadyHere = Set(recipe.guideIDs + recipe.groups.flatMap(\.guideIDs))
        return guideStrokes.filter { !alreadyHere.contains($0.id) }
    }

    /// **Link**: the same guide drives this interval too. A recipe names guides by **id**, so
    /// editing it anywhere moves the motion everywhere — fix the arc once and every frame of a
    /// repeating cycle follows.
    @discardableResult
    func linkGuideStroke(id: UUID) -> InterpolationRefusal? {
        guard let at = interpolationTarget,
              let recipe = layers[at.layer].cels[at.cel].interpolation,
              guideStrokes.contains(where: { $0.id == id }) else { return .noInterpolationToGuide }
        guard !recipe.guideIDs.contains(id),
              !recipe.groups.contains(where: { $0.guideIDs.contains(id) }) else { return nil }
        withInterpolationUndo(name: "Link Guide") {
            layers[at.layer].cels[at.cel].interpolation?.guideIDs.append(id)
        }
        return nil
    }

    /// **Duplicate**: an independent copy of the same arc, for a one-off.
    ///
    /// Deliberately *not* copied, the same judgement `recordGuideStroke` makes: a fresh `id` (the
    /// whole difference from a link); this interval, not the source's; and whole-frame, not the
    /// source's `boundGroups` (carried across, it would silently make the copy drive nothing
    /// whenever that group isn't part of *this* recipe). `role` *is* carried — it's a property of
    /// the drawing, not of where it's used.
    @discardableResult
    func duplicateGuideStroke(id: UUID) -> InterpolationRefusal? {
        guard let source = guideStrokes.first(where: { $0.id == id }),
              let at = interpolationTarget,
              let recipe = layers[at.layer].cels[at.cel].interpolation,
              let first = recipe.references.first?.cels.first,
              let last = recipe.references.last?.cels.last else { return .noInterpolationToGuide }

        let copy = GuideStroke(samples: source.samples,
                               interval: KeyframeInterval(start: first, end: last),
                               boundGroups: [], role: source.role)
        withInterpolationUndo(name: "Duplicate Guide") {
            guideStrokes.append(copy)
            layers[at.layer].cels[at.cel].interpolation?.guideIDs.append(copy.id)
        }
        return nil
    }

    // MARK: - The spacing chart

    /// Frames from the first keyframe to the last, inclusive — the chart's stop count. Read off the
    /// **timeline**, not the recipe. Nil when the span cannot be resolved or the keyframes are
    /// adjacent.
    func interpolationFrameSpan(of recipe: InterpolationRecipe) -> Int? {
        guard let first = recipe.references.first?.cels.first,
              let last = recipe.references.last?.cels.last,
              let a = celIndices(forCel: first.celID, inLayer: first.layerID),
              let b = celIndices(forCel: last.celID, inLayer: last.layerID) else { return nil }
        let start = layers[a.layer].cels[a.cel].startFrame
        let end = layers[b.layer].cels[b.cel].startFrame
        guard end > start else { return nil }
        return end - start + 1
    }

    /// True when this guide's timing is what `binding` reads — the two ways the model can say so.
    /// Must stay in sync with the pairing `GuideSet` performs: this decides where a dot drag
    /// *writes*, `GuideSet` decides where the result is *read*. If they disagreed, the chart would
    /// move and the frame would not.
    private func binding(_ binding: MotionGroupBinding, isDrivenBy guide: GuideStroke,
                         in recipe: InterpolationRecipe) -> Bool {
        binding.guideIDs.contains(guide.id)
            || (recipe.guideIDs.contains(guide.id) && guide.drives(binding.groupID))
    }

    /// The easing actually in force for `guide`'s groups, mirroring the evaluator's precedence —
    /// `binding.spacing ?? the guide's derived timing ?? recipe.spacing`. Mirrored rather than
    /// shared because the evaluator resolves per binding and this question is per *guide* — the
    /// chart is drawn on one guide and has to show one curve. Where several bound groups disagree,
    /// the first is shown, and a drag then writes all of them.
    private func spacingInForce(for guide: GuideStroke, in recipe: InterpolationRecipe) -> SpacingCurve {
        if let driven = recipe.groups.first(where: { binding($0, isDrivenBy: guide, in: recipe) }),
           let explicit = driven.spacing {
            return explicit
        }
        if guide.role != .trajectory, let derived = GuidePath(samples: guide.samples)?.spacingCurve() {
            return derived
        }
        return recipe.spacing
    }

    /// The chart to draw on `guideID`, or nil when there is nothing to space.
    func spacingChart(forGuide guideID: UUID) -> SpacingChart? {
        guard let at = interpolationTarget,
              let recipe = layers[at.layer].cels[at.cel].interpolation,
              let guide = guideStrokes.first(where: { $0.id == guideID }),
              let frames = interpolationFrameSpan(of: recipe), frames >= 3 else { return nil }
        return SpacingChart(curve: spacingInForce(for: guide, in: recipe), frames: frames)
    }

    /// Writes a chart back as the easing for every group `guide` drives.
    ///
    /// `binding.spacing` outranks the guide's derived stylus timing, so a dot the artist has placed
    /// by hand is not overwritten by the velocity they happened to draw the arc at. A recipe with no
    /// bindings takes it on `recipe.spacing` instead, the same rule one level up.
    func setSpacing(_ curve: SpacingCurve, forGuide guideID: UUID) {
        guard let at = interpolationTarget,
              var recipe = layers[at.layer].cels[at.cel].interpolation,
              let guide = guideStrokes.first(where: { $0.id == guideID }) else { return }
        var wroteABinding = false
        for index in recipe.groups.indices where binding(recipe.groups[index], isDrivenBy: guide, in: recipe) {
            recipe.groups[index].spacing = curve
            wroteABinding = true
        }
        if !wroteABinding { recipe.spacing = curve }
        withInterpolationUndo(name: "Adjust Spacing") {
            layers[at.layer].cels[at.cel].interpolation = recipe
        }
    }

    /// A chart dot's touch-down. Same bracket and the same touch-down snapshot as a handle drag, for
    /// the same two reasons: one undo step per gesture, and a drag that is a pure function of where
    /// the finger *is* rather than of the curve it has been writing as it went.
    func beginGuideSpacingDrag(guideID: UUID) {
        guard let chart = spacingChart(forGuide: guideID),
              let at = interpolationTarget,
              let recipe = layers[at.layer].cels[at.cel].interpolation else { return }
        guideSpacingDrag = (guideID, chart, recipe)
        beginStructureGesture()
    }

    /// Moves one frame's dot to `fraction` along the guide. Records nothing — the bracket owns it.
    func dragGuideSpacingStop(index: Int, to fraction: CGFloat) {
        guard let drag = guideSpacingDrag else { return }
        setSpacing(drag.chart.moving(index, to: fraction).curve, forGuide: drag.guideID)
    }

    func commitGuideSpacingDrag() {
        guard let drag = guideSpacingDrag, let at = interpolationTarget else { return }
        guideSpacingDrag = nil
        let moved = layers[at.layer].cels[at.cel].interpolation.map { current in
            current.spacing != drag.recipe.spacing
                || current.groups.map(\.spacing) != drag.recipe.groups.map(\.spacing)
        } ?? false
        if moved { commitStructureGesture(name: "Adjust Spacing") } else { cancelStructureGesture() }
    }

    func cancelGuideSpacingDrag() {
        guard let drag = guideSpacingDrag else { return }
        guideSpacingDrag = nil
        if let at = interpolationTarget {
            layers[at.layer].cels[at.cel].interpolation = drag.recipe
        }
        cancelStructureGesture()
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
