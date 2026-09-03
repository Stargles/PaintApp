import CoreGraphics
import Foundation

/// **Writing the transform channel** — KEYFRAMES.md §2.5's *"a transform key stores a pose, and it is
/// written at commit"*, routed through the same five arms every other channel obeys.
///
/// ## The routing is `KeyframeControl.write`, unchanged, and that is the point
///
/// §2.27 settled where one *slider* edit goes as a function of where the playhead stands relative to
/// the target's keyframes. A Move is the transform channel's slider, so it asks the identical
/// question and takes the identical five answers. Nothing here re-derives the rule; it supplies the
/// four inputs and carries out each arm in the pose channel's own currency.
///
/// Three of the four inputs are read the same way. The fourth, `channelHasCurve`, asks whether this
/// cel's channel carries a `TransformTrack` at all — the **loose** predicate, never
/// `TransformTrack.isAnimated`, for §2.23's surviving reason: a track whose two keys hold equal poses
/// is still in force, so a Move routed to the geometry instead would be overwritten by the track at
/// every frame it is consulted at, and the artist would watch their drawing spring back.
///
/// ## What each arm does, and the one asymmetry with a value channel
///
/// A value channel's `.storedValue` and `.storedValueHoldingBaseline` arms both *write the number*.
/// A pose channel's stored base is the cel's geometry (`CanvasManager.CelPoseState` says why), so
/// "write the base" is the ordinary bake `applyToVectorFloat` has always done — already on the undo
/// stack, one step per nudge, by the time this is reached. So:
///
///  * **`.storedValue`** — no keyframes anywhere. Nothing happens. A document nobody has keyframed
///    behaves exactly as it did before this feature existed, which is the safety property the whole
///    routing rule is shaped around.
///  * **`.storedValueHoldingBaseline`** — the bake stands, and the baseline records the pose that
///    puts the drawing back where it *was*, i.e. the inverse of the map just applied. The next
///    keyframe press commits it onto the neighbouring mark.
///  * **`.seedAndKey`** — the bake stands, the inverse goes onto the neighbouring keyframes, and the
///    identity is keyed here. Both halves in one write, because standing on a keyframe there is no
///    third press coming to commit a baseline.
///  * **`.key`** — the channel is already animated, so the bake must be **taken back**: the cel holds
///    one drawing in its rest position and the keys hold the poses (§2.5). The rest display list is
///    restored and the map is keyed at the playhead, as one undo step.
///
/// ## Why `.key` is only ever reached at a frame whose pose is the identity
///
/// The Move box is measured on the cel's **stored** ink (`MoveBoxInk(of: lift.elements)`), while a
/// posed cel shows a derived picture. Where the two disagree the artist would be dragging a box that
/// is not around the drawing they can see — which is the same mismatch that already makes Move refuse
/// an interpolated cel outright, in two places. So `activeVectorMoveTarget` refuses a Move at a frame
/// whose pose is not resting, and `.key`'s write is therefore composing the new map with the identity
/// rather than with an arbitrary pose. Posing the float itself — which is what would lift that
/// refusal — is named as the next stage's work rather than half-built here.
extension CanvasManager {

    // MARK: - Reading

    /// **Whether this cel shows its ink where it stores it at `frame`** — the predicate the Move
    /// refusal and the `.key` arm both lean on. True for every cel in a document with no pose
    /// channels, which is the fast path every caller takes.
    func celPoseIsResting(layerIndex: Int, celIndex: Int, atFrame frame: Int) -> Bool {
        guard layers.indices.contains(layerIndex),
              layers[layerIndex].cels.indices.contains(celIndex) else { return true }
        let cel = layers[layerIndex].cels[celIndex]
        guard !cel.transformTracks.isEmpty else { return true }
        return Self.poseIsResting(cel.transformTracks, atCelLocalFrame: frame - cel.startFrame)
    }

