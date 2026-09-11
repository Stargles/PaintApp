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
/// ## `.key` at a frame that is already posed, and what `map` has to be by the time it arrives
///
/// Until 2026-09-03 `activeVectorMoveTarget` refused a Move at any frame whose pose was not resting,
/// so this arm only ever composed the new map with the identity. That refusal is gone — it was the
/// owner's *"try to select it in an inbetween, it does not let you"* — and `.key` is now reached at
/// frames where the channel is mapping the drawing somewhere.
///
/// **Nothing in this file changed for it, and that is deliberate.** A Move's `map` is a delta in the
/// space the artist was looking at, and a key is a map out of rest space; the two differ by the
/// channel's own current pose and by whatever is applied *after* it. `commitPoseFromFloat` does that
/// composition (`M · O · D · O⁻¹`) and hands the result in, so this file keeps taking one affine and
/// keeps meaning one thing by it — and the inverse it takes for a held baseline or a seeded neighbour
/// comes out right for free, because those arms are only reached when the channel has no curve and
/// `M` is therefore the identity.
extension CanvasManager {

    // MARK: - Reading

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
        // **The container's own channel, and it needs no conversion** — §3.1: `LayerPose.track` keys
        // in *absolute document frames* because a transformation layer has no cel to ride.
        //
        // **It was missing until §11.7 and the divergence it left is exactly §2.28's.** The
        // transformation layer landed with `Layer.transform` animated by a `TransformTrack`, and this
        // funnel folded only the cels' — so a key on a transformation layer drew a node in the graph
        // editor with no keyframe indicator on the track beside it, which is the same report §2.28
        // was written from, arriving through the third door.
        //
        // **`layerTransform`, not `transform`**, which is `storedEffect(of:)`'s asymmetry one payload
        // over: a `.raster` layer carrying a pose left behind by a kind change poses nothing, so a
        // marker for it would claim a keyframe for an animation the canvas is not running.
        if let track = layers[index].layerTransform?.track {
            frames.formUnion(track.keyedFrames)
        }
        return frames.sorted()
    }

    /// **The same for a folder's own pose** — §2.21's twin, absolute frames, no cel conversion.
    ///
    /// A folder holds no cels, so this is the *whole* of a folder target's pose contribution; there
    /// is no kind gate because a folder has no kinds.
    func poseKeyframeFrames(inFolder id: UUID) -> [Int] {
        guard let track = folders.first(where: { $0.id == id })?.transform?.track else { return [] }
        return track.keyedFrames.sorted()
    }

    // MARK: - Raising the Move box from the channel list — KEYFRAMES.md §11.7

    /// **What a click on a channel list row does** — the owner's *"clicking on a move item in there
    /// should bring up the move box for that move item so you don't need to select it manually
    /// again."*
    ///
    /// One line, because every decision in it is somewhere else: which channel a row names is
    /// `PoseChannelID.resolve(parameterID:)`, whether it has a box to raise is
    /// `PoseChannelID.raisesMoveBox`, and raising it is `beginVectorChannelMove(_:)`. It is here
    /// rather than in `Views/AnimationTimeline.swift` for that file's founding reason — it is not
    /// compiled into `PaintSoftwareUITests`, so a rule written there is pinned by nothing.
    ///
    /// - Returns: whether a box came up. False for a channel whose ink is not on the cel under the
    ///   playhead, and — for a container pose — when the band's layer is not a transformation layer,
    ///   which is the case a stale filter can still name.
    @discardableResult
    func revealPoseChannel(_ channel: PoseChannelID) -> Bool {
        guard channel.raisesMoveBox else { return false }
        switch channel {
        case .cel(let id): return beginVectorChannelMove(id)
        // **`.container` used to return false here**, and the note on `raisesMoveBox` said the day a
        // Move on a transformation layer existed *"this returns true and nothing else changes"*. It
        // is that day; this arm is the one thing that did change, because the box a container pose
        // raises is not a vector float and so cannot go through `beginVectorChannelMove`.
        case .container: return beginContainerPoseMove()
        }
    }

    // MARK: - Deleting and adding one pose node from the graph editor — TODO (21)

    /// **Delete one pose node from the graph editor** — TODO (21)'s "still refused for want of a
    /// writer": the node menu's Delete funnelled through `removeEffectParameterKey`, a grade writer
    /// that drops a pose id outright, and a `TransformTrack.Key` needed a writer of its own.
    ///
    /// **The whole key goes, never one component**, because there is no partial version of it to
    /// delete: all six of the band's rows for one pose channel are decomposed from one
    /// `TransformTrack.Key` at that frame (`poseChannels`' "six rows, one key"), so whichever row the
    /// artist tapped, the node names a frame and a channel and the channel's *track* holds the key.
    ///
    /// **Resolved by trying every source that could own the frame, exactly as
    /// `writeGraphBandPoseEdits` already does for a drag.** A layer's cels contribute disjoint
    /// absolute spans to one merged channel (`poseChannels`' merging note), so at most one cel's
    /// track ever has a key at a given absolute frame, and asking each in turn needs no separate
    /// "which cel" lookup of its own.
    ///
    /// - Returns: whether the document changed. False for a frame the channel does not key, which is
    ///   the state a menu left up while an undo removed the node underneath it reaches — the same
    ///   guard `removeEffectParameterKey` states for the grade side.
    @discardableResult
    func removePoseChannelKey(layerIndex: Int, parameterID: String, frame: Int) -> Bool {
        guard layers.indices.contains(layerIndex),
              let (channel, _) = PoseChannelID.resolve(parameterID: parameterID)
        else { return false }
        let layerID = layers[layerIndex].id
        switch channel {
        case .container:
            guard let before = layers[layerIndex].layerTransform, before.track.key(atFrame: frame) != nil
            else { return false }
            var after = before
            after.track.removeKey(atFrame: frame)
            writeContainerPose(after, from: before, target: .layer(id: layerID), label: .removeKeyframe)
            return true
        case .cel(let id):
            for cel in layers[layerIndex].cels {
                let local = frame - cel.startFrame
                guard cel.transformTracks[id.id]?.key(atFrame: local) != nil else { continue }
                return removeTransformPoseKey(layerID: layerID, celID: cel.id, channel: id,
                                              atCelLocalFrame: local)
            }
            return false
        }
    }

    /// **Add one pose node from the graph editor's tap-to-add gesture** — TODO (21)'s other half of
    /// "still refused for want of a writer", and the ruling its doc named as still owed: tapping a
    /// curve to add a key "would have to invent the five component values the artist never gave."
    ///
    /// **They are not invented — they hold exactly what the track already resolves to at this
    /// frame**, never re-derived and never reset to rest. That is not a new rule, only this rule's
    /// second use: it is `addKeyframe`'s own step 3, *"hold this pose here"*, and `PoseEdit`'s own
    /// rule for a drag — *"only what moved is listed … the five it did not name are carried"* —
    /// applied to a gesture that creates a key instead of moving one. An artist who taps one row's
    /// line sees every other row's animation exactly as it was reading a moment before the tap.
    ///
    /// **Refused where there is no pose to resolve, or where it is projective.** A pose channel is
    /// only ever drawn for a non-empty track (`poseChannels` skips an empty one outright), so this
    /// mainly declines a pose that `PoseComponents.setting` cannot decompose — the same case
    /// `decompose` declines the whole channel for in the band.
    ///
    /// - Returns: whether the document changed.
    @discardableResult
    func addPoseChannelKey(layerIndex: Int, parameterID: String, frame: Int, value: Double) -> Bool {
        guard layers.indices.contains(layerIndex),
              let (channel, component) = PoseChannelID.resolve(parameterID: parameterID)
        else { return false }
        let layerID = layers[layerIndex].id
        switch channel {
        case .container:
            guard let before = layers[layerIndex].layerTransform,
                  let resolved = before.track.pose(atDocumentFrame: frame),
                  let posed = PoseComponents.setting(component, to: value, of: resolved)
            else { return false }
            var after = before
            after.track.setKey(TransformTrack.Key(frame: frame, pose: posed))
            writeContainerPose(after, from: before, target: .layer(id: layerID), label: .addKeyframe)
            return true
        case .cel(let id):
            for cel in layers[layerIndex].cels {
                let local = frame - cel.startFrame
                guard local >= 0, local < cel.frameCount,
                      let track = cel.transformTracks[id.id],
                      let resolved = track.pose(atCelLocalFrame: local),
                      let posed = PoseComponents.setting(component, to: value, of: resolved)
                else { continue }
                return setTransformPoseKey(layerID: layerID, celID: cel.id, channel: id,
                                           atCelLocalFrame: local, pose: posed, label: .addKeyframe)
            }
            return false
        }
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

    /// **`setTransformPoseKey`'s inverse: drops one channel's key on one cel-local frame**, as one
    /// undo step — the writer `removePoseChannelKey` needed and did not have, TODO (21).
    ///
    /// **A channel left with no keys is removed rather than stored empty**, `clearKeyframes`'s rule
    /// on the same payload one door over: an empty `TransformTrack` left in the dictionary is a
    /// channel the graph editor would still list and draw as a flat, unkeyed line.
    ///
    /// - Returns: whether the document changed. False for a frame the channel does not key.
    @discardableResult
    func removeTransformPoseKey(layerID: UUID, celID: UUID, channel: TransformChannelID,
                                atCelLocalFrame frame: Int,
                                label: HistoryActionLabel = .removeKeyframe) -> Bool {
        let before = celPoseState(layerID: layerID, celID: celID)
        var state = before
        guard var track = state.tracks[channel.id], track.key(atFrame: frame) != nil else { return false }
        track.removeKey(atFrame: frame)
        if track.isEmpty {
            state.tracks.removeValue(forKey: channel.id)
        } else {
            state.tracks[channel.id] = track
        }
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
    ///
    /// **And only neighbours inside this cel's span** — TODO (62): a key never lives outside
    /// `0..<frameCount`. The layer's keyframes are the layer's, so the nearest one below or above the
    /// playhead can sit on another block or on no block at all, and until 2026-09-11 it was seeded
    /// here regardless: a mark at 15 seeded a key at cel-local 15 on a ten-frame cel, and a mark at 5
    /// seeded one at -5 on the block starting at 10. Both were outside the span the moment they were
    /// written, and the next span change cropped them with a banner naming a frame the artist never
    /// keyed on that block. A neighbour past the cel's edge is not seeded; the pose holds from the
    /// new key to the edge, which is what `TransformTrack`'s constant extrapolation does anyway.
    @discardableResult
    func seedAndKeyPose(layerID: UUID, celID: UUID, channel: TransformChannelID,
                        oldPose: PoseQuad, newPose: PoseQuad,
                        atCelLocalFrame frame: Int, keyframes: [Int]) -> Bool {
        let before = celPoseState(layerID: layerID, celID: celID)
        var state = before
        var track = state.tracks[channel.id] ?? TransformTrack()
        let span = celIndices(forCel: celID, inLayer: layerID)
            .map { 0..<layers[$0.layer].cels[$0.cel].frameCount } ?? 0..<Int.max
        let keyframes = keyframes.filter { span.contains($0) }
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
    /// `restBox` is the box the pose is measured against and `map` is the canvas-space map the
    /// gesture applied to the ink inside it. `restElements` is the display list as it stood *before*
    /// the lift, which the `.key` arm restores, and `movedIDs` are the ids the gesture moved under
    /// their own id — what the `.key` arm's swap may find rewritten (TODO (41)), which is the
    /// float's `insideIDs`. Over-declaring costs a larger rectangle; under-declaring is a wrong
    /// picture; an empty set is right only when `restElements` and the standing list hold the same
    /// content under every shared id.
    ///
    /// **`map` is a `PoseMap` since KEYFRAMES.md §8 stage 5b**, so a Distort's keystone reaches the
    /// key rather than being flattened to its affine part on the way in. Every arm below is written
    /// against `PoseQuad`, which has held four free corners since stage 5 (§2.14, *"from day one"*) —
    /// so this is one initialiser and an inverse that answers a `PoseMap`, and no storage changed.
    ///
    /// - Returns: the arm taken, so the caller can decide whether it still owes a bake. `.storedValue`
    ///   means "this was an ordinary Move; leave everything alone".
    @discardableResult
    func commitTransformPose(layerID: UUID, celID: UUID, channel: TransformChannelID,
                             restBox: CGRect, map: PoseMap,
                             restElements: [VectorElement], movedIDs: Set<UUID>,
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
        guard let inverse = map.inverse else { return .storedValue }
        let local = frame - cel.startFrame
        // Where the drawing *was*, expressed against the geometry as it now stands. `restBox` is only
        // a reference frame — `Homography(rect:to:)` recovers the same map from any non-degenerate
        // one — so using the pre-move box keeps the number the artist can reason about.
        //
        // **Nil where a corner of the box has no image**, which is the vanishing line and is the one
        // failure a projective map has that an affine one does not. Refusing the whole commit beats
        // writing a key nothing can render; the geometry is already baked and the artist sees their
        // drag stand, which is exactly what the `.storedValue` arm means.
        guard let wasAt = PoseQuad(box: restBox, mappedThrough: inverse.homography) else { return .storedValue }
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
            guard let posed = PoseQuad(box: restBox, mappedThrough: map.homography) else {
                return .storedValue
            }
            keyPoseRestoringRest(layerID: layerID, celID: celID, channel: channel,
                                 atCelLocalFrame: local, pose: posed,
                                 restElements: restElements, movedIDs: movedIDs)
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
                                      restElements: [VectorElement], movedIDs: Set<UUID>) {
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
        // **A same-id rewrite, declared as one** — TODO (41)'s last box. The moved elements go back
        // to rest under their own ids (a piece a Cut minted is an id difference and is bounded by
        // that half), so the seam bounds the swap by where each was and where it will be, in the
        // bake and in both presses, rather than `bumpVersion()`'s whole-cel walk.
        vector.restoreElements(restElements, changedInk: nil, rewriting: movedIDs)
        applyCelPoseState(state, layerID: layerID, celID: celID)
        celContentChangedOutsideStroke(layerID: layerID, celID: celID)

        guard structureUndoDepth == 0, gestureSnapshot == nil else { return }
        recordUndo(label: .effectKeyframes,
                   cost: (movedElements.count + restElements.count) * 512,
                   undo: { [weak self] in
                       vector.restoreElements(movedElements, changedInk: nil, rewriting: movedIDs)
                       self?.applyCelPoseState(before, layerID: layerID, celID: celID)
                       self?.celContentChangedOutsideStroke(layerID: layerID, celID: celID)
                   }, redo: { [weak self] in
                       vector.restoreElements(restElements, changedInk: nil, rewriting: movedIDs)
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
        // piece extends its channel instead of minting a second one over the same ink.
        //
        // **A mixed selection answers nil, and the mint that follows is why the lift refuses one.**
        // `mintAnimationChannel` *overwrites* `animationGroupID` on everything it is given, so the
        // fall-through does not "join one of them" — it ends every animation the carried ink already
        // had. `animationGroupHarmedByMove` is the rule that stops a Move reaching here in that
        // state; the `Set` below is the exact expression it is stated against, untagged ink's `nil`
        // included.
        let tags = Set(carried.map(\.animationGroupID))
        guard tags.count == 1, let existing = tags.first, let id = existing,
              animationGroups.contains(where: { $0.id == id }) else { return nil }
        return .group(id)
    }

    /// **How a Move would damage an animation that already exists** — the two ways there are, and
    /// which group it would happen to. `animationGroupHarmedByMove` answers with one of these or
    /// with nil, and the two cases exist because **the way out of them is opposite**: one is fixed by
    /// widening the loop and the other by narrowing it, so they cannot share a sentence.
    enum AnimationGroupHarm: Equatable {
        /// Some but not all of the group's members are carried, so the half left behind travels too.
        case torn(UUID)
        /// The group is carried whole, but with ink it does not own — another group's, or none's.
        /// `existingAnimationChannel` answers nil for that mixture and the commit **mints**, which
        /// overwrites `animationGroupID` on every carried element and orphans the tracks they had.
        case notAlone(UUID)
    }

    /// **How a Move would damage an existing animation, or nil when it would damage none** — the
    /// owner's ruling of 2026-09-03: *"Lets say animation A is a movement of a selection to a
    /// location. Now if you select half of the selection, then it shouldn't allow you to move it
    /// because that would break things."* Extended the same day to its second case, on the same
    /// reasoning: **if a Move would damage an existing animation, it does not happen, and it says
    /// why.**
    ///
    /// ## One rule, and it is a sentence about membership: *an animation group moves whole, and on its own*
    ///
    /// Everything below is that sentence failing in one of its two halves, and stating it once is
    /// what keeps the two from drifting apart. Routing is a consequence; membership is the thing the
    /// artist can see and reason about, it needs no keyframe state to evaluate, and it is what the
    /// notice can say back to them.
    ///
    /// ## `.torn` — the half the loop missed moves as well
    ///
    /// A group's members are carried by **one** pose channel, so a key written for it moves all of
    /// them. `existingAnimationChannel` above reuses a group as soon as every *carried* element
    /// shares it and never asks whether the group has members the loop missed — so a half-lasso of an
    /// animated group routes to that group's channel, and `commitTransformPose`'s `.key` arm then
    /// restores the pre-lift display list and keys the whole thing. The artist dragged half and the
    /// whole piece moved. The other two writing arms fail the same way one step later: `.seedAndKey`
    /// leaves the drag baked *and* keys the group, so the lassoed half moves twice and the rest once,
    /// and `.storedValueHoldingBaseline` parks a baseline that does it when the next mark lands.
    ///
    /// ## `.notAlone` — the animation stops existing, and nothing on screen says so
    ///
    /// `existingAnimationChannel` reuses a group only when **every** carried element shares one, so a
    /// selection spanning two groups — or one group plus ink in no group — answers nil and
    /// `commitPoseFromFloat` falls through to `mintAnimationChannel`, which **overwrites**
    /// `animationGroupID` on every carried element with the fresh group's id. From that moment
    /// `VectorElement.isMoved(by: .group(old))` is false for all of them, so the tracks still sitting
    /// on the cel claim no elements and pose nothing. Nothing looks wrong at the frame the Move was
    /// made on — the ink keeps moving, under the new channel, from wherever the drag left it. The
    /// loss shows up only when the artist scrubs.
    ///
    /// **Two whole groups and one whole group beside untagged ink are the same defect through the
    /// same door**, which is why one case covers both rather than two: the mint does not care what
    /// the other carried ink is, only that the carried set is not one group exactly. A predicate
    /// written for "two or more groups" alone would leave the identical silent loss reachable with a
    /// four-element drawing.
    ///
    /// ## Four narrowings, each of which a broader rule would get wrong
    ///
    ///   * **A Move that carries the whole cel is never harm, and this is the narrowing the second
    ///     case needs.** `existingAnimationChannel` answers `.cel` for exactly that Move, so nothing
    ///     is minted and every group on the cel travels whole inside it — a character walking with
    ///     both arms still swinging. Without this line, `beginVectorWholeCelMove` on any drawing
    ///     holding two animated groups would refuse, which is Move with no selection made unusable on
    ///     every animated document. It is stated as "every element is carried" rather than as
    ///     "nothing was left behind by a *group*", because the damaging case has untagged ink outside
    ///     the loop and no group's member there at all.
    ///   * **Group channels only — the cel channel is not one of these.** `.cel`'s membership is
    ///     every element, so a rule stated over channels would make an animated cel refuse every
    ///     lasso on it. It also would not be protecting anything: `existingAnimationChannel` answers
    ///     `.cel` only for a Move that carries the whole list, so a partial lasso on a cel-animated
    ///     cel never reaches that channel — it mints a group of its own and nests inside the cel
    ///     move, which is a character's arm swinging while the character walks and is exactly right.
    ///   * **Only groups that are in `animationGroups`**, matching `existingAnimationChannel`'s own
    ///     guard to the letter. A tag whose registry entry is gone is not a channel anything reuses,
    ///     so refusing on it would block a Move that could not have written onto it — and an element
    ///     wearing one counts as ink in no group, because that is what the mint would cost it.
    ///   * **Membership is counted on the cel's own display list**, not across the document. A pose
    ///     channel lives on one cel and keys one cel's rest box, so a group's members on *other* cels
    ///     are moved by other channels and are none of this Move's business.
    ///
    /// `elements` is a parameter for `celPoseMaps`' reason: the lasso lift has to ask against the
    /// **post-split** list, since a cut mints fresh ids for both halves and `splitForLassoMove`
    /// carries the group onto both — so a loop drawn *through* an animated stroke leaves half of it
    /// behind and is refused, which is the same tear by a narrower door.
    ///
    /// **`.torn` is answered before `.notAlone`** when a Move manages both. It is the worse damage —
    /// ink the artist never pointed at moves — and its fix comes first: widen the loop to all of that
    /// group, and ask again.
    ///
    /// Sorted before the first is taken so the answer does not depend on Swift's per-process hash
    /// seed — `poseMappings` makes the same argument for the same reason one file over.
    func animationGroupHarmedByMove(_ elements: [VectorElement],
                                    movedIDs moved: Set<UUID>) -> AnimationGroupHarm? {
        guard !animationGroups.isEmpty, !moved.isEmpty, !elements.isEmpty else { return nil }
        // The `.cel` channel's own membership. Nothing is minted for it and nothing is torn by it.
        if elements.allSatisfy({ moved.contains($0.id) }) { return nil }

        let registered = Set(animationGroups.map(\.id))
        var caught: Set<UUID> = []
        var left: Set<UUID> = []
        var carriesInkInNoGroup = false
        for element in elements {
            let group = element.animationGroupID.flatMap { registered.contains($0) ? $0 : nil }
            if moved.contains(element.id) {
                if let group { caught.insert(group) } else { carriesInkInNoGroup = true }
            } else if let group {
                left.insert(group)
            }
        }
        let ordered = { (ids: Set<UUID>) in ids.sorted { $0.uuidString < $1.uuidString }.first }
        guard let first = ordered(caught) else { return nil }
        if let torn = ordered(caught.intersection(left)) { return .torn(torn) }
        guard caught.count == 1, !carriesInkInNoGroup else { return .notAlone(first) }
        return nil
    }

    /// **Renames an animation group** — KEYFRAMES.md §3.4's identity, which until now was generated
    /// and unreachable.
    ///
    /// A minted group is called "Group 1", "Group 2" — `mintAnimationChannel` counts — and that name
    /// is what the graph editor's channel list draws over the curve (`poseChannelName(_:)`), which is
    /// the surface an artist picks a channel by. A document with four of them offers four rows that
    /// differ only by a number, so the *one* thing a group's identity is for cannot be used.
    ///
    /// **An empty name is refused rather than stored**, `renameLayer`'s rule: a blank row is a row the
    /// artist cannot pick, and `poseChannelName`'s fallback only covers a group that is *missing*.
    ///
    /// **`withStructureUndo`, which is the bracket that snapshots `animationGroups`** — see
    /// `CanvasManager.StructureSnapshot`, which carries them precisely so a group edit is one press of
    /// Undo like every other discrete pick.
    ///
    /// - Returns: whether the document changed.
    @discardableResult
    func renameAnimationGroup(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let at = animationGroups.firstIndex(where: { $0.id == id }),
              animationGroups[at].displayName != trimmed else { return false }
        withStructureUndo(label: .renameAnimationGroup) {
            animationGroups[at].displayName = trimmed
        }
        return true
    }

    /// **The group one channel-list row names**, or nil for a row that is not a group's — the whole
    /// cel's Move, a container pose, or a grade's curve.
    ///
    /// One accessor rather than a `case .cel(.group(let id))` at each caller, for
    /// `revealPoseChannel`'s reason: `Views/AnimationTimeline.swift` is not compiled into
    /// `PaintSoftwareUITests`, so a rule spelled there is pinned by nothing.
    func animationGroup(named channel: PoseChannelID?) -> AnimationGroup? {
        guard case .cel(.group(let id))? = channel else { return nil }
        return animationGroups.first { $0.id == id }
    }

    /// **Mints a group over the carried elements and tags them** — the writing half of the pair above,
    /// called only once the route has said a key is actually going to be written.
    ///
    /// The tag is written onto `vector.elements` directly rather than through an undo record of its
    /// own: it travels with the pose write in the same commit, and the arm that restores rest geometry
    /// (`.key`) is never the arm that mints, because a channel with a track already has its group.
    ///
    /// **The write is an overwrite, and that is why the lift has a guard rather than this having a
    /// merge.** Anything carried here loses the group it had, so a Move that reaches this holding
    /// ink from an existing animation ends that animation — silently, since the ink keeps moving
    /// under the new channel and only a scrub shows the loss. `animationGroupHarmedByMove` refuses
    /// such a Move at the lift, so by the time this runs the carried set is either untagged ink or
    /// ink whose tags no channel claims.
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
        Self.invertedAffine(map)
    }

    // MARK: - The container's own pose — KEYFRAMES.md §4.4's transformation layer, §2.21's folder twin

    /// **Where a Move on a transformation layer or a posed folder would go**, `transformWrite`'s
    /// container twin with `KeyframeControl.write`'s four inputs read off `target`.
    ///
    /// **`containerPose(of:)`, never a raw field**, which is this file's rule everywhere else and is
    /// load-bearing here for the reason `poseKeyframeFrames(inLayer:)` gives: a `.raster` layer
    /// carrying a pose left behind by a kind change poses nothing, so routing a write onto it would
    /// key an animation the canvas is not running. A folder has no second field to reconcile, so the
    /// accessor is a plain read there — `containerPose(of:)`'s own doc carries the asymmetry.
    ///
    /// **`target` rather than `layerID`, since a folder's transform earned its own writer.** Every
    /// caller of this file's container-pose pipeline used to name a layer because a layer was the
    /// only thing that could pose; `KeyframeTarget` already existed for the grade's own two homes
    /// (§2.21), so widening this pipeline to reach `LayerFolder.transform` was a signature change and
    /// not a new mechanism.
    func containerPoseWrite(_ target: KeyframeTarget, atFrame frame: Int) -> KeyframeControl.Write {
        guard let pose = containerPose(of: target) else { return .storedValue }
        let placed = keyframeFrames(of: target)
        return KeyframeControl.write(
            // A pose is not a scalar and this input is not asking whether it is — `transformWrite`
            // carries the argument. The container track stores and renders every pose it can hold.
            isScalarAnimatable: true,
            channelHasCurve: !pose.track.isEmpty,
            keyframeCount: placed.count,
            playheadIsOnKeyframe: placed.contains(frame))
    }

    /// **One committed Move on a transformation layer or a posed folder, routed** — §2.5's
    /// write-at-commit for §4.4's container pose, through `KeyframeControl.write`'s same five arms.
    ///
    /// ## It is a *value* channel, not a geometry channel, and that is the one real difference
    ///
    /// `commitTransformPose`'s `.key` arm **takes the bake back**: a cel channel has no stored base,
    /// so the drawing itself was moved and the render composes geometry × pose — leaving both would
    /// apply the move twice. A container has a stored base and `LayerPose.resolvedPose(atFrame:)` is
    /// *"the track when it holds keys, the stored base otherwise"* — a precedence, not a composition.
    /// So **every arm here writes the stored base**, which is exactly §2.27's second consequence
    /// stated for the general case: *"the edit still writes the stored base, exactly as it always
    /// did"*. Nothing is doubled, and an artist who later deletes every key is left with the pose
    /// they last saw rather than snapped back to rest.
    ///
    /// The arms are therefore the effect-parameter path's, one payload over:
    ///
    ///  * **`.storedValue`** — no keyframes anywhere. The base moves and nothing else happens, which
    ///    is the property the whole routing rule is shaped around.
    ///  * **`.storedValueHoldingBaseline`** — the base moves and `LayerPose.baseline` records where
    ///    the container *was*, for the next keyframe press to commit onto the neighbouring mark.
    ///  * **`.seedAndKey`** — the old pose onto the immediate neighbouring keyframes, the new one
    ///    here, both in one write, because standing on a keyframe there is no third press coming.
    ///  * **`.key`** — the auto-key arm: a key at the playhead holding the pose the artist ended on.
    ///
    /// **§2.28's biconditional is applied here rather than left to a caller**, because this is a
    /// third writer that changes `keyedFrames(of:)` — `commitKeyframeState` and
    /// `setEffectParameterTrack` are the other two. A key landing on a marked frame drops the mark,
    /// asked against the keys *either side* of the write, so a key written onto a mark takes it and a
    /// document saved under the old rule heals on first touch.
    ///
    /// - Parameters:
    ///   - restPose: the pose the container was showing when the gesture began — what a held baseline
    ///     and a seeded neighbour record.
    ///   - posed: the pose the artist ended on.
    /// - Returns: the arm taken, so a caller can label its own bracket.
    @discardableResult
    func commitContainerPose(_ target: KeyframeTarget, restingAt restPose: PoseQuad, movedTo posed: PoseQuad,
                             atFrame frame: Int) -> KeyframeControl.Write {
        guard let before = containerPose(of: target) else { return .storedValue }
        let route = containerPoseWrite(target, atFrame: frame)

        var after = before
        // Every arm, for the reason above: the edit writes the stored base exactly as it always did.
        after.pose = posed

        switch route {
        case .storedValue:
            break

        case .storedValueHoldingBaseline:
            // **Written once per keyframe cycle**, `holdPoseBaseline`'s rule: the first Move after a
            // mark is the only one that knows where the container was at A, and a later one measures
            // from a base this arm has already written.
            if after.baseline == nil { after.baseline = restPose }

        case .seedAndKey:
            let placed = keyframeFrames(of: target)
            after.track = Self.seedingContainer(after.track, keyframes: placed, frame: frame,
                                                oldPose: restPose, newPose: posed)
            after.baseline = nil

        case .key:
            after.track.setKey(TransformTrack.Key(frame: frame, pose: posed))
            after.baseline = nil
        }

        guard after != before else { return route }
        writeContainerPose(after, from: before, target: target, label: .effectKeyframes)
        return route
    }

    /// **Only the immediate neighbours are seeded**, `seedAndKeyPose`'s rule and for its reason:
    /// `TransformTrack` extrapolates as a constant hold outside its first and last key, so a pose on
    /// the nearest keyframe below already holds at every one below that.
    ///
    /// Static and pure so the seeding rule can be pinned without a document — it is the one piece of
    /// arithmetic in this section that a fixture could get wrong invisibly.
    static func seedingContainer(_ track: TransformTrack, keyframes: [Int], frame: Int,
                                 oldPose: PoseQuad, newPose: PoseQuad) -> TransformTrack {
        var track = track
        if let below = keyframes.last(where: { $0 < frame }), track.key(atFrame: below) == nil {
            track.setKey(TransformTrack.Key(frame: below, pose: oldPose))
        }
        if let above = keyframes.first(where: { $0 > frame }), track.key(atFrame: above) == nil {
            track.setKey(TransformTrack.Key(frame: above, pose: oldPose))
        }
        track.setKey(TransformTrack.Key(frame: frame, pose: newPose))
        return track
    }

    /// **The one funnel every container-pose write goes through**, marks pruned and one undo step
    /// recorded — `commitCelPoseState` one container up, plus the §2.28 rule that a cel channel gets
    /// from `commitKeyframeState` instead.
    ///
    /// **Addressed by id inside the closures**, `setEffectParameterTrack`'s rule: a restack or a
    /// delete between the edit and the undo moves an index and cannot move an id.
    ///
    /// **Records nothing while an enclosing bracket is open** — `withStructureUndo`'s own rule, so a
    /// live drag that calls this on every tick costs the artist one press of Undo rather than one per
    /// tick.
    ///
    /// **`target` rather than `layerID`**, so a folder's own posed contents (§2.21) go through the
    /// identical funnel a transformation layer's always have — `KeyframeTarget.folder` was already
    /// the grade's second home, and a container pose has no reason to need a second writer where the
    /// grade needed none.
    func writeContainerPose(_ pose: LayerPose?, from before: LayerPose?, target: KeyframeTarget,
                            label: HistoryActionLabel = .effectKeyframes) {
        guard targetExists(target) else { return }
        let marksBefore = keyframeState(of: target).marks
        beginCanvasEdit()

        // Both halves of `marks(_:droppingKeyed:)`: the "before" set is what makes a key dragged off
        // a marked frame take the mark with it, the "after" set is what stops a mark being written
        // under a key. Free when the target carries no marks, which is most of them.
        let keyedBefore = marksBefore.isEmpty ? [] : keyedFrames(of: target)
        applyContainerPose(pose, target: target)
        let marksAfter = marksBefore.isEmpty
            ? marksBefore
            : Self.marks(marksBefore, droppingKeyed: keyedBefore.union(keyedFrames(of: target)))
        if marksAfter != marksBefore { applyContainerPose(pose, target: target, marks: marksAfter) }

        guard structureUndoDepth == 0, gestureSnapshot == nil else { return }
        recordUndo(label: label,
                   cost: Self.containerPoseUndoCost(before) + Self.containerPoseUndoCost(pose),
                   undo: { [weak self] in
                       self?.applyContainerPose(before, target: target, marks: marksBefore)
                   }, redo: { [weak self] in
                       self?.applyContainerPose(pose, target: target, marks: marksAfter)
                   })
    }

    /// The one mutation every direction of the undo above goes through, re-resolving `target` by id
    /// on every call — `applyCelPoseState`'s rule for the payload one container up.
    ///
    /// **The raw field is written and the accessor is read**, which is
    /// `applyGraphBandPoseSnapshot`'s pairing and needed for its reason: nil is a real value here, so
    /// a restore has to be able to write it, while a pose left inert by a kind change must not be
    /// treated as one this path may put back into force. A folder has no kind to change, so its arm
    /// is the layer arm with the second field reconciled away — `containerPose(of:)`'s own asymmetry.
    ///
    /// **Not `private`: `CanvasManager+Recording.swift` restores a take's base pose through it**
    /// (KEYFRAMES.md §5's Move box surface), for the same reason `commitContainerFloat` writes the
    /// field directly — putting a *preview* back is not an edit and must stay off the history. That is
    /// `targetExists`' precedent one file over, and the alternative was a second spelling of this
    /// `switch` in the recorder, which is how two writers drift apart.
    func applyContainerPose(_ pose: LayerPose?, target: KeyframeTarget, marks: [Int]? = nil) {
        switch target {
        case .layer(let id):
            guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
            if layers[index].transform != pose { layers[index].transform = pose }
            if let marks, layers[index].keyframeMarks != marks { layers[index].keyframeMarks = marks }
        case .folder(let id):
            guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
            if folders[index].transform != pose { folders[index].transform = pose }
            if let marks, folders[index].keyframeMarks != marks { folders[index].keyframeMarks = marks }
        }
    }

    /// `graphBandPoseUndoCost`'s container term, in the same currency and for the same reason.
    private static func containerPoseUndoCost(_ pose: LayerPose?) -> Int {
        pose.map { 64 + 160 * $0.track.keys.count } ?? 0
    }
}

// MARK: - The transform layer's modes — TRANSFORM_LAYER.md §5, stages 2 and 3

/// **One item beneath a parallax poser, as the panel lists it** — its target (for the share
/// writer), its name, the share it is showing at the playhead, and whether that share was typed
/// or is the positional default (§5.2: *"defaults shown greyed until touched"*).
struct ParallaxItem: Equatable {
    let target: KeyframeTarget
    let name: String
    /// The share in force at the playhead — the curve, the typed number, or the positional default,
    /// in that precedence.
    let share: Double
    /// The share this item's position gives it, whatever it stores — what the row shows greyed
    /// when nothing has been typed, and what `setParallaxShare` materialises before the first edit.
    let positionalDefault: Double
    /// Whether the artist has typed a number (or keyed a curve) for this item.
    let isExplicit: Bool
}

extension CanvasManager {

    /// **Switches a transform layer's — or a posed folder's — mode**, TRANSFORM_LAYER.md §5. One
    /// undo step; nothing else moves: the authored pose, its track and its keys stay exactly as they
    /// are, because §6's factorisation makes the mode a qualifier on the pose rather than a rewrite
    /// of it. Refused on a target with no pose to qualify.
    ///
    /// **Repeat is refused on a folder** (§3.3: *"not repeat: a folder has no block"*, and the loop's
    /// extent is the block) — the folder picker does not list it, and this is the model's half of
    /// the same rule. On a layer entering Repeat with no period yet, the period is **pre-filled from
    /// where the drawings beneath end** (§2 ruling 11), inside the same undo step.
    func setTransformLayerMode(_ target: KeyframeTarget, to mode: TransformLayerMode) {
        guard var pose = containerPose(of: target), pose.mode != mode else { return }
        if mode == .repeat, case .folder = target { return }
        pose.mode = mode
        // **The shake's seed is minted the first time the pose enters Shake** (§5.4: *"minted at
        // creation"*), inside the same undo step as the pick, so two shake layers differ from birth
        // and one is stable from its first frame. A seed already minted is kept — leaving Shake and
        // coming back is the same shake, `valueFill`'s own asymmetry.
        if mode == .shake, pose.shakeSeed == 0 { pose.shakeSeed = Self.freshShakeSeed() }
        if mode == .repeat, pose.repeatPeriod == 0, case .layer(let id) = target,
           let index = layers.firstIndex(where: { $0.id == id }) {
            pose.repeatPeriod = suggestedRepeatPeriod(forLayer: index)
        }
        withStructureUndo(label: .transformLayerMode) {
            applyContainerPose(pose, target: target)
        }
    }

    /// **The loop length a Repeat layer is pre-filled with** — §2 ruling 11's (b): *"where the
    /// drawings beneath it end"*, measured from the layer's first block. The entries beneath it in
    /// its container, a folder's contents included, are walked for the last frame any of their
    /// cels covers; the period is that end less the block's start, so a walk on frames 1–8 under a
    /// bar starting at 1 pre-fills 8. Never below 1, and the block's own length when nothing beneath
    /// ends after the block starts (a loop of the whole bar, which is the identity — the honest
    /// default when there is nothing to loop yet).
    func suggestedRepeatPeriod(forLayer index: Int) -> Int {
        guard layers.indices.contains(index) else { return 1 }
        let blockStart = layers[index].cels.map(\.startFrame).min() ?? 0
        let blockLength = layers[index].cels.first { $0.startFrame == blockStart }?.frameCount ?? 1
        let stack = Array(containerEntries(inContainer: layers[index].parentFolderID).reversed())
        guard let position = stack.firstIndex(where: {
            if case .layer(let at) = $0 { return at == index } else { return false }
        }) else { return max(blockLength, 1) }
        var end = blockStart
        for q in 0..<position {
            switch stack[q] {
            case .layer(let at):
                guard layers[at].kind.holdsPixels else { continue }
                for cel in layers[at].cels where cel.endFrame > end { end = cel.endFrame }
            case .folder(let folder):
                for at in descendantLayerIndices(ofFolder: folder.id) where layers[at].kind.holdsPixels {
                    for cel in layers[at].cels where cel.endFrame > end { end = cel.endFrame }
                }
            }
        }
        let fromDrawings = end - blockStart
        return fromDrawings >= 1 ? fromDrawings : max(blockLength, 1)
    }

    /// **Sets a Repeat layer's loop length** — §2 ruling 11's (a), typed; one undo step; never below
    /// 1. Written whatever the mode, since the panel offers it only in Repeat and a period is
    /// harmless storage elsewhere.
    func setRepeatPeriod(_ target: KeyframeTarget, to period: Int) {
        let clamped = max(period, 1)
        guard var pose = containerPose(of: target), pose.repeatPeriod != clamped else { return }
        pose.repeatPeriod = clamped
        withStructureUndo(label: .repeatPeriod) {
            applyContainerPose(pose, target: target)
        }
    }

    /// A seed for a shake — `DabRandom.freshSeed`, never zero, because zero is "never minted".
    static func freshShakeSeed() -> UInt64 {
        var seed = DabRandom.freshSeed()
        while seed == 0 { seed = DabRandom.freshSeed() }
        return seed
    }

    /// **Re-rolls a shake layer's seed** — §2 ruling 9's *"new shake"* button, one undo step, and
    /// nothing else moves. Refused off a pose in Shake, where the seed reaches no pixel.
    func rerollShakeSeed(_ target: KeyframeTarget) {
        guard var pose = containerPose(of: target), pose.mode == .shake else { return }
        var seed = Self.freshShakeSeed()
        while seed == pose.shakeSeed { seed = Self.freshShakeSeed() }
        pose.shakeSeed = seed
        withStructureUndo(label: .shakeSeed) {
            applyContainerPose(pose, target: target)
        }
    }

    /// **Sets how many frames one jolt of a shake lasts** — §2 ruling 10's one speed control, clamped
    /// into `TransformLayerMode.shakePeriodRange`, one undo step. Written whatever the mode, since
    /// the panel offers it only in Shake and a period is harmless storage elsewhere.
    func setShakePeriod(_ target: KeyframeTarget, to period: Int) {
        let range = TransformLayerMode.shakePeriodRange
        let clamped = min(max(period, range.lowerBound), range.upperBound)
        guard var pose = containerPose(of: target), pose.shakePeriod != clamped else { return }
        pose.shakePeriod = clamped
        withStructureUndo(label: .shakePeriod) {
            applyContainerPose(pose, target: target)
        }
    }

    /// The mode a target's pose is in, or nil when it has no pose.
    func transformLayerMode(of target: KeyframeTarget) -> TransformLayerMode? {
        containerPose(of: target)?.mode
    }

    /// **A target channel's value at `frame`, on whichever home `target` names** — `storedValue`'s
    /// resolved twin, and what a panel control shows: §2.23's dead-control argument says the slider
    /// must show the resolved number, never the base, or a keyed channel reads as stuck.
    func resolvedValue(of target: KeyframeTarget, channel: TargetChannel, atFrame frame: Int) -> Double? {
        switch target {
        case .layer(let id): return layers.first { $0.id == id }?.resolvedValue(channel, atFrame: frame)
        case .folder(let id): return folders.first { $0.id == id }?.resolvedValue(channel, atFrame: frame)
        }
    }

    /// **The stack a container pose reaches, and where the poser sits in it** — the same two operands
    /// `RenderTree.renderNodes` builds, so the panel's list and the render's items are one walk. A
    /// layer's poser is the layer's own position in its container; a folder's is the top of the
    /// folder's own contents.
    private func poserStack(of target: KeyframeTarget) -> (stack: [ContainerEntry], position: Int)? {
        switch target {
        case .layer(let id):
            guard let index = layers.firstIndex(where: { $0.id == id }) else { return nil }
            let stack = Array(containerEntries(inContainer: layers[index].parentFolderID).reversed())
            guard let position = stack.firstIndex(where: {
                if case .layer(let at) = $0 { return at == index } else { return false }
            }) else { return nil }
            return (stack, position)
        case .folder(let id):
            guard folders.contains(where: { $0.id == id }) else { return nil }
            let stack = Array(containerEntries(inContainer: id).reversed())
            return (stack, stack.count)
        }
    }

    /// **The items a parallax poser distributes its move over, top to bottom, with the share each is
    /// showing at the playhead** — the panel's list (§5.2: *"the panel lists the items with a slider
    /// each"*). Empty for a target with no pose, and for one with nothing beneath it; not gated on
    /// the mode, so the panel can show what Parallax *would* do before the artist picks it.
    func parallaxItems(beneath target: KeyframeTarget) -> [ParallaxItem] {
        guard let (stack, position) = poserStack(of: target) else { return [] }
        let positions = parallaxItemPositions(in: stack, beneath: position)
        return positions.enumerated().map { rank, q in
            let positional = TransformLayerMode.positionalParallaxShare(rank: rank, of: positions.count)
            switch stack[q] {
            case .layer(let index):
                let layer = layers[index]
                return ParallaxItem(
                    target: .layer(id: layer.id), name: layer.name,
                    share: layer.parallaxShare(atFrame: currentFrame, positionalDefault: positional),
                    positionalDefault: positional,
                    isExplicit: layer.parallaxShare != nil
                        || layer.channelTracks[TargetChannel.parallaxShare.id]?.isEmpty == false)
            case .folder(let folder):
                return ParallaxItem(
                    target: .folder(id: folder.id), name: folder.name,
                    share: folder.parallaxShare(atFrame: currentFrame, positionalDefault: positional),
                    positionalDefault: positional,
                    isExplicit: folder.parallaxShare != nil
                        || folder.channelTracks[TargetChannel.parallaxShare.id]?.isEmpty == false)
            }
        }
    }

    /// **One share-slider edit on one item, routed and performed** — `applyTargetChannelEdit` on
    /// `TargetChannel.parallaxShare`, with the one line that channel needs and opacity did not.
    ///
    /// **The positional default is written through as a stored number before the edit is routed**,
    /// when nothing has been typed yet. The funnel reads the *stored* value to seed keyframe A and
    /// to hold a baseline (`applyTargetChannelEdit`'s own rule), and for a share that is nil the
    /// stored value is `parallaxShareValue`'s fallback rather than the 75% the artist was looking at
    /// — so a first drag on a keyed layer would seed A with the wrong number. Materialising first
    /// makes the funnel's read true. It is not an undo step of its own: the number it writes is the
    /// one already on screen, and the bracket the panel opens around the drag records the edit.
    ///
    /// - Returns: the arm taken, so the caller can label its undo bracket, exactly as the opacity
    ///   slider does.
    @discardableResult
    func setParallaxShare(of item: KeyframeTarget, beneath poser: KeyframeTarget,
                          to value: Double, atFrame frame: Int) -> KeyframeControl.Write {
        if storedParallaxShare(of: item) == nil,
           let listed = parallaxItems(beneath: poser).first(where: { $0.target == item }) {
            setStoredValue(of: item, channel: .parallaxShare, to: listed.positionalDefault)
        }
        return applyTargetChannelEdit(item, channel: .parallaxShare, newValue: value, atFrame: frame)
    }

    /// The typed share on a target, or nil for the positional default — the raw optional, which
    /// `storedValue(of:channel:)` cannot answer because it reads through the non-optional view.
    func storedParallaxShare(of target: KeyframeTarget) -> Double? {
        switch target {
        case .layer(let id): return layers.first { $0.id == id }?.parallaxShare
        case .folder(let id): return folders.first { $0.id == id }?.parallaxShare
        }
    }

    // MARK: - §5.5's ghost blocks

    /// **One run of frames on a layer's row that a Repeat above it is showing as an earlier frame** —
    /// what the timeline draws ghosted so the artist can tell (§5.5: *"the timeline drawing the
    /// repeated span as ghost blocks so the artist can see it is one"*). `sourceCelID` is the cel
    /// those frames are showing, so consecutive ghost frames of one drawing are one segment and the
    /// row reads as the first cycle's pattern played again.
    struct RepeatGhost: Equatable {
        let start: Int
        let length: Int
        let sourceCelID: UUID
    }

    /// **The ghost segments on layer `index`'s row.** Structural rather than off the render walk —
    /// the timeline builds its layout key on every SwiftUI pass, and a walk per frame of every
    /// repeated span would be hundreds of walks a pass — so this applies the Repeat layers that reach
    /// the layer in the walk's own order (outermost container first, top to bottom within one) with
    /// `TransformLayerMode.repeatSourceFrame`, which is the one function the walk applies too;
    /// `TransformLayerModesLogicTests` pins the two against each other on a nested fixture. Empty
    /// for every layer in a document with no Repeat layer in force, after one array scan.
    func repeatGhostSegments(forLayer index: Int) -> [RepeatGhost] {
        guard hasRepeatLayerInForce, layers.indices.contains(index) else { return [] }
        let chain = repeatPosers(reaching: index)
        guard !chain.isEmpty else { return [] }
        let end = contentEndFrame
        var segments: [RepeatGhost] = []
        var open: (start: Int, sourceCelID: UUID)?
        func close(at frame: Int) {
            if let open { segments.append(RepeatGhost(start: open.start, length: frame - open.start, sourceCelID: open.sourceCelID)) }
            open = nil
        }
        for frame in 0..<end {
            var shown = frame
            for repeater in chain {
                guard let block = repeater.blocks.first(where: { shown >= $0.start && shown < $0.end }) else { continue }
                shown = TransformLayerMode.repeatSourceFrame(shown, blockStart: block.start, period: repeater.period)
            }
            guard shown != frame, let celIndex = activeCelIndex(inLayer: index, atFrame: shown) else {
                close(at: frame)
                continue
            }
            let id = layers[index].cels[celIndex].id
            if open?.sourceCelID != id { close(at: frame); open = (frame, id) }
        }
        close(at: end)
        return segments
    }

    /// One Repeat layer as the ghost walk sees it: its blocks and its period.
    private struct RepeatPoser {
        let blocks: [(start: Int, end: Int)]
        let period: Int
    }

    /// **The Repeat layers whose loop reaches layer `index`, in the order the render walk applies
    /// them** — for each container from the outermost in, the visible Repeat layers above the entry
    /// that leads to the layer, top to bottom. `renderNodes`' own two gates: the eye, and never
    /// inside a compositor node, where the sibling carry is suppressed.
    private func repeatPosers(reaching index: Int) -> [RepeatPoser] {
        var chain: [RepeatPoser] = []
        var child: ContainerEntry = .layer(index: index)
        var container = layers[index].parentFolderID
        while true {
            let isNode = container.flatMap { id in folders.first { $0.id == id } }?.isCompositorNode == true
            var above: [RepeatPoser] = []
            // `containerEntries` ranks top to bottom, so everything before the child is above it.
            scan: for entry in containerEntries(inContainer: container) {
                switch (entry, child) {
                case (.layer(let a), .layer(let b)) where a == b: break scan
                case (.folder(let a), .folder(let b)) where a.id == b.id: break scan
                case (.layer(let at), _):
                    guard !isNode, layers[at].isVisible, let pose = layers[at].layerTransform, pose.repeats else { continue scan }
                    above.append(RepeatPoser(blocks: layers[at].cels.map { ($0.startFrame, $0.endFrame) },
                                             period: pose.repeatPeriod))
                default:
                    break
                }
            }
            chain = above + chain
            guard let containerID = container, let folder = folders.first(where: { $0.id == containerID }) else { break }
            child = .folder(folder)
            container = folder.parentFolderID
        }
        return chain
    }
}
