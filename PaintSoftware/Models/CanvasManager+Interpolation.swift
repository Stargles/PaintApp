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

    /// Assigns (or with a nil `groupID`, clears) the motion-group tag on the named strokes, wherever
    /// in the document they live. One step, spanning as many layers and cels as the selection does —
    /// which is the point of groups being document-level.
    ///
    /// **Re-registers every recipe that reads a touched cel, in the same step.** A tag is only half
    /// of what a motion group is: the other half is the fitted lattice in the recipe, and that was
    /// computed from the *old* partition. Retagging without re-registering would change the
    /// colour-coding and leave the motion exactly as it was, which reads as the tag having done
    /// nothing. Phase 5's definition of done is "the artist can retag and see the result
    /// immediately", and this is the line that makes "immediately" true.
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
    /// guides and local edits and replacing only its group bindings.
    ///
    /// Reads each recipe's **own** `references` rather than the transient reference selection, so it
    /// is correct for a recipe built in an earlier session and works with interpolate mode off.
    ///
    /// Records no undo step of its own — it is always part of a larger artist action (a retag, a
    /// colour bake), and the caller owns the bracket. It must be one that is `touching:`
    /// `canvasesReached(byRetagging:)`, because re-registration writes tags onto *every* keyframe of
    /// every recipe it re-runs, not only the cel the artist touched.
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

    // MARK: - Tag by stroke colour

    /// **Tag by stroke colour** — `PLAN.md` §5.1.1's one-shot populate.
    ///
    /// Clusters the strokes of `cels` by paint colour and writes one motion group per cluster into
    /// `motionGroupID`, then re-registers so the new partition is what actually moves.
    ///
    /// A *populate*, never a live binding, and that distinction is the whole design. After it runs
    /// the tags are ordinary tags: the artist can merge, split or reassign them, and recolouring a
    /// stroke afterwards does **not** silently move it to a different motion group. A live binding
    /// would be simpler to implement and much worse to use — it would make every colour change a
    /// hidden motion change.
    ///
    /// It exists because assigning tags by hand is tedious for art that already encodes structure in
    /// its colours, which is exactly the mitigation the product owner named for the attached-limb
    /// limitation (`HANDOFF.md` §8 item 1): distinguish the limbs by colour in both reference frames
    /// and the grouping stops having to guess.
    ///
    /// **Erasers are skipped.** An eraser's colour is not a colour — it says nothing about which part
    /// it belongs to — so clustering on it would invent a group made of every eraser on the drawing.
    /// Left untagged they ride the recipe's first binding, which is the same thing they did before
    /// this action existed. Making an eraser inherit the group of the ink it overlaps is the right
    /// answer and is recorded rather than built.
    ///
    /// Returns the groups it created, in cluster order.
    @discardableResult
    func tagMotionGroupsByStrokeColour(in cels: [CelRef],
                                       tolerance: CGFloat = 0.08) -> [MotionGroup] {
        let resolved: [(ref: CelRef, canvas: VectorCanvas)] = cels.compactMap { ref in
            celIndices(forCel: ref.celID, inLayer: ref.layerID)
                .flatMap { layers[$0.layer].cels[$0.cel].vector }
                .map { (ref, $0) }
        }
        guard !resolved.isEmpty else { return [] }

        // One pass over every stroke on every named cel, in document order, so the clusters — and
        // therefore the group names — come out the same on every run.
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
        // One colour is not a grouping — it is the whole-frame group the drawing already had, and
        // minting a single group for it would put an artist-facing object on screen that says
        // nothing. Refusing here rather than in the UI keeps the rule in one place.
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

    /// How far apart two paint colours are, as the largest single-channel difference.
    ///
    /// Max-channel rather than Euclidean so the tolerance means one plain thing — "no channel differs
    /// by more than this" — and so a colour cannot drift into a cluster by accumulating small
    /// differences across three channels. Alpha is included: a stroke at half opacity is a different
    /// paint choice from the same hue at full, and on flats it usually means a different pass.
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
        let registration = Self.registerGroups(frames: frames, existing: motionGroups)

        let recipe = InterpolationRecipe(references: keyframes, t: 0.5, mode: mode,
                                         groups: registration.bindings)
        // `withInterpolationUndo`, not `withStructureUndo`, and Phase 5 is what changed that.
        // Attaching a recipe writes a value type inside `Cel` and the structure bracket covers it —
        // but registration now also writes each stroke's motion-group tag back onto the *keyframes*,
        // and a tag is a field on `VectorStroke`, which `StructureSnapshot` shares rather than
        // copies. Undoing a Generate under the old bracket would put the recipe back and leave the
        // tags on. This is exactly the trap §5's Phase 2 entry describes.
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

    /// Writes registration's grouping decision back onto the keyframes' own strokes.
    ///
    /// This is the step that makes the grouping *visible and editable*. Without it the partition
    /// would live only inside the recipe's bindings, where the artist can neither see which stroke
    /// went where nor move one — and Phase 5's definition of done is precisely that they can. It is
    /// also what the evaluator reads: `warped` resolves a stroke's `motionGroupID` against the
    /// bindings, so an untagged stroke rides the *first* binding whatever the grouping decided.
    ///
    /// Only strokes can carry a tag. A fill or a placed image takes part in the partition — its
    /// points are in the cloud, so it lands in a part and that part's lattice is fitted with it in —
    /// but it has nowhere to record which, so at render time it falls back to the first binding
    /// (`HANDOFF.md` §8 item 11).
    ///
    /// Call inside an undo bracket that is `touching:` these canvases.
    func applyMotionGroupTags(_ assignments: [[UUID?]], to keyframes: [InterpolationReference]) {
        for (frameIndex, reference) in keyframes.enumerated() where frameIndex < assignments.count {
            let tags = assignments[frameIndex]
            // The assignments are in the order `registrationFrame(of:)` saw the elements, which is
            // `cels.flatMap(provider)` — so walking the cels in the same order and carrying a cursor
            // is what lines them back up. Anything that changes one order must change the other.
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
                    // The setters deliberately do not invalidate — see `VectorCanvas`'s accessor
                    // contract — so a wholesale assignment has to bump the version itself. It is
                    // also what re-keys the preview memo (`InterpolationPreviewKey`), which is how
                    // a retag shows up on screen without an explicit invalidation call.
                    canvas.bumpVersion()
                }
            }
        }
    }

    /// **Generate/Reproject as the bar presses them** — act on the playhead, creating the block if
    /// there is not one there yet.
    ///
    /// Product owner, 2026-08-01: standing on an empty slot between two references and pressing
    /// Generate should just work. The alternative — add the block from the slot's own menu, then
    /// press Generate — is two steps for one intent, and the first of them is easy to not know about.
    ///
    /// The block and the recipe land as **one** undo step because they are one action. `addCel` opens
    /// `withStructureUndo` and `interpolate` opens `withInterpolationUndo`; both defer to an
    /// enclosing bracket rather than recording their own, so the outer bracket here is all it takes.
    ///
    /// It has to be the **interpolation** bracket, not the structure one. §5's note on
    /// `withInterpolationUndo` says an inner vector-content edit nested inside an outer structural
    /// bracket is not undoable and that the fix is to widen the outer one; Phase 5 is the thing that
    /// needed it, because registration writes motion-group tags onto the keyframes' strokes.
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

    // MARK: - Registration with motion groups (Phase 5)

    /// What registration decided about a drawing's parts.
    ///
    /// Three outputs rather than one because a grouping has to be *stored* in three places: the
    /// geometry goes in the recipe (`bindings`), the artist-facing identity goes in the document
    /// registry (`invented`), and membership goes on the strokes themselves (`assignments`). The
    /// third is the one that is easy to leave out and the one that makes the feature usable —
    /// without tags the decision would live only inside the recipe, where nothing can show it and
    /// nothing can correct it.
    struct GroupRegistration {
        /// One per part, in the order the parts came back. A recipe's `groups`.
        var bindings: [MotionGroupBinding]

        /// Groups registration had to create because the drawing turned out to have several parts.
        /// **Empty when the answer was one whole-frame group**, which stays anonymous — a registered
        /// group is an artist-facing object and inventing one for the degenerate case would put
        /// document state in front of the artist that they never asked for (`HANDOFF.md` §5.10).
        var invented: [MotionGroup]

        /// Per keyframe, per element, the group it landed in. Empty for the anonymous whole-frame
        /// answer, which tags nothing.
        var assignments: [[UUID?]]

        static let none = GroupRegistration(bindings: [], invented: [], assignments: [])
    }

    /// Tag colours for groups registration invents, cycled in order.
    ///
    /// Saturated and spread around the wheel, because their whole job is to be told apart at a glance
    /// over linework that is usually black. Deliberately unrelated to any stroke's paint colour
    /// (`PLAN.md` §5.1.1) — this is metadata, and "Tag by stroke colour" is a one-shot populate of
    /// membership, never a live binding of appearance.
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

    /// **Phase 5's registration.** Split the drawing into parts that move together, and fit each part
    /// on its own.
    ///
    /// `PLAN.md` §5.3's one algorithm with two seeds: the artist's tags if there are any, one group
    /// covering everything if there are not. Both go through `MotionGrouping.group`, which refines a
    /// seeded partition exactly as it splits an unseeded one, so tagging one limb does not switch the
    /// artist onto a different code path — it only changes where the recursion starts.
    ///
    /// **The whole-frame answer is preserved exactly.** A drawing that groups into one part takes the
    /// Phase 4 path unchanged: one anonymous binding, no registered group, no tags written. That is
    /// not a special case bolted on — it is the honest reading of "this drawing has one part", and
    /// keeping it identical is what stops a single-stroke test drawing acquiring document state.
    ///
    /// `existing` is the document's group registry, consulted so that re-registering after a retag
    /// **reuses the artist's own groups** instead of minting a parallel set beside them.
    static func registerGroups(frames: [RegistrationFrame],
                               existing: [MotionGroup]) -> GroupRegistration {
        guard let first = frames.first, !first.cloud.isEmpty, frames.count >= 2,
              let last = frames.last, !last.cloud.isEmpty else {
            return wholeFrameRegistration(frames: frames)
        }

        // Grouping is measured against the **last** keyframe rather than the next one, because it is
        // asking a question about the whole span: two parts that move differently are most separable
        // where they have moved furthest apart. With today's two references the two are the same
        // frame; with a spline (`PLAN.md` §10 decision 7) grouping against the adjacent keyframe
        // would let a part that barely moves in the first segment hide inside its neighbour.
        let ceiling = ARAPRegistration.Options().maxRegistrationSamples
        let target = PointCloudIndex(ARAPRegistration.subsampled(last.cloud, to: ceiling))
        let parts = MotionGrouping.group(strokes: first.elements.map(\.points), target: target,
                                         seeds: tagSeeds(first.elements))
        guard parts.count > 1 else { return wholeFrameRegistration(frames: frames) }

        // One id per part, reusing whatever the members already agree on so a retag survives a
        // re-registration, and minting the rest.
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

        // Frame 0's assignment is the partition itself; every later frame is assigned by geometry,
        // honouring any tag the artist already put there.
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
                // A part with no counterpart at this keyframe has nothing to fit to, and "do not
                // move" is the only answer that is not invented — the same rule the whole-frame path
                // uses for an empty keyframe. Its ink fades on weight alone, which is the honest
                // rendering of content that is not there at the other end (`HANDOFF.md` §8 item 34
                // is the better answer, and it is not built).
                guard !slice.cloud.isEmpty else { lattices.append(rest); continue }
                let cloud = ARAPRegistration.subsampled(slice.cloud, to: ceiling)
                let fit = ARAPRegistration.fit(lattice: rest, source: source.cloud,
                                               target: PointCloudIndex(cloud),
                                               correspondence: source.correspondence(to: slice))
                lattices.append(fit.lattice)
            }
            bindings.append(MotionGroupBinding(groupID: id, lattices: lattices))
        }

        // Every part that produced no binding — an empty one, which `guard` above skips — must not
        // leave its tag behind, or a stroke would reference a group the recipe cannot warp and would
        // silently fall through to the first binding instead of its own.
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

    /// Phase 4's answer, in Phase 5's shape: one anonymous binding and nothing else.
    private static func wholeFrameRegistration(frames: [RegistrationFrame]) -> GroupRegistration {
        guard let binding = registerWholeFrameGroup(frames: frames) else { return .none }
        return GroupRegistration(bindings: [binding], invented: [], assignments: [])
    }

    /// The artist's tagging as a seed partition, or nil when nothing is tagged.
    ///
    /// Order is first-appearance rather than the registry's, so the seeds line up with the drawing
    /// rather than with the order groups happened to be created in. Untagged elements are left out
    /// entirely — `MotionGrouping.group` gathers them into one extra group, which is exactly right:
    /// a partial tagging should still produce a complete partition.
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
    /// an earlier part.
    ///
    /// Most common rather than unanimous because grouping is free to move an element between seeded
    /// parts when the residuals say so, and a part that is nine tenths "Arm" is Arm. Excluding
    /// already-claimed ids keeps two parts from collapsing onto one group when a seed splits in two:
    /// the larger half keeps the name, the splinter gets a new one, which is what the artist sees as
    /// "it found another part inside the one I tagged".
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
    /// An element that already carries one of the parts' tags keeps it: that is the artist having
    /// said so, at the keyframe where they said it, and geometry has no business overruling it.
    /// Everything else is assigned by geometry — each part's fitted similarity is applied to its own
    /// source points, and the element joins whichever part it then sits nearest to.
    ///
    /// Nearest-to-the-*moved*-source rather than nearest-to-the-source: the whole premise is that the
    /// parts moved, so comparing against where they started would put an arm that swung across the
    /// body into the torso's group. `MotionGrouping.Group.fit` is exactly that motion and it has
    /// already been computed, so this costs one point-cloud index per part and no further fitting.
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

    /// One element of one keyframe, as registration sees it.
    ///
    /// Elements rather than one summed point cloud because Phase 5 has to *partition* a keyframe: a
    /// motion group is a set of elements, and both the grouping algorithm and the per-group fit want
    /// the frame sliced along that partition rather than added together.
    struct RegistrationElement {
        /// What this element contributes to the point cloud. A stroke's samples, a fill's control
        /// points, a placed image's centre — see `registrationPoints(of:)`.
        var points: [CGPoint]

        /// Its polyline when it is a stroke, **nil** for a fill or a placed image. Tier 0's 1:1
        /// correspondence needs the strokes kept apart so it can pair them; see
        /// `RegistrationFrame.strokes` for why a non-stroke poisons the whole frame.
        var stroke: [CGPoint]?

        /// The motion group it is tagged with, which is what seeds the grouping. Nil is untagged,
        /// which is every stroke until this phase runs once.
        var groupID: UUID?
    }

    /// One keyframe's geometry, as registration sees it.
    ///
    /// Three views of the same content, because the three things that read it want different shapes:
    /// tier 1 and the fallback fit want every point whatever drew it, tier 0's 1:1 correspondence
    /// wants the strokes kept apart so it can pair them (`HANDOFF.md` §8 item 31), and grouping wants
    /// to slice the frame down to one part at a time.
    struct RegistrationFrame {
        /// The frame's elements in display-list order. The partition is expressed as indices into
        /// this, which is also the order tags are written back in.
        var elements: [RegistrationElement]

        /// Every point the display list contributes. Never nil — this is what registration always
        /// had.
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

        /// The sub-frame holding only the elements at `indices`, in their original order.
        ///
        /// Sliced rather than re-derived so a part inherits the frame's own all-or-nothing stroke
        /// rule: a group made entirely of strokes keeps its correspondence even when a *fill*
        /// elsewhere on the keyframe made the whole frame's `strokes` nil. That is worth having —
        /// it is precisely the lineart-plus-flats case requirement 5 is about.
        func restricted(to indices: [Int]) -> RegistrationFrame {
            RegistrationFrame(elements: indices.compactMap {
                elements.indices.contains($0) ? elements[$0] : nil
            })
        }

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
                // A fill or a placed image contributes to the cloud but cannot carry a tag —
                // `motionGroupID` is a field on `VectorStroke` only (`HANDOFF.md` §8 item 11). It is
                // still *grouped*: its points take part in the partition, so it lands in a part and
                // gets a lattice; it simply has nowhere to record which one, so at render time it
                // rides the recipe's first binding like any untagged content.
                return RegistrationElement(points: registrationPoints(of: [element]), stroke: nil,
                                           groupID: nil)
            }
        })
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
