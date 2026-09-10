import CoreGraphics
import UIKit

/// **Editing which animation group a drawing belongs to** — TODO (21)'s last owner-facing gap, ruled
/// 2026-09-10.
///
/// The owner, asked in artist terms whether a drawing moved between animated groups should stay where
/// it looks on screen or snap to the new group's motion:
///
/// > *"stay where it looks like on screen for animation groups. […] Along with that, the ability to
/// > add new selections to an animation group (not only from another animation group) and remove
/// > selections from groups will be useful."*
///
/// ## Three operations and one rule
///
/// **Add** a selection to a group, **remove** a selection from a group, **move** a selection from one
/// group to another. All three are the same write, because all three are the same arithmetic with one
/// or both ends set to "no group".
///
/// **What "stays where it looks on screen" has to mean, and it is an interpretation rather than a
/// quote.** Read literally as *every* frame it is self-defeating — an element that looks identical at
/// every frame after joining a group has not joined it in any observable sense — and it is not
/// expressible anyway, because only groups carry tracks (§3.4) and per-frame compensation would need a
/// per-element track that does not exist. The reading built here is re-parenting's, which is what
/// every animation tool means by it: **appearance is preserved at the frame the artist is standing on,
/// and from there the element follows its new group.**
///
/// ## The arithmetic, and why the cel channel and the container pose are not in it
///
/// `CanvasManager.posed(_:through:inheriting:)` shows an element at `g · G · C · I` — its stored
/// geometry through its **group** channel, then the **cel** channel, then whatever container pose is
/// **inherited** — in that fixed order, groups first. Membership changes only the first factor, so
/// preserving the product at frame `F` means
///
/// ```
///     g′ · G_new(F) = g · G_old(F)      ⟹      g′ = g · G_old(F) · G_new(F)⁻¹
/// ```
///
/// and `C` and `I` cancel **exactly**, because both carry every element on the cel and neither knows
/// what group anything is in. That is why this file never reads them: a compensation that folded them
/// in would be right at this frame and wrong at every other, since it would have baked the cel's own
/// animation into one element's rest geometry.
///
/// The three operations are the three ways the two ends can be filled in, and there is no fourth:
///
/// | | `G_old` | `G_new` | what the element does afterwards |
/// |---|---|---|---|
/// | **add** | identity | the group's pose at `F` | starts following the group |
/// | **remove** | the group's pose at `F` | identity | stands still where it stood |
/// | **move** | the old group's pose at `F` | the new group's pose at `F` | follows the new group |
///
/// A channel with no track, or one resting at `F`, contributes the identity —
/// `resolvedPoseMap(layerID:celID:channel:atFrame:)`'s own answer — so an add into a group that is not
/// animated on this cel rewrites no geometry at all, which is right: there is nothing to compensate.
///
/// ## Two edges the ruling left open, both decided here
///
/// **A remove that empties a group keeps the group and keeps its track.** The alternative — delete the
/// registry entry and the channel once the last member leaves — destroys the artist's animation on a
/// verb they reached for to move one drawing, and it is `Layer.valueFill`'s asymmetry exactly (§3.5:
/// *"a picker that silently destroys the other mode's setting is what a picker must not do"*). Keeping
/// it also makes the round trip **exact**: remove writes `g · G(F)`, adding the same element back at
/// the same frame writes `g · G(F) · G(F)⁻¹ = g`, so a mistaken remove costs nothing but an undo press
/// even if the artist re-adds by hand instead. An empty group's track is inert in every reader —
/// `posed` asks `isMoved(by:)` and no element answers yes — and it stays listed in the graph editor
/// and in the Select panel, which is what lets the artist put something back into it.
///
/// **An add cannot make a track meaningless, but a pose can make the edit impossible, and that is
/// refused whole.** Two ways: the destination group's pose at this frame is **singular**, so
/// `G_new(F)⁻¹` does not exist and there is no geometry that reproduces where the drawing looks; or
/// the compensation is **projective** and the loop caught a placed image or a video, whose whole
/// placement is six numbers and a mirror bit with nowhere for the perspective residue to live
/// (`VectorCanvas.posing(_:through:)`'s two declining kinds, and `distortUnavailableReason`'s voice).
/// Either way nothing is written and a notice says which — **never a partial edit**, because every key
/// on both tracks changes meaning at once and a half-applied membership edit is a corrupted document.
///
/// **What is *not* an edge: adding ink to a group whose track already animates.** That is the feature.
/// And adding every element on the cel to one group makes that group's channel do what `.cel`'s does,
/// which composes correctly (`poseMappings` orders groups before the cel) and is merely redundant.
///
/// ## What this does not touch
///
/// **No track is ever written here**, which is what keeps §2.28's union honest: the union is the
/// explicit marks plus every frame a channel keys on, computed by one accessor
/// (`poseKeyframeFrames(inLayer:)` folding into `keyedFrames(of:)`), and neither list is a function of
/// membership. A membership edit therefore leaves the union bit-for-bit as it was, and
/// `testAMembershipEditLeavesTheKeyframeUnionExactlyAsItWas` pins that rather than assuming it.
///
/// **KEYFRAMES §2.29's refusal survives untouched.** A *Move* that catches part of an animated group
/// is still refused and still says so; this is the sanctioned way to do what it refuses, and both
/// refusal sentences now name it.
struct SelectionAnimationGroupMemo: Equatable {
    var pathObject: ObjectIdentifier
    var bounds: CGRect
    var layerID: UUID
    var celID: UUID
    var frame: Int
    var vectorVersion: Int
    var membership: LassoMembership
    var registered: Int
    var answer: CanvasManager.SelectionAnimationGroup
}

