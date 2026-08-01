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

        // Bracketed with `defer` for the same reason `withStructureUndo` does it: `body` is where a
        // future caller will put something that can exit early, and a depth that never comes back
        // down silently disables undo for everything after it.
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
        // Counted before anything is locked, because this runs on **every** frame tick (see the call
        // site in `handleActiveContextChanged`) and `hasCachedImage` takes each canvas's lock — which
        // a background `render()` holds for its entire rasterization, tens of milliseconds. Reading
        // `cel.vector` is a struct field access and locks nothing, so a document with fewer vector
        // cels than the limit — which is every raster project, and most others — cannot have
        // anything to evict and gets out without touching a lock at all.
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

    // MARK: - Interpolate mode

    /// Enters interpolate mode with a clean reference selection.
    func enterInterpolateMode() {
        interpolationReferences.removeAll()
        isInterpolateMode = true
    }

    /// Leaves the mode and drops the reference selection.
    ///
    /// Recipes already attached to cels are untouched: the selection is a transient, the recipe is
    /// document content. Leaving and re-entering the mode therefore keeps every in-between working
    /// and only asks the artist to re-pick references if they want to build a *new* one.
    func exitInterpolateMode() {
        isInterpolateMode = false
        interpolationReferences.removeAll()
    }

    func isInterpolationReference(celID: UUID, inLayer layerID: UUID) -> Bool {
        interpolationReferences.contains(CelRef(layerID: layerID, celID: celID))
    }

    /// Flags or unflags a cel as a keyframe — `InterpolateBar`'s Set as Reference.
    ///
    /// Not undoable, deliberately: this is a selection, like which layer is current, and filling the
    /// undo stack with selection steps is what makes undo useless. The recipe that *results* from a
    /// selection is undoable, in one step (`interpolate(...)`).
    func toggleInterpolationReference(celID: UUID, inLayer layerID: UUID) {
        let ref = CelRef(layerID: layerID, celID: celID)
        if let existing = interpolationReferences.firstIndex(of: ref) {
            interpolationReferences.remove(at: existing)
        } else {
            interpolationReferences.append(ref)
        }
    }

    /// The flagged cels grouped into keyframes, in time order.
    ///
    /// Cels that start on the same frame are one keyframe, which is what makes requirement 5 work
    /// without a second gesture: flagging a lineart cel and the flats cel underneath it produces one
    /// reference holding both, so they warp through one lattice instead of drifting apart.
    ///
    /// Grouping is by `startFrame` rather than by overlap. Overlap would fold a long held cel in with
    /// every short cel beside it, which is the wrong answer far more often than two same-length cels
    /// starting a frame apart is.
    var interpolationKeyframes: [InterpolationReference] {
        var byFrame: [Int: [CelRef]] = [:]
        for ref in interpolationReferences {
            guard let at = celIndices(forCel: ref.celID, inLayer: ref.layerID) else { continue }
            byFrame[layers[at.layer].cels[at.cel].startFrame, default: []].append(ref)
        }
        return byFrame.keys.sorted().map { InterpolationReference(cels: byFrame[$0] ?? []) }
    }

    /// Resolves a `CelRef` to the display list that cel holds — the evaluator's `ContentProvider`.
    ///
    /// The evaluator takes this as a closure rather than reaching for `CanvasManager` itself, which
    /// is what lets every render test run without a document (`HANDOFF.md` §5.9). This is the one
    /// place the two are joined.
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
        /// Reproject is not built yet — see `IMPLEMENTATION.md` Phase 6 item 1.
        case reprojectNotImplemented

        var message: String {
            switch self {
            case .notEnoughReferences: return "Set at least two reference frames first."
            case .targetIsAReference: return "This frame is a reference. Pick a different frame."
            case .notAVectorLayer: return "Interpolation works on vector layers."
            case .referencesAreEmpty: return "The reference frames have nothing to interpolate."
            case .alreadyInterpolated: return "This frame is already interpolated."
            case .reprojectNotImplemented: return "Reproject isn't available yet."
            }
        }
    }

    /// Whether `interpolate` would succeed for this cel, and why not if it would not.
    func interpolationRefusal(mode: InterpolationMode, layerIndex: Int, celIndex: Int) -> InterpolationRefusal? {
        if mode == .reproject { return .reprojectNotImplemented }
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex),
              layers[layerIndex].cels[celIndex].vector != nil else { return .notAVectorLayer }
        // Generating on a cel that already derives from a recipe is never what was meant: the second
        // Generate silently replaces the first, so a double tap looks like it interpolated twice and
        // an artist who has scrubbed to a `t` they like loses it. Retiming is the slider's job, and
        // starting over is Remove Interpolation's. Deliberately *not* extended to Reproject, whose
        // whole subject is a cel that already has content — when it is built it will need its own
        // answer to this question rather than inheriting Generate's.
        if layers[layerIndex].cels[celIndex].interpolation != nil { return .alreadyInterpolated }
        let target = CelRef(layerID: layers[layerIndex].id, celID: layers[layerIndex].cels[celIndex].id)
        return referenceRefusal(excludingTarget: target)
    }

    /// The part of the refusal that is about the *references* rather than the target, so the
    /// playhead check can reuse it for a cel that does not exist yet.
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
    /// Nil when the playhead sits over an empty slot — which Generate treats as "make one", not as
    /// "refuse" (see `interpolateAtPlayhead`).
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
        if mode == .reproject { return .reprojectNotImplemented }
        // An empty slot between two references is the ordinary way to ask for an in-between, so the
        // missing block is not a refusal — Generate makes it. Every target-side check is answered by
        // construction for a cel that does not exist: it is empty, it carries no recipe, and nothing
        // can have flagged it as a reference. What is left is the layer's kind and the references.
        guard layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].kind == .vector else { return .notAVectorLayer }
        return referenceRefusal(excludingTarget: nil)
    }

    /// **Generate** — attach a recipe deriving this cel from the flagged keyframes (`PLAN.md` §5.5).
    ///
    /// Note what this does *not* do: it does not write a display list into the cel. An in-between is
    /// derived, never stored (`PLAN.md` §4) — the recipe is the frame, and moving the slider is a
    /// parameter change rather than a regeneration. Baking is a separate, later, explicitly one-way
    /// **Commit** action.
    ///
    /// Registration happens here because this is the first moment both keyframes are known. It is
    /// the expensive step — an ARAP fit per reference past the first — and it is synchronous, so the
    /// caller sees `isRegisteringInterpolation` go true and back.
    ///
    /// Returns the refusal reason, or nil on success.
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
        let binding = Self.registerWholeFrameGroup(frames: frames)

        let recipe = InterpolationRecipe(references: keyframes, t: 0.5, mode: mode,
                                         groups: binding.map { [$0] } ?? [])
        // A structure bracket, not `withInterpolationUndo`: attaching a recipe writes a value type
        // inside `Cel` and touches no stroke content, which is exactly the case `withStructureUndo`
        // covers. The stroke-content bracket is what a future Commit will need (§5).
        withStructureUndo(name: "Interpolate") {
            layers[layerIndex].cels[celIndex].interpolation = recipe
        }
        return nil
    }

    /// **Generate/Reproject as the bar presses them** — act on the playhead, creating the block if
    /// there is not one there yet.
    ///
    /// Product owner, 2026-08-01: standing on an empty slot between two references and pressing
    /// Generate should just work. The alternative — add the block from the slot's own menu, then
    /// press Generate — is two steps for one intent, and the first of them is easy to not know about.
    ///
    /// The block and the recipe land as **one** undo step because they are one action. Both `addCel`
    /// and `interpolate` open `withStructureUndo`, and both defer to an enclosing bracket rather than
    /// recording their own, so the outer bracket here is all it takes.
    @discardableResult
    func interpolateAtPlayhead(mode: InterpolationMode) -> InterpolationRefusal? {
        if let refusal = interpolationRefusalAtPlayhead(mode: mode) { return refusal }
        let layerIndex = currentLayerIndex
        if let at = interpolationTarget {
            return interpolate(mode: mode, layerIndex: at.layer, celIndex: at.cel)
        }
        let frame = currentFrame
        var result: InterpolationRefusal? = nil
        withStructureUndo(name: "Interpolate") {
            guard addCel(layerIndex: layerIndex, startFrame: frame, frameCount: 1),
                  let celIndex = activeCelIndex(inLayer: layerIndex, atFrame: frame) else {
                result = .notAVectorLayer
                return
            }
            result = interpolate(mode: mode, layerIndex: layerIndex, celIndex: celIndex)
        }
        return result
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

    /// One binding covering the whole frame — Phase 4's single automatic motion group.
    ///
    /// The group id is fresh per recipe and **no** `MotionGroup` is registered for it. A registered
    /// group is an artist-facing object (it has a name, a tag colour, a mode badge — Phase 5), and
    /// inventing one per recipe would put document state in front of the artist that they never
    /// asked for. The binding is all the evaluator needs: untagged content rides the recipe's first
    /// binding (`HANDOFF.md` §5.9), and in Phase 4 every stroke is untagged.
    ///
    /// Nil when there is nothing to register, which leaves a recipe with no bindings — legal, and
    /// meaning "warp nothing", which is the honest answer to two empty keyframes (`PLAN.md` §10
    /// decision 2).
    static func registerWholeFrameGroup(frames: [RegistrationFrame]) -> MotionGroupBinding? {
        guard let first = frames.first, !first.cloud.isEmpty, frames.count >= 2 else { return nil }

        // The lattice is built over the bounding region at the *first* keyframe (`PLAN.md` §5.2) and
        // every later keyframe is a fit of it. Cell size is set from the content's own extent rather
        // than fixed, so a thumbnail-sized doodle and a full-canvas drawing get comparable
        // resolution; the floor keeps a tiny drawing from producing a needlessly huge grid.
        let rest = Lattice(covering: first.cloud,
                           targetCellSize: Self.latticeCellSize(covering: first.cloud), padding: 1)
        var lattices: [Lattice] = [rest]
        for frame in frames.dropFirst() {
            guard !frame.cloud.isEmpty else {
                // A keyframe with no content has nothing to fit to, and "do not move" is the only
                // answer that is not invented. Its set fades in or out on weight alone.
                lattices.append(rest)
                continue
            }
            // The target cloud is capped here rather than inside `fit`, which only ever sees the
            // index and not the points that went into it. Same reasoning and same ceiling as
            // `ARAPRegistration.Options.maxRegistrationSamples`: past a couple of hundred samples
            // the extra points buy no accuracy and cost a nearest query each, per iteration.
            let cloud = ARAPRegistration.subsampled(
                frame.cloud, to: ARAPRegistration.Options().maxRegistrationSamples)
            let fit = ARAPRegistration.fit(lattice: rest, source: first.cloud,
                                           target: PointCloudIndex(cloud),
                                           correspondence: first.correspondence(to: frame))
            lattices.append(fit.lattice)
        }
        return MotionGroupBinding(groupID: UUID(), lattices: lattices)
    }

    /// One keyframe's geometry, as registration sees it.
    ///
    /// Two views of the same content, because the two tiers want different things: tier 1 and the
    /// fallback fit want every point whatever drew it, and tier 0's 1:1 correspondence wants the
    /// strokes kept apart so it can pair them (`HANDOFF.md` §8 item 31).
    struct RegistrationFrame {
        /// Every point a display list contributes. Never nil — this is what registration always had.
        var cloud: [CGPoint]

        /// The frame's strokes in drawing order, or **nil** when the frame holds anything that is
        /// not a stroke.
        ///
        /// Nil rather than "the strokes among other things" on purpose. Dropping the point-cloud
        /// data rows is what makes the correspondence work at all (see `ARAPRegistration.fit`), and
        /// with them dropped a fill or a placed image would be left with nothing pulling it —
        /// carried along by lattice rigidity alone. Its contour is also a closed loop, which needs a
        /// phase offset rather than a direction bit, and that is not in scope. So a frame with a
        /// fill in it takes the point-cloud path it always took.
        var strokes: [[CGPoint]]?

        /// The 1:1 correspondence between these two frames, or nil when they cannot be paired that
        /// way — different stroke counts (the N:M case, `HANDOFF.md` §8 item 33, still deferred), or
        /// either frame holding something that is not a stroke.
        func correspondence(to other: RegistrationFrame) -> ARAPRegistration.StrokeCorrespondence? {
            guard let mine = strokes, let theirs = other.strokes else { return nil }
            let candidate = ARAPRegistration.StrokeCorrespondence(source: mine, target: theirs)
            return candidate.isPairable ? candidate : nil
        }
    }

    /// Roughly ten cells across the longer side, floored so a small drawing does not get a grid finer
    /// than its own strokes. The ARAP factorisation is over lattice vertices, so this is the dial that
    /// sets registration cost — see `PLAN.md` §8.
    private static func latticeCellSize(covering points: [CGPoint]) -> CGFloat {
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return 32 }
        return max(max(maxX - minX, maxY - minY) / 10, 8)
    }

    /// What registration sees of one keyframe: the cloud always, and the strokes when *everything*
    /// in the frame is a stroke. See `RegistrationFrame.strokes` for why it is all or nothing.
    static func registrationFrame(of elements: [VectorElement]) -> RegistrationFrame {
        var strokes: [[CGPoint]]? = []
        for element in elements {
            guard case .stroke(let stroke) = element else { strokes = nil; break }
            strokes?.append(stroke.samples.map(\.point))
        }
        return RegistrationFrame(cloud: registrationPoints(of: elements), strokes: strokes)
    }

    /// Every point a display list contributes to registration.
    ///
    /// Strokes contribute their samples; a fill contributes its path's control points; a placed image
    /// contributes its centre, which is all of it that can travel (`InterpolationEvaluator`'s note on
    /// warping one). A stroke's `lattice` parent walk is deliberately skipped — it duplicates the
    /// stroke's own path and would weight a split piece's parent more heavily than the drawing.
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
    /// evaluable.
    ///
    /// Nil is "not yet", not an error (`HANDOFF.md` §5.9): a recipe can be broken by editing around
    /// it, and the caller should fall back to the cel's own content rather than show a failure.
    ///
    /// `at` overrides the recipe's stored `t` so a live drag can render without writing to the
    /// document on every tick.
    func interpolatedImage(forCel celID: UUID, inLayer layerID: UUID, at t: CGFloat? = nil,
                           quality: RenderQuality = .full) -> UIImage? {
        guard let canvasSize,
              let at = celIndices(forCel: celID, inLayer: layerID),
              let recipe = layers[at.layer].cels[at.cel].interpolation else { return nil }
        return InterpolationEvaluator.render(recipe: recipe, at: t ?? recipe.t, size: canvasSize,
                                             content: interpolationContentProvider,
                                             quality: quality, options: interpolationOptions)
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
