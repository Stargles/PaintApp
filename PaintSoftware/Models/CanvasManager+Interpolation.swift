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

    // MARK: - The groups the bar shows, and the retagging gesture

    /// One chip's worth of state — a registered group plus how much of the current keyframes is
    /// actually in it.
    struct MotionGroupChip: Identifiable {
        var group: MotionGroup
        /// Strokes carrying this group's id across every flagged keyframe. Zero is meaningful: it is
        /// a group the artist made or deleted the last stroke out of, and hiding it would make it
        /// unreachable rather than tidy.
        var strokeCount: Int
        var isArmed: Bool
        var isHidden: Bool
        var id: UUID { group.id }
    }

    /// The groups `InterpolateBar` puts on screen, in registry order.
    ///
    /// The registry rather than the active recipe's bindings, because a `MotionGroup` is
    /// **document-level** by design (requirement 5: one group spans a lineart layer and a flats
    /// layer), so scoping the chips to one recipe would hide the group an artist is about to tag
    /// content into on a second layer. Counts are over the flagged keyframes, which is the drawing in
    /// front of them.
    ///
    /// Phase 4's whole-frame binding has a `groupID` with no registry entry and so contributes no
    /// chip — deliberately. It is not an artist-facing object and never was (`HANDOFF.md` §5.10);
    /// `hasAnonymousWholeFrameGroup` is what the bar uses to say so in words instead.
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

    /// True when the cel under the playhead derives from a recipe whose grouping is Phase 4's single
    /// anonymous whole-frame binding — one part, no registry entry, nothing tagged.
    var hasAnonymousWholeFrameGroup: Bool {
        guard let at = interpolationTarget,
              let recipe = layers[at.layer].cels[at.cel].interpolation,
              recipe.groups.count == 1 else { return false }
        return motionGroup(withID: recipe.groups[0].groupID) == nil
    }

    /// Arms a group for tap-to-assign, or disarms it when it is already armed.
    ///
    /// Toggling rather than a separate off switch: the chip is the only control, and an artist who
    /// has finished tagging presses the thing they pressed to start. Arming a *different* group while
    /// one is armed just moves the arming, which is what tagging several parts in a row looks like.
    func toggleArmedMotionGroup(_ id: UUID) {
        armedMotionGroupID = armedMotionGroupID == id ? nil : id
    }

    /// The retagging gesture: assign the stroke under `point` on the current layer to the armed group.
    ///
    /// Returns the stroke it tagged, or nil when nothing was armed, the layer is not a vector layer,
    /// or the tap landed on bare canvas — all three are "do nothing quietly" rather than errors, since
    /// a miss is an ordinary part of tapping at strokes.
    ///
    /// The cel it reaches is `interpolationTarget`, the same one every other command in this mode
    /// acts on (`HANDOFF.md` §5.10). In practice that is a *keyframe*, because that is where the ink
    /// is: standing on the derived in-between there is nothing to tap, which is correct — the
    /// in-between has no strokes of its own to belong to a group.
    ///
    /// Tapping a stroke **already** in the armed group clears its tag instead, so one gesture both
    /// adds and removes and the artist can undo a mis-tap without hunting for a second control. Note
    /// what clearing means here, which is not what it sounds like: registration re-tags everything it
    /// partitions, so the stroke is re-decided by geometry rather than left out
    /// (`InterpolationMotionGroupLogicTests` pins this).
    ///
    /// It goes through `setMotionGroup`, so it re-registers and undoes in exactly one step like any
    /// other retag.
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

    /// A keyframe's own drawing, with every stroke repainted in its motion group's tag colour —
    /// `IMPLEMENTATION.md` Phase 5 item 4's legibility pass.
    ///
    /// Nil unless interpolate mode is on, the overlay is switched on, the cel is a vector cel and
    /// something on it is actually tagged. In particular a single-part drawing gets nothing, because
    /// tinting a whole drawing one colour says nothing at all.
    ///
    /// **The whole display list, not just the tagged strokes**, because the seam it goes through
    /// (`StrokeCanvasView.setInterpolationImage`) *replaces* the cel's display rather than drawing
    /// over it. Returning only the tinted strokes would make every fill and placed image vanish
    /// while the overlay was up.
    ///
    /// Untagged strokes are drawn grey rather than left in their own colour. Grey is a statement —
    /// "this rides the first binding, it is along for someone else's ride" (`HANDOFF.md` §5.9) — and
    /// it is the state the artist is looking for when they suspect a stroke is being carried by the
    /// wrong part. Leaving it black would make it indistinguishable from a stroke that is fine.
    ///
    /// Rendered at `.preview` quality: this is a diagram of a decision, not artwork, and the polyline
    /// tier is several times cheaper per pass (`HANDOFF.md` §5.9).
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

    /// Solo: show only this group. Pressing it again on the group that is already alone clears the
    /// filter rather than hiding everything, which is the only reading that lets solo be its own
    /// off switch.
    func soloMotionGroup(_ id: UUID) {
        let others = Set(motionGroups.map(\.id)).subtracting([id])
        hiddenMotionGroups = hiddenMotionGroups == others ? [] : others
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

    // MARK: - Editing at an in-between (Phase 6 items 2 and 3)

    /// The interpolated cel a layer is showing at the playhead, or nil when it is showing an
    /// ordinary drawing.
    ///
    /// The gate is "the cel carries a recipe", **not** "interpolate mode is on", and the difference
    /// matters. An interpolated cel shows its derived in-between whatever mode the app is in, so a
    /// stroke committed to its own `VectorCanvas` would land in a display list nothing on screen
    /// renders — the artist would draw and watch the ink vanish. Routing on the recipe alone means
    /// an in-between behaves the same way from every entry point.
    ///
    /// By layer rather than by cel because the caller is a layer's own canvas view, which knows
    /// which layer it is and nothing about cels. Note this is deliberately *not*
    /// `interpolationTarget` (§5.10's "the cel under the playhead on the **current** layer"): that
    /// one answers for the commands on the bar, which act on the layer the artist has selected,
    /// while a touch is answered by the view it landed in.
    func inBetweenCelID(inLayer layerID: UUID) -> UUID? {
        guard let layerIndex = layers.firstIndex(where: { $0.id == layerID }),
              let celIndex = activeCelIndex(inLayer: layerIndex, atFrame: currentFrame),
              layers[layerIndex].cels[celIndex].interpolation != nil
        else { return nil }
        return layers[layerIndex].cels[celIndex].id
    }

    /// The current layer is showing an interpolated cel at the playhead.
    ///
    /// The whole-content vector transform (`isVectorTransforming`) is refused on one, and it is a
    /// refusal rather than a routing — see `IMPLEMENTATION.md` Phase 6 item 3 and `HANDOFF.md` §5.13.
    /// A transform at `t` moves the *frame*, and an in-between's frame is derived: `setVectorTransform`
    /// writes onto the cel's own `VectorCanvas`, which is empty and which the evaluated image does not
    /// come from, so the handle box would drag around a drawing that never moved. That is a silent
    /// no-op, and a silent no-op is worse than an unavailable control.
    var activeCelIsInBetween: Bool {
        guard layers.indices.contains(currentLayerIndex) else { return false }
        return inBetweenCelID(inLayer: layers[currentLayerIndex].id) != nil
    }

    /// Records a stroke drawn *at* the in-between — `PLAN.md` §5.4, `IMPLEMENTATION.md` Phase 6
    /// item 2. Returns false when the recipe cannot take it, and the caller should fall back to
    /// committing the stroke normally.
    ///
    /// The four steps of §5.4, in order: the stroke is embedded in the deformed lattice at `t`, the
    /// lattice grows by whole rings if it falls outside, the inverse map carries it back to the
    /// lattice's rest space, and it is given τ = `t` so it does not appear before the frame it was
    /// drawn at. `InterpolationEvaluator.planLocalEdit` does the first three; this does the writing.
    ///
    /// **Why the samples go in without the canvas→local transform** the ordinary
    /// `addStroke(canvasSpaceStroke:)` path applies. The whole interpolation pipeline works in one
    /// space: registration reads the reference cels' display lists, and `composite` renders the
    /// result into a fresh identity-transform `VectorCanvas` that the layer view shows as-is. So the
    /// lattices live in whatever space those display lists are in, and the pixels the artist is
    /// aiming at are placed by that same space — mapping the samples through *this* cel's transform
    /// would put the edit somewhere other than where they drew it. The cost is inherited rather than
    /// added: a moved or scaled reference layer is already unhandled by the evaluator.
    @discardableResult
    func recordLocalEdit(canvasSpaceStroke stroke: VectorStroke,
                         forCel celID: UUID, inLayer layerID: UUID) -> Bool {
        guard let at = celIndices(forCel: celID, inLayer: layerID),
              let recipe = layers[at.layer].cels[at.cel].interpolation,
              let plan = InterpolationEvaluator.planLocalEdit(
                recipe: recipe, at: recipe.t, points: stroke.samples.map(\.point),
                options: interpolationOptions),
              plan.restPoints.count == stroke.samples.count
        else { return false }

        var stored = stroke
        stored.samples = zip(stroke.samples, plan.restPoints).map {
            VectorSample(x: $1.x, y: $1.y, pressure: $0.pressure)
        }
        // τ = `t`: the edit belongs to the pose it was made at and does not exist before it
        // (`PLAN.md` §5.4 step 4). The evaluator's one-sided `t >= τ` test is what enforces it, so
        // sliding the frame *earlier* than where the edit was drawn hides it again — which is the
        // designed behaviour and not a rounding artefact.
        stored.visibilityThreshold = recipe.t
        // A stroke's own tag is what *keyframe* content uses to find its group. A local edit's group
        // is on the `LocalEdit`, because the edit is not part of either keyframe's drawing and a tag
        // here would make it look like it were. One place records the answer, not two.
        stored.motionGroupID = nil

        let edit = LocalEdit(stroke: stored, groupID: plan.groupID)
        withInterpolationUndo(name: stroke.composite == .erase ? "Erase at In-Between"
                                                               : "Draw at In-Between") {
            // The grown lattices go back into the binding they came from. No index anywhere needs
            // remapping, which is the whole point of the recipe storing geometry and never indices
            // (`HANDOFF.md` §5.7) — a ring shifts every cell and vertex index, and nothing here
            // holds one.
            if let grown = plan.grownLattices, let index = plan.bindingIndex {
                layers[at.layer].cels[at.cel].interpolation?.groups[index].lattices = grown
            }
            layers[at.layer].cels[at.cel].interpolation?.localEdits.append(edit)
        }
        return true
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
        // Both are view state that only means anything inside the mode, and an armed group left set
        // would turn the next ordinary canvas tap into a silent retag.
        armedMotionGroupID = nil
        hiddenMotionGroups.removeAll()
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
        // Only inside the mode: solo/mute is a working view of an in-between being judged, and a
        // group left muted must not follow the artist out and quietly blank part of every export.
        options.hiddenGroups = isInterpolateMode ? hiddenMotionGroups : []
        return options
    }

    /// `interpolationOptions` with solo/mute forced off — what any evaluation whose result is
    /// **written to the document** must use, which today means Commit.
    ///
    /// The distinction is sharp and it is worth naming rather than inlining. `hiddenGroups` is a view
    /// filter: it answers "which part is moving wrongly" by taking the others away, and §5 already
    /// records that it must not reach a render outside the mode. Commit is the case that breaks that
    /// rule from the other side — it runs *inside* the mode, where `hiddenGroups` is legitimately
    /// populated, and it writes what it evaluates. Baking with a group muted would delete that
    /// group's content from the drawing permanently, on a command that says nothing about deleting.
    ///
    /// `thicknessFade` is deliberately kept, because that one is not a filter: it is a choice about
    /// what the in-between *looks like*, the artist toggled it, and it is what they can see when they
    /// press the button.
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
            }
        }
    }

    /// Whether `interpolate` would succeed for this cel, and why not if it would not.
    func interpolationRefusal(mode: InterpolationMode, layerIndex: Int, celIndex: Int) -> InterpolationRefusal? {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex),
              layers[layerIndex].cels[celIndex].vector != nil else { return .notAVectorLayer }
        // Generating on a cel that already derives from a recipe is never what was meant: the second
        // Generate silently replaces the first, so a double tap looks like it interpolated twice and
        // an artist who has scrubbed to a `t` they like loses it. Retiming is the slider's job, and
        // starting over is Remove Interpolation's.
        //
        // **Reproject does not inherit it, and that is now a decision rather than a stub.** Its whole
        // subject is a cel that already has content, and re-running it is the honest way to pick up
        // references that have changed — it re-registers the same linework against them and replaces
        // nothing. Note what this does *not* let through: a cel carrying a `.generate` recipe holds
        // no strokes of its own (an in-between is derived, never stored), so Reproject on one refuses
        // with `.nothingToReproject`. Commit is what turns it into a frame Reproject can work on,
        // which is exactly the composition `PLAN.md` §5.5 describes.
        if mode == .generate, layers[layerIndex].cels[celIndex].interpolation != nil {
            return .alreadyInterpolated
        }
        if mode == .reproject, layers[layerIndex].cels[celIndex].vector?.elements.isEmpty != false {
            return .nothingToReproject
        }
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
        // No block at the playhead means no drawing to repose. Generate makes one; Reproject cannot,
        // because the thing it acts on is the artist's own linework.
        if mode == .reproject { return .nothingToReproject }
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

        // **Reproject registers the cel's own drawing, not the keyframes' parts.** No grouping runs
        // and no tags are written: motion groups partition a drawing that is being *derived* from two
        // others, and here there is one drawing whose pose slides as a whole. `PLAN.md` §5.5's mixed
        // case — "groups B has get Reproject, groups it lacks get Generate" — is a later item; the
        // model already allows it, since a recipe's bindings are a list.
        if mode == .reproject {
            let subject = Self.registrationFrame(of: layers[layerIndex].cels[celIndex].vector?.elements ?? [])
            guard let binding = Self.registerReprojection(subject: subject, frames: frames) else {
                return .nothingToReproject
            }
            let recipe = InterpolationRecipe(references: keyframes, t: 0.5, mode: .reproject,
                                             groups: [binding])
            // The structural bracket is enough here, and only here: reprojection writes a value type
            // into `Cel` and touches no stroke anywhere. Generate's wider bracket exists because its
            // registration tags the *keyframes'* strokes — see below.
            withStructureUndo(name: "Reproject") {
                layers[layerIndex].cels[celIndex].interpolation = recipe
            }
            return nil
        }

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

    // MARK: - Commit

    /// **Commit** — bake the frame this cel currently derives at into the cel as ordinary content and
    /// drop the recipe. `PLAN.md` §4, `HANDOFF.md` §8 item 17. One-way, explicit, never automatic;
    /// undoable like anything else, which is what keeps "one-way" from meaning "unrecoverable".
    ///
    /// This is the counterpart to `interpolate`: that one makes a frame derived, this one makes it a
    /// drawing again. It is also the missing link in `PLAN.md` §5.5's composition — a `.generate` cel
    /// stores no strokes of its own, so Reproject refuses on one with `.nothingToReproject`, and
    /// Generate → **Commit** → Reproject is how an in-between becomes something to re-pose.
    ///
    /// **It is lossy at an interior `t` and that is the artist's decision to make, not this
    /// function's to prevent.** `InterpolationEvaluator.flattened` documents exactly what changes and
    /// why no display list can avoid it; a commit at `t = 0` or `t = 1` is bit-exact. What matters
    /// here is that the loss happens *once*, visibly, on a command the artist pressed — the reason
    /// PLAN §4 insists this is never automatic.
    ///
    /// Note it deliberately does **not** care whether interpolate mode is on. A cel carries its
    /// recipe from every entry point (the same reasoning as `inBetweenCelID`), and a command that
    /// worked only in one mode would be a second rule to learn.
    ///
    /// Returns the refusal reason, or nil on success.
    @discardableResult
    func commitInterpolation(layerIndex: Int, celIndex: Int) -> InterpolationRefusal? {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex),
              let canvas = layers[layerIndex].cels[celIndex].vector else { return .notAVectorLayer }
        guard let recipe = layers[layerIndex].cels[celIndex].interpolation else { return .nothingToCommit }
        // The cel's own display list is the subject of a reprojection and is ignored by a generation
        // — the same join `interpolatedImage` makes, and for the same reason: the recipe holds no
        // reference to the cel it lives on, so this is the one place that knows both.
        let subject = recipe.mode == .reproject ? canvas.elements : []
        // `interpolationCommitOptions`, never `interpolationOptions` — see its comment. Committing
        // with a group muted would delete that group's content from the drawing for good.
        guard let evaluation = InterpolationEvaluator.evaluate(
            recipe: recipe, at: recipe.t, content: interpolationContentProvider,
            subject: subject, options: interpolationCommitOptions)
        else { return .interpolationNotEvaluable }

        let baked = InterpolationEvaluator.flattened(evaluation)
        // `withInterpolationUndo` rather than `withStructureUndo`, and this is the first caller in
        // the feature that writes stroke content from a recipe — §5's Phase 2 entry predicted it.
        // The structure bracket alone would restore the recipe and none of the ink, because
        // `StructureSnapshot` shares each `VectorCanvas` by reference rather than copying it.
        withInterpolationUndo(name: "Commit Interpolation", touching: [canvas]) {
            canvas.elements = baked
            // The setters do not invalidate — `VectorCanvas`'s accessor contract — so a wholesale
            // assignment has to bump the version itself, or the cel would keep rendering the cached
            // image of an empty display list.
            canvas.bumpVersion()
            layers[layerIndex].cels[celIndex].interpolation = nil
        }
        return nil
    }

    /// Whether `commitInterpolation` would succeed, without performing it. Shares every check with
    /// it, **including the evaluation** — a malformed recipe is the reachable failure (delete a
    /// referenced cel and the frame stops being renderable while the recipe stays put).
    ///
    /// **Not what greys the bar's button out, and that is deliberate**, which makes this the one
    /// refusal in the feature that breaks §5.10's pattern. Every other one is a cheap structural
    /// test that a view can afford to re-ask on every SwiftUI pass; this one runs `evaluate`, which
    /// is an ARAP solve per motion group. `InterpolateBar` gates the button on "there is a recipe"
    /// and reports the refusal on tap instead. Anything that wants the precise answer should call
    /// this from an event handler, never from a `body`.
    func commitRefusal(layerIndex: Int, celIndex: Int) -> InterpolationRefusal? {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex),
              let canvas = layers[layerIndex].cels[celIndex].vector else { return .notAVectorLayer }
        guard let recipe = layers[layerIndex].cels[celIndex].interpolation else { return .nothingToCommit }
        let subject = recipe.mode == .reproject ? canvas.elements : []
        guard InterpolationEvaluator.evaluate(recipe: recipe, at: recipe.t,
                                              content: interpolationContentProvider,
                                              subject: subject,
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

    /// **Reproject** — the target cel's own drawing, registered so its *pose* can slide along the
    /// A→C motion while its linework is never touched (`PLAN.md` §5.5, Phase 6 item 1).
    ///
    /// One structural difference from `registerWholeFrameGroup` carries the whole feature: **which
    /// drawing the rest lattice covers.** Generate's rest lattice is drawn over keyframe A, and A's
    /// content is what rides it. Here it is drawn over the *subject* — this cel's own cloud — and
    /// every entry in `lattices`, including the first, is a fit of that grid to a reference. So
    /// `lattices[0]` is the subject posed as keyframe A, `lattices[1]` is it posed as keyframe C, and
    /// the evaluator's interpolation between them is the pose sliding. The subject embeds in the
    /// lattice's **rest** configuration, which is where it was drawn, so nothing about its geometry
    /// is derived — only where the grid carrying it currently sits.
    ///
    /// That first entry being a fit rather than the rest configuration is the invariant Generate's
    /// array has and this one deliberately does not. For Generate, `t = 0` reproduces keyframe A to
    /// the last bit precisely because `lattices[0]` *is* the rest grid its content was embedded in.
    /// A reprojected cel has no such endpoint — it is neither keyframe — and giving it one would
    /// show the drawing unposed at `t = 0` and snap the instant the slider moved.
    ///
    /// Nil when there is nothing to repose or nothing to repose it along; the caller turns that into
    /// a refusal the artist can read.
    static func registerReprojection(subject: RegistrationFrame,
                                     frames: [RegistrationFrame]) -> MotionGroupBinding? {
        guard !subject.cloud.isEmpty, frames.count >= 2 else { return nil }

        let rest = Lattice(covering: subject.cloud,
                           targetCellSize: latticeCellSize(covering: subject.cloud), padding: 1)
        let ceiling = ARAPRegistration.Options().maxRegistrationSamples
        var lattices: [Lattice] = []
        for frame in frames {
            // A keyframe with nothing in it gives the pose no target, and "stay where it was drawn"
            // is the only answer that is not invented — the same rule the Generate path uses.
            guard !frame.cloud.isEmpty else { lattices.append(rest); continue }
            let cloud = ARAPRegistration.subsampled(frame.cloud, to: ceiling)
            let fit = ARAPRegistration.fit(lattice: rest, source: subject.cloud,
                                           target: PointCloudIndex(cloud),
                                           correspondence: subject.correspondence(to: frame))
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
        // A reprojection's content is the cel's own display list, which no `ContentProvider` can
        // reach — the recipe holds no reference to the cel it lives on, by design. Handing it over
        // here is the one place that knows both.
        let subject = recipe.mode == .reproject ? (layers[at.layer].cels[at.cel].vector?.elements ?? []) : []
        return InterpolationEvaluator.render(recipe: recipe, at: t ?? recipe.t, size: canvasSize,
                                             content: interpolationContentProvider, subject: subject,
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