extension CanvasManager {

    // MARK: - What the artist can ask for

    /// The three operations, as the one thing a control writes. `newGroup` is a fourth *pick* and not
    /// a fourth operation: it mints a group and then adds, and it is here rather than at the call site
    /// so the mint happens **after** every refusal has passed and a refused edit cannot leave a stray
    /// group in the registry.
    enum AnimationGroupAssignment: Hashable {
        case none
        case existing(UUID)
        case newGroup
    }

    /// What the loop has caught, as a membership — the Select panel's readout.
    ///
    /// **`mixed` is a real answer and not a failure.** A loop can hold ink from two groups, and the
    /// edit is still perfectly well defined for it: every caught element is compensated out of
    /// *whatever it was in* and into the one destination. The readout says so rather than pretending
    /// there is a single current value.
    enum SelectionAnimationGroup: Equatable {
        /// No selection, or a layer this verb cannot act on.
        case unavailable
        /// The loop caught something, and none of it is in a registered group.
        case untagged
        case one(UUID)
        case mixed
    }

    /// Why the Animation Group control is off, in the artist's terms, or nil when it is on.
    ///
    /// Word for word `recolorUnavailableReason`'s shape and for its reason — a control that does
    /// nothing says why — with this control's own subject in it. Both refusals are the same two:
    /// membership is a field on a stored element, so it wants a vector cel that is not derived.
    var animationGroupEditUnavailableReason: String? {
        guard layers.indices.contains(currentLayerIndex) else { return nil }
        guard layers[currentLayerIndex].kind == .vector,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              layers[currentLayerIndex].cels[celIndex].vector != nil else {
            return "Animation groups hold drawn marks, so this works on vector layers only."
        }
        if activeCelIsInBetween { return "An animation group can't be changed on an in-between frame." }
        return nil
    }

    // MARK: - Reading, cheaply enough for a SwiftUI body

    /// **Which group the loop's ink is in.** Read once per `SelectPanel` body pass, so the expensive
    /// half is behind three gates and a one-entry memo.
    ///
    /// The expensive half is genuinely expensive — `localPath(fromCanvas:)`, a `normalized` boolean op
    /// over a path that is usually self-intersecting, a per-element pull-back through the frame's
    /// poses, and a containment test per element — which is fine once per `recolorSelection` and not
    /// fine once per layout pass. So:
    ///
    ///   * **no registered groups at all** answers `untagged` with no geometry touched, which is every
    ///     document that has never been keyframed;
    ///   * **no element on this cel carrying a registered tag** answers the same, on one scan of an
    ///     `Optional<UUID>` field with no geometry in it — that is every document whose groups live on
    ///     other cels;
    ///   * and what is left is memoized on everything the answer can depend on. The memo's key
    ///     includes `vectorVersion`, so the edit this readout labels invalidates it by construction.
    ///
    /// **The cheap classifier, never the splitter.** Under Cut the real edit splits a straddling
    /// element and the inside half inherits its parent's tag (`splitForLassoMove` copies the parent
    /// whole), so the parent's group *is* the answer for the piece that will be edited — and a readout
    /// that cut geometry to draw a label would be a side effect in a getter.
    var selectionAnimationGroup: SelectionAnimationGroup {
        guard animationGroupEditUnavailableReason == nil,
              let selection,
              layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].id == selection.layerID,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              layers[currentLayerIndex].cels[celIndex].id == selection.celID,
              let vector = layers[currentLayerIndex].cels[celIndex].vector
        else { return .unavailable }