    /// **The frames a layer's pose channels hold keys on, in absolute document frames** — what
    /// §2.28's union folds in beside the layer's marks and its grade's curve keys.
    ///
    /// **Cel-local keys converted here rather than stored absolute**, §3.1: the track rides its cel
    /// through move, split and duplicate precisely because it does not know where the cel starts, and
    /// the one place that has to know is the one that draws the timeline.
    ///
    /// The `transformTracks.isEmpty` test per cel is what keeps this affordable from a SwiftUI body —
    /// it is asked on every layout pass of every layer.
    func poseKeyframeFrames(inLayer id: UUID) -> [Int] {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return [] }
        var frames: Set<Int> = []
        for cel in layers[index].cels where !cel.transformTracks.isEmpty {
            for track in cel.transformTracks.values {
                for key in track.keys { frames.insert(cel.startFrame + key.frame) }
            }
        }
        return frames.sorted()
    }

    // MARK: - Writing one key

    /// **Inserts or replaces one channel's pose key on one cel-local frame**, as one undo step.
    ///
    /// - Returns: whether the document changed. A key identical to the one already there is not a
    ///   change and records nothing, so a second commit on an unmoved playhead costs no undo press.
    @discardableResult
    func setTransformPoseKey(layerID: UUID, celID: UUID, channel: TransformChannelID,
                             atCelLocalFrame frame: Int, pose: PoseQuad,
                             label: HistoryActionLabel = .effectKeyframes) -> Bool {
        let before = celPoseState(layerID: layerID, celID: celID)
        var state = before
        var track = state.tracks[channel.id] ?? TransformTrack()
        track.setKey(TransformTrack.Key(frame: frame, pose: pose))
        state.tracks[channel.id] = track
        // A channel that lands a key no longer needs its held pose.
        state.baselines.removeValue(forKey: channel.id)
        guard state != before else { return false }
        commitCelPoseState(state, from: before, layerID: layerID, celID: celID, label: label)
        return true
    }

    /// **Records the pose a channel held before this move** — `.storedValueHoldingBaseline`'s half,
    /// and §2.27's *"the previous value is held"*.
    ///
    /// **Written once per channel per keyframe cycle.** The first Move after a mark is the only one
    /// that knows where the drawing was at A; a later one measures from geometry this arm has already
    /// baked, so overwriting would replace the true baseline with a position the artist never sat on.
    /// An existing entry is kept and the call is free — `holdBaseline`'s rule, restated for a pose.
    ///
    /// **Records no undo step *of its own*, and instead folds itself into the one the Move already
    /// made.** One Move is one press of Undo (LASSO_MOVE.md §5.5), and this write arrives after that
    /// press has been recorded, so `UndoHistory.extendLast` is what puts the two on one entry.
    ///
    /// **The half of `holdBaseline`'s argument that is false here is what makes that necessary.** That
    /// function may record nothing because *"the bake it rides beside is already a step that snapshots
    /// the cel"* — true for a value channel, whose call sites sit inside a bracket that has already
    /// snapshotted `layers` and `folders` wholesale. A pose baseline's neighbour is
    /// `registerVectorFloatNudgeUndo`, which restores `vector.elements`, `float.frame.*` and
    /// `selection` **and nothing on the `Cel`** — so this field was outside every closure that could
    /// have given it back. The symptom was exact and silent: Move between two marks, press Undo, watch
    /// the drawing return, and a later keyframe press then seeds an animation out of a baseline
    /// describing a move that no longer exists.
    ///
    /// **Nothing is folded when a bracket is already open** (`structureUndoDepth`, `gestureSnapshot`),
    /// which is `commitCelPoseState`'s guard and for its reason: the enclosing step restores the cel
    /// wholesale, and extending an entry that is not this gesture's would attach the baseline to a
    /// stranger.
    @discardableResult
    func holdPoseBaseline(layerID: UUID, celID: UUID, channel: TransformChannelID,
                          pose: PoseQuad) -> Bool {
        let before = celPoseState(layerID: layerID, celID: celID)
        guard before.baselines[channel.id] == nil else { return false }
        var state = before
        state.baselines[channel.id] = pose
        applyCelPoseState(state, layerID: layerID, celID: celID)

        guard structureUndoDepth == 0, gestureSnapshot == nil else { return true }
        history.extendLast(cost: 160,
                           undo: { [weak self] in
                               self?.applyCelPoseState(before, layerID: layerID, celID: celID)
                           }, redo: { [weak self] in
                               self?.applyCelPoseState(state, layerID: layerID, celID: celID)
                           })
        refreshUndoRedoState()
        return true
    }

    /// **Creates a pose channel from nothing with the old pose on its neighbouring keyframes and the
    /// new one at the playhead** — `.seedAndKey`, and §2.27's *"modifies another slider while on B"*.
    ///
    /// **Only the immediate neighbours are seeded**, `seedAndKeyChannel`'s rule and for its reason:
    /// `TransformTrack` extrapolates as a constant hold outside its first and last key, so a pose
    /// placed on the nearest keyframe below already holds at every one below that. Fewer keys, same
    /// animation, and no handles on frames the artist never touched.
    @discardableResult
    func seedAndKeyPose(layerID: UUID, celID: UUID, channel: TransformChannelID,
                        oldPose: PoseQuad, newPose: PoseQuad,
                        atCelLocalFrame frame: Int, keyframes: [Int]) -> Bool {
        let before = celPoseState(layerID: layerID, celID: celID)
        var state = before
        var track = state.tracks[channel.id] ?? TransformTrack()
        if let below = keyframes.last(where: { $0 < frame }), track.key(atFrame: below) == nil {
            track.setKey(TransformTrack.Key(frame: below, pose: oldPose))
        }
        if let above = keyframes.first(where: { $0 > frame }), track.key(atFrame: above) == nil {
            track.setKey(TransformTrack.Key(frame: above, pose: oldPose))
        }
        track.setKey(TransformTrack.Key(frame: frame, pose: newPose))
        state.tracks[channel.id] = track
        state.baselines.removeValue(forKey: channel.id)
        guard state != before else { return false }
        commitCelPoseState(state, from: before, layerID: layerID, celID: celID, label: .effectKeyframes)
        return true
    }

    /// **Drops every pose key and held baseline in a half-open range of *absolute* frames** — the
    /// pose half of `removeKeyframe` and `clearKeyframes`, applied to every cel of one layer.
    ///
    /// The range is absolute and each cel converts it, which is the same conversion
    /// `poseKeyframeFrames` makes in the other direction and the only place either happens.
    ///
    /// Mutates in place without recording; the caller's bracket is what makes it one step. A channel
    /// left with no keys is removed rather than stored empty — `setEffectParameterTrack`'s rule, and
    /// the state that would otherwise sit in the channel list animating nothing.
    ///
    /// - Returns: whether anything changed.
    @discardableResult
    func clearPoseKeys(inLayer index: Int, absoluteFrames frames: Range<Int>) -> Bool {
        guard layers.indices.contains(index) else { return false }
        var changed = false
        for celIndex in layers[index].cels.indices {
            let cel = layers[index].cels[celIndex]
            guard !cel.transformTracks.isEmpty || !cel.pendingPoseBaselines.isEmpty else { continue }
            var tracks = cel.transformTracks
            for (id, track) in tracks {
                var trimmed = track
                for frame in frames { trimmed.removeKey(atFrame: frame - cel.startFrame) }
                if trimmed.isEmpty { tracks.removeValue(forKey: id) } else { tracks[id] = trimmed }
            }
            guard tracks != cel.transformTracks else { continue }
            layers[index].cels[celIndex].transformTracks = tracks
            // A channel whose keys are gone has nothing left for a baseline to be committed onto.
            layers[index].cels[celIndex].pendingPoseBaselines =
                cel.pendingPoseBaselines.filter { tracks[$0.key] != nil }
            changed = true
        }
        return changed
    }

    // MARK: - The commit

    /// **Where a committed Move would go**, with `KeyframeControl.write`'s four inputs read off the
    /// model — the pose twin of `keyframeWrite(_:parameter:atFrame:)`.
    ///
    /// `channel` may be nil, meaning "a group would have to be minted": a channel that does not exist
    /// yet has no track, so `channelHasCurve` is false and the answer is the same one the minted
    /// channel will get. That is what lets the caller ask before it creates anything.
    func transformWrite(layerID: UUID, celID: UUID, channel: TransformChannelID?,
                        atFrame frame: Int) -> KeyframeControl.Write {
        guard let at = celIndices(forCel: celID, inLayer: layerID),
              let target = keyframeTarget(layerIndex: at.layer)
        else { return .storedValue }
        let cel = layers[at.layer].cels[at.cel]
        guard cel.interpolation == nil else { return .storedValue }
        let placed = keyframeFrames(of: target)
        return KeyframeControl.write(
            // A pose is not a scalar, and this input is not asking whether it is: it is the refusal
            // gate for the nine stepped, array and colour *effect* parameters, and a transform channel
            // is none of them. `TransformTrack` stores and renders every pose it can hold.
            isScalarAnimatable: true,
            channelHasCurve: channel.flatMap { cel.transformTracks[$0.id] }?.isEmpty == false,
            keyframeCount: placed.count,
            playheadIsOnKeyframe: placed.contains(frame))
    }

    /// **One committed Move, routed** — §2.5's write-at-commit, and the whole of the transform
    /// channel's authoring path.
    ///
    /// `restBox` is the box the pose is measured against and `map` is the canvas-space affine the
    /// gesture applied to the ink inside it. `restElements` is the display list as it stood *before*
    /// the lift, which the `.key` arm restores.
    ///
    /// - Returns: the arm taken, so the caller can decide whether it still owes a bake. `.storedValue`
    ///   means "this was an ordinary Move; leave everything alone".
    @discardableResult
    func commitTransformPose(layerID: UUID, celID: UUID, channel: TransformChannelID,
                             restBox: CGRect, map: CGAffineTransform,
                             restElements: [VectorElement],
                             atFrame frame: Int) -> KeyframeControl.Write {
        guard let at = celIndices(forCel: celID, inLayer: layerID),
              let target = keyframeTarget(layerIndex: at.layer)
        else { return .storedValue }
        let cel = layers[at.layer].cels[at.cel]
        // §2.18: a derived in-between has no stable elements to key, so it takes no object channel and
        // the writer refuses rather than leaving storage that renders nothing.
        guard cel.interpolation == nil else { return .storedValue }

        let placed = keyframeFrames(of: target)
        let route = transformWrite(layerID: layerID, celID: celID, channel: channel, atFrame: frame)

        guard route != .storedValue else { return .storedValue }
        guard let inverse = invertedIfPossible(map) else { return .storedValue }
        let local = frame - cel.startFrame
        // Where the drawing *was*, expressed against the geometry as it now stands. `restBox` is only
        // a reference frame — `Homography(rect:to:)` recovers the same affine from any non-degenerate
        // one — so using the pre-move box keeps the number the artist can reason about.
        let wasAt = PoseQuad(box: restBox, mappedBy: inverse)
        let resting = PoseQuad(restingIn: restBox)

        switch route {
        case .storedValue:
            return .storedValue

        case .storedValueHoldingBaseline:
            holdPoseBaseline(layerID: layerID, celID: celID, channel: channel, pose: wasAt)

        case .seedAndKey:
            let localKeyframes = placed.map { $0 - cel.startFrame }
            seedAndKeyPose(layerID: layerID, celID: celID, channel: channel,
                           oldPose: wasAt, newPose: resting,
                           atCelLocalFrame: local, keyframes: localKeyframes)

        case .key:
            // The one arm that takes the bake back: the cel holds one drawing in its rest position and
            // the keys hold the poses. Both halves in one step, so an undo cannot leave the geometry
            // restored and the key written.
            keyPoseRestoringRest(layerID: layerID, celID: celID, channel: channel,
                                 atCelLocalFrame: local,
                                 pose: PoseQuad(box: restBox, mappedBy: map),
                                 restElements: restElements)
        }
        return route
    }

    /// `.key`'s write: the rest display list and the pose key, as **one** undo step.
    ///
    /// Two things move here and they cannot be two steps. The elements live on a `VectorCanvas`, which
    /// is a reference type, so the closure swaps its display list directly — the shape
    /// `registerVectorFloatNudgeUndo` already uses, and the reason it captures the canvas rather than
    /// an index.
    private func keyPoseRestoringRest(layerID: UUID, celID: UUID, channel: TransformChannelID,
                                      atCelLocalFrame frame: Int, pose: PoseQuad,
                                      restElements: [VectorElement]) {
        guard let at = celIndices(forCel: celID, inLayer: layerID),
              let vector = layers[at.layer].cels[at.cel].vector else { return }
        let before = celPoseState(layerID: layerID, celID: celID)
        var state = before
        var track = state.tracks[channel.id] ?? TransformTrack()
        track.setKey(TransformTrack.Key(frame: frame, pose: pose))
        state.tracks[channel.id] = track
        state.baselines.removeValue(forKey: channel.id)

        let movedElements = vector.elements
        beginCanvasEdit()
        vector.elements = restElements
        vector.bumpVersion()
        applyCelPoseState(state, layerID: layerID, celID: celID)
        celContentChangedOutsideStroke(layerID: layerID, celID: celID)

        guard structureUndoDepth == 0, gestureSnapshot == nil else { return }
        recordUndo(label: .effectKeyframes,
                   cost: (movedElements.count + restElements.count) * 512,
                   undo: { [weak self] in
                       vector.elements = movedElements
                       vector.bumpVersion()
                       self?.applyCelPoseState(before, layerID: layerID, celID: celID)
                       self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
                   }, redo: { [weak self] in
                       vector.elements = restElements
                       vector.bumpVersion()
                       self?.applyCelPoseState(state, layerID: layerID, celID: celID)
                       self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
                   })
    }

    // MARK: - Groups

    /// **Which channel a committed Move would write, without creating anything.**
    ///
    /// A Move that carries every element on the cel is the `.cel` channel — the owner's screenshake,
    /// and what Move with no selection already does. Anything narrower is a group, because the frames
    /// either side of this one have to know *which* elements travelled, and §3.4 rules that the only
    /// thing surviving a lasso lift (fresh ids on both pieces) and a reload (an image's id is
    /// re-minted) is a **field on the element**.
    ///
    /// Nil means "a group would have to be minted for this". **Asking without minting is the whole
    /// reason this is two functions**: the route is computed from this answer, and a document with no
    /// keyframes takes the `.storedValue` arm — so minting first would tag ink and add a group to
    /// every ordinary Move ever made, which is precisely the "nothing changes until you keyframe"
    /// property the routing rule exists to protect.
    func existingAnimationChannel(forMovedElementIDs moved: Set<UUID>, layerID: UUID,
                                  celID: UUID) -> TransformChannelID? {
        guard let at = celIndices(forCel: celID, inLayer: layerID),
              let vector = layers[at.layer].cels[at.cel].vector else { return nil }
        let elements = vector.elements
        guard !moved.isEmpty, !elements.isEmpty else { return nil }
        if moved.count >= elements.count, elements.allSatisfy({ moved.contains($0.id) }) { return .cel }

        let carried = elements.filter { moved.contains($0.id) }
        guard !carried.isEmpty else { return nil }
        // Reused only when *every* carried element already shares one group, so re-moving the same
        // piece extends its channel instead of minting a second one over the same ink; a mixed
        // selection mints a fresh group rather than silently joining one of them.
        let tags = Set(carried.map(\.animationGroupID))
        guard tags.count == 1, let existing = tags.first, let id = existing,
              animationGroups.contains(where: { $0.id == id }) else { return nil }
        return .group(id)
    }

    /// **Mints a group over the carried elements and tags them** — the writing half of the pair above,
    /// called only once the route has said a key is actually going to be written.
    ///
    /// The tag is written onto `vector.elements` directly rather than through an undo record of its
    /// own: it travels with the pose write in the same commit, and the arm that restores rest geometry
    /// (`.key`) is never the arm that mints, because a channel with a track already has its group.
    @discardableResult
    func mintAnimationChannel(forMovedElementIDs moved: Set<UUID>, layerID: UUID,
                              celID: UUID) -> TransformChannelID? {
        guard let at = celIndices(forCel: celID, inLayer: layerID),
              let vector = layers[at.layer].cels[at.cel].vector else { return nil }
        let elements = vector.elements
        guard !moved.isEmpty, elements.contains(where: { moved.contains($0.id) }) else { return nil }

        let group = AnimationGroup(displayName: "Group \(animationGroups.count + 1)",
                                   tagColor: Self.animationGroupPalette[
                                       animationGroups.count % Self.animationGroupPalette.count])
        animationGroups.append(group)
        vector.elements = elements.map {
            moved.contains($0.id) ? $0.taggedForAnimation(group.id) : $0
        }
        vector.bumpVersion()
        return .group(group.id)
    }

    /// Tag colours for freshly minted animation groups, cycled by creation order. Hand-picked for
    /// `TimelineGraphBand`'s reason — a generated palette cannot be told that ~211° is the playhead
    /// and ~48° is an interpolation reference (§2.8).
    static let animationGroupPalette: [CodableColor] = [
        CodableColor(red: 0.20, green: 0.65, blue: 1.00, alpha: 1),
        CodableColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 1),
        CodableColor(red: 0.35, green: 0.80, blue: 0.40, alpha: 1),
        CodableColor(red: 0.85, green: 0.35, blue: 0.75, alpha: 1)
    ]

    // MARK: - Shared machinery

    /// Applies a new pose state and records the one undo step that takes it back — the pose twin of
    /// `commitKeyframeState`, and deliberately not `withStructureUndo` for its reason: that bracket
    /// snapshots `layers`, `folders`, `viewPresets`, `motionGroups` and `guideStrokes` twice at a
    /// declared cost of 4096, which is the right price for a structural pick and the wrong one for a
    /// channel edit.
    private func commitCelPoseState(_ state: CelPoseState, from before: CelPoseState,
                                    layerID: UUID, celID: UUID, label: HistoryActionLabel) {
        beginCanvasEdit()
        applyCelPoseState(state, layerID: layerID, celID: celID)
        celContentChangedOutsideStroke(layerID: layerID, celID: celID)

        guard structureUndoDepth == 0, gestureSnapshot == nil else { return }
        recordUndo(label: label,
                   cost: Self.poseStateUndoCost(before) + Self.poseStateUndoCost(state),
                   undo: { [weak self] in
                       self?.applyCelPoseState(before, layerID: layerID, celID: celID)
                       self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
                   }, redo: { [weak self] in
                       self?.applyCelPoseState(state, layerID: layerID, celID: celID)
                       self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
                   })
    }

    /// The same small estimate `KeyframeControl.stateUndoCost` makes, in pose currency: a key is a
    /// rect, eight coordinates and four handle numbers. What matters is that it is *small*, so a
    /// session that keyframes heavily costs the history what a couple of structural edits do.
    private static func poseStateUndoCost(_ state: CelPoseState) -> Int {
        state.tracks.values.reduce(0) { $0 + 64 + 160 * $1.keys.count } + 160 * state.baselines.count
    }

    /// `map` inverted, or nil for a singular or non-finite one. A Move whose map cannot be inverted
    /// has collapsed the drawing to a line, which `ObjectTransformDrag` already refuses one level up;
    /// answering nil here routes the commit to `.storedValue` and leaves the bake alone rather than
    /// writing a key that says nothing.
    private func invertedIfPossible(_ map: CGAffineTransform) -> CGAffineTransform? {
        let determinant = map.a * map.d - map.b * map.c
        guard determinant.isFinite, abs(determinant) > Quad.epsilon else { return nil }
        let inverse = map.inverted()
        guard inverse.a.isFinite, inverse.b.isFinite, inverse.c.isFinite,
              inverse.d.isFinite, inverse.tx.isFinite, inverse.ty.isFinite else { return nil }
        return inverse
    }
}