        let registered = Set(animationGroups.map(\.id))
        guard !registered.isEmpty else { return .untagged }
        let elements = vector.elements
        guard elements.contains(where: { $0.animationGroupID.map(registered.contains) ?? false })
        else { return .untagged }

        let key = SelectionAnimationGroupMemo(
            pathObject: ObjectIdentifier(selection.path), bounds: selection.bounds,
            layerID: selection.layerID, celID: selection.celID, frame: currentFrame,
            vectorVersion: vector.version, membership: selectionMembership,
            registered: registered.count, answer: .unavailable)
        if let memo = selectionAnimationGroupMemo, memo.matches(key) { return memo.answer }

        let loops = CanvasManager.lassoLoops(
            vector.localPath(fromCanvas: selection.path).normalized(using: VectorCanvas.lassoFillRule),
            posedBy: celPoseMaps(elements, layerID: selection.layerID, celID: selection.celID,
                                 atFrame: currentFrame))
        let caught = vector.elementIDs(insideLoops: loops, membership: selectionMembership)
        var tags: Set<UUID> = []
        var untagged = false
        for element in elements where caught.contains(element.id) {
            if let group = element.animationGroupID, registered.contains(group) { tags.insert(group) }
            else { untagged = true }
        }
        let answer: SelectionAnimationGroup
        if tags.isEmpty { answer = .untagged }
        else if tags.count == 1, !untagged { answer = .one(tags.first!) }
        else { answer = .mixed }

        var stored = key
        stored.answer = answer
        selectionAnimationGroupMemo = stored
        return answer
    }

    /// The readout's own words — what `SelectPanel` puts on the control and what an XCUITest reads off
    /// it as a **value**, so a test cannot pass against a control that has stopped resolving anything.
    var selectionAnimationGroupName: String {
        switch selectionAnimationGroup {
        case .unavailable: return "—"
        case .untagged: return "No Group"
        case .mixed: return "Mixed"
        case .one(let id): return animationGroups.first { $0.id == id }?.displayName ?? "No Group"
        }
    }

    // MARK: - The write

    /// **One membership edit, as one undo step.**
    ///
    /// - Returns: whether the document changed. False for a refusal, for a loop that caught nothing,
    ///   and for an edit that asks for the group everything is already in.
    @discardableResult
    func setAnimationGroupOfSelection(_ assignment: AnimationGroupAssignment) -> Bool {
        let requested = selection
        // `commitAllInteractiveState`, not `beginCanvasEdit` — `recolorSelection`'s reason exactly: a
        // selection outlives a Move lift, so without settling the piece first this would rewrite the
        // geometry of a cel that is currently showing a hole and the float would bake its own copy of
        // that geometry over the top.
        commitAllInteractiveState()
        guard animationGroupEditUnavailableReason == nil,
              let selection = requested,
              layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].id == selection.layerID,
              let celIndex = activeCelIndex(inLayer: currentLayerIndex, atFrame: currentFrame),
              layers[currentLayerIndex].cels[celIndex].id == selection.celID,
              let vector = layers[currentLayerIndex].cels[celIndex].vector else { return false }
        let layerID = layers[currentLayerIndex].id
        let celID = layers[currentLayerIndex].cels[celIndex].id

        // Both preconditions `splitForLassoMove` states, and the per-element pull-back LASSO_MOVE.md
        // §5.27 rules: a lasso means what it means **on screen**, including on a frame where a pose
        // channel is showing the drawing somewhere other than where it is stored.
        let drawn = vector.localPath(fromCanvas: selection.path)
                          .normalized(using: VectorCanvas.lassoFillRule)
        let elementsBefore = vector.elements
        let loops = CanvasManager.lassoLoops(
            drawn, posedBy: celPoseMaps(elementsBefore, layerID: layerID, celID: celID,
                                        atFrame: currentFrame))

        // **The one branch the three rules cost**, `recolorSelection`'s verbatim: membership belongs to
        // the selection with no exception (LASSO_MOVE.md §5.26), and this is a fifth consumer of it
        // reading it through the same two doors. Under Cut a straddling stroke is split and only the
        // inside half changes group, which is what an artist asking for Cut has asked for.
        let membership = selectionMembership
        let working: [VectorElement]
        let caught: Set<UUID>
        if membership.cutsAtTheBoundary {
            guard let split = vector.splitForLassoMove(insideLoops: loops,
                                                       membership: membership) else { return false }
            working = split.elements
            caught = split.insideIDs
        } else {
            working = elementsBefore
            caught = vector.elementIDs(insideLoops: loops, membership: membership)
            guard !caught.isEmpty else {
                // §5.24 again, and through the same call: Enclosed catching nothing in a loop full of
                // ink says so, because there the rule excluded the ink rather than there being none.
                noteALassoThatCaughtNothing(vector: vector, loops: loops)
                return false
            }
        }

        let registered = Set(animationGroups.map(\.id))
        // **Minted as a value now and appended to the registry only at the end**, so a refusal below
        // cannot leave a group nothing is in and nothing can reach. Its id is a real destination
        // immediately — a fresh group has no track on this cel, so `resolvedPoseMap` answers the
        // identity for it, which is the correct compensation for joining a group that is not animated.
        let minted: AnimationGroup? = assignment == .newGroup
            ? AnimationGroup(displayName: "Group \(animationGroups.count + 1)",
                             tagColor: Self.animationGroupPalette[
                                 animationGroups.count % Self.animationGroupPalette.count])
            : nil
        let destination: UUID?
        switch assignment {
        case .none: destination = nil
        // A group the registry has lost is not a destination — `existingAnimationChannel`'s own guard,
        // and without it this would tag ink onto a channel nothing can name or animate.
        case .existing(let id): guard registered.contains(id) else { return false }; destination = id
        case .newGroup: destination = minted?.id
        }

        // Where the destination is showing its members right now. The identity for a removal, for a
        // group with no track on this cel, and for a track resting at this frame — all three of which
        // mean "there is nothing to compensate for".
        let into = destination.map {
            resolvedPoseMap(layerID: layerID, celID: celID, channel: .group($0), atFrame: currentFrame)
        } ?? .identity
        guard let intoInverse = into.inverse else {
            raise(.animationGroupEditRefused(.destinationIsFlatOnThisFrame))
            return false
        }

        var rewritten = working
        var changed = 0
        for (index, element) in working.enumerated() {
            guard caught.contains(element.id) else { continue }
            let was = element.animationGroupID.flatMap { registered.contains($0) ? $0 : nil }
            // Untagged ink asked for no group, or ink already in the destination: nothing to write, and
            // writing anyway would charge an undo step for an edit the artist cannot see. A freshly
            // minted group's id is never `was`, so this never skips a `newGroup`.
            guard was != destination else { continue }
            let from = was.map {
                resolvedPoseMap(layerID: layerID, celID: celID, channel: .group($0),
                                atFrame: currentFrame)
            } ?? .identity
            let compensation = from.concatenating(intoInverse)
            let tagged = element.taggedForAnimation(destination)
            if compensation.isIdentity {
                rewritten[index] = tagged
            } else {
                // **Nil is a refusal of the whole edit, not of one element.** It is a placed image or a
                // video under a projective compensation, and leaving that element behind at rest while
                // its neighbours travelled would be exactly the half-applied edit this verb must never
                // make. `distortUnavailableReason` refuses the same pair for the same reason one tier
                // over, and names the same way out.
                guard let moved = VectorCanvas.posing(tagged, through: compensation) else {
                    raise(.animationGroupEditRefused(.aPlacedImageCannotFollowAKeystone))
                    return false
                }
                rewritten[index] = moved
            }
            changed += 1
        }
        // Nothing to say, nothing recorded — and **under Cut this throws the split away too**, since
        // `rewritten` is a local list and nothing has been assigned to the canvas yet. A loop that
        // caught only ink already in the destination must not leave a cut behind.
        guard changed > 0 else { return false }

        // **The registry is only touched here**: every refusal above has passed, so a refused edit
        // cannot leave a group in it with nothing inside and no way to reach it.
        let groupsBefore = animationGroups
        if let minted { animationGroups.append(minted) }
        let groupsAfter = animationGroups

        // What the notice will say, read off the lists rather than re-derived later.
        let leaving = leavingGroupName(working, caught: caught, registered: registered)
        let arriving = minted?.displayName
            ?? destination.flatMap { id in animationGroups.first { $0.id == id }?.displayName }
        vector.elements = rewritten
        // **Not optional.** The `elements` setter deliberately does not invalidate, and both
        // `PixelOps.RasterizeKey` and `LayerContentVersion` key on `vectorVersion` — without this the
        // edit happens in the model and the compensated geometry never reaches the screen.
        vector.bumpVersion()
        // The transient tier, or a stale pre-edit fill preview composites over the top —
        // `recolorSelection` clears it for the same reason.
        setFillImage(layerIndex: currentLayerIndex, celIndex: celIndex, image: (nil as UIImage?))

        // **One record for both stores, and that is the requirement rather than tidiness.** Every key
        // on both tracks changes meaning the moment membership does, so an undo that put the geometry
        // back and left the tag — or the other way round — would leave a document whose drawing and
        // whose animation disagree. `StructureSnapshot` cannot be that record: it copies `layers` by
        // value and `Cel.vector` is a **class**, so it shares the live canvas and restores no element.
        recordUndo(label: .animationGroupMembership,
                   cost: VectorUndoCost.bytes(from: elementsBefore, to: rewritten),
                   undo: { [weak self] in
                       vector.elements = elementsBefore
                       vector.bumpVersion()
                       self?.animationGroups = groupsBefore
                       self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
                   }, redo: { [weak self] in
                       vector.elements = rewritten
                       vector.bumpVersion()
                       self?.animationGroups = groupsAfter
                       self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
                   })
        celContentChangedOutsideStroke(layerID: layerID, celID: celID)

        // **An action whose entire visible effect is that nothing moved has to say what it did.** That
        // is the whole design — appearance is preserved at this frame — so without a sentence the
        // artist taps a control and watches the canvas not change, which is indistinguishable from a
        // control that is broken. It is the *"a refusal with no notice"* defect wearing its positive
        // costume.
        raise(.animationGroupMembershipChanged(edit(leaving: leaving, arriving: arriving)))
        refreshUndoRedoState()
        return true
    }

    /// The name of the group the caught ink is leaving, or nil when it is leaving none. Nil for a
    /// mixture too: *"Moved out of two groups"* is not a sentence the notice can act on, and the
    /// arriving half is the half the artist needs.
    private func leavingGroupName(_ elements: [VectorElement], caught: Set<UUID>,
                                  registered: Set<UUID>) -> String? {
        var tags: Set<UUID> = []
        for element in elements where caught.contains(element.id) {
            if let group = element.animationGroupID, registered.contains(group) { tags.insert(group) }
        }
        guard tags.count == 1, let id = tags.first else { return nil }
        return animationGroups.first { $0.id == id }?.displayName
    }

    private func edit(leaving: String?, arriving: String?) -> CanvasNotice.AnimationGroupEdit {
        switch (leaving, arriving) {
        case (let from?, let to?) where from != to: return .moved(from: from, to: to)
        case (_, let to?): return .joined(to)
        case (let from?, nil): return .left(from)
        case (nil, nil): return .left("its animation group")
        }
    }
}

private extension SelectionAnimationGroupMemo {
    /// Every field but the answer — so a hit is a key comparison and never a comparison against the
    /// thing being looked up.
    func matches(_ other: SelectionAnimationGroupMemo) -> Bool {
        pathObject == other.pathObject && bounds == other.bounds && layerID == other.layerID
            && celID == other.celID && frame == other.frame && vectorVersion == other.vectorVersion
            && membership == other.membership && registered == other.registered
    }
}
