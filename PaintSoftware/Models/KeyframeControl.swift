import Foundation

/// **Where one settings-bar edit goes** — KEYFRAMES.md §2.26 and §2.27, the keyframe-mark workflow.
///
/// **Why this is a type and not four `if`s inside `AnimationTimeline`.** `Views/AnimationTimeline.swift`,
/// `Views/EffectSection.swift` and `Views/DrawingView.swift` are **not compiled into the
/// `PaintSoftwareUITests` target** — a fast-tier test written against any of them is silently a pin
/// against nothing, which is what commit `6a396e1` was written to record. So every decision that can
/// be stated as a function of values rather than of views lives here, where a logic test can reach
/// it, and the views hold only the wiring that genuinely needs SwiftUI. `TimelineLayoutKey` is the
/// same split made for the same reason one file over.
enum KeyframeControl {

    /// **What one settings-bar slider edit does to the document.**
    enum Write: Equatable {
        /// Writes the number onto the target's *stored* effect and holds nothing — a plain slider on a
        /// document with no keyframes in it.
        case storedValue
        /// Writes the stored value **and** records the pre-edit value as this channel's baseline, for
        /// the next keyframe to commit onto the neighbouring mark. The owner's *"the previous value is
        /// held"*.
        case storedValueHoldingBaseline
        /// Inserts or replaces a key at the playhead. The auto-key arm.
        case key
        /// Creates the channel from nothing in one move: the **old** value keyed onto the neighbouring
        /// marks, the **new** one at the playhead. The owner's *"the user modifies another slider while
        /// on B"*, where A already exists and must receive the value B is moving away from.
        case seedAndKey
    }

    /// **The routing rule, in one place — five arms, no mode.**
    ///
    /// **The marks carry the state**: a keyframe is placed, edits are made, another keyframe is
    /// placed, and the pair of them is the animation. So "what does this edit do" is answered by where
    /// the playhead stands relative to `Layer.keyframeMarks` — document state the artist can see on the
    /// timeline — rather than by a flag they have to remember they set.
    ///
    /// 1. **Not scalar-animatable → `.storedValue`.** The stepped, array and colour parameters
    ///    (`EffectParameter.isScalarAnimatable` names why for each of the nine) are refused here as
    ///    well as at the resolver, so the app cannot reach a track that stores and renders nothing.
    /// 2. **The channel already has a curve → `.key`.** This is the auto-key arm and it takes
    ///    precedence over everything below it.
    /// 3. **Marks exist and the playhead is on one, with another mark to seed onto → `.seedAndKey`.**
    /// 4. **Marks exist and the playhead is not on one (or is on the only one) → hold the baseline.**
    /// 5. **No marks at all → `.storedValue`.** On a document nobody has keyframed a slider is a
    ///    slider, and nothing about this feature is visible.
    ///
    /// **Arm 2 asks `channelHasCurve`, not the owner's stricter "two keyframes and the value differs".**
    /// That stricter predicate is `AnimationCurve.isAnimated` and it is right for deciding what appears
    /// in the channel list; it is wrong here. A curve whose two keys happen to hold equal values is
    /// still in force, so an edit routed to the stored base would be overwritten by the curve at every
    /// frame it is consulted at and would spring back under the artist's finger. The alternative to
    /// keying is not "edit the value", it is a **dead control**. Two predicates, two jobs; do not merge
    /// them.
    ///
    /// **`markCount` rather than a bare `hasMarks`, and that is arm 3's whole correctness.** Seeding
    /// needs a *neighbouring* mark to put the old value on, and when the playhead's mark is the only
    /// one there is none — seeding would then produce a one-key curve pinning the new value, and the
    /// artist's old value would be lost with nothing on screen to explain it. The owner's canonical
    /// story is exactly that case: *"keyframe A is added, nothing is saved. A slider is then adjusted.
    /// The previous value is held. Then keyframe B is added"* — so with one mark the answer must be
    /// arm 4, and the value reaches A when B lands. `playheadIsOnMark && markCount > 1` is the same
    /// statement as "there is a mark other than this one", because the playhead's own mark is one of
    /// the count.
    static func write(isScalarAnimatable: Bool,
                      channelHasCurve: Bool,
                      markCount: Int,
                      playheadIsOnMark: Bool) -> Write {
        guard isScalarAnimatable else { return .storedValue }
        if channelHasCurve { return .key }
        guard markCount > 0 else { return .storedValue }
        return (playheadIsOnMark && markCount > 1) ? .seedAndKey : .storedValueHoldingBaseline
    }
}


/// **Which grade a keyframe write is aimed at.**
///
/// Two homes, because there are exactly two places an `Effect` lives — `Layer.effect` and
/// `LayerFolder.effect` — and §2.21 rules that they animate identically: one writer, one undo step,
/// one set of refusals, reached through this rather than through a `switch` at every call site.
///
/// **Both cases carry an id, including the layer one, and that is not symmetry for its own sake.** An
/// undo closure written against a layer *index* is wrong the moment a restack or a delete happens
/// between the edit and the undo — `setEffectParameterTrack(layerIndex:…)` has to reach for the id
/// *inside* its closures to survive that, and says so. Addressing by id from the outset removes the
/// hazard by construction instead of by care, which is the shape stage 2b's folder overload already
/// has ("there is no index here to go stale"). The cost is a `firstIndex` per lookup over a handful
/// of layers, behind the same `effectTracks.isEmpty` fast path everything else here uses.
enum KeyframeTarget: Equatable, Hashable {
    case layer(id: UUID)
    case folder(id: UUID)
}

// MARK: - The model half

extension CanvasManager {

    /// **Everything §2.26 stores on one target, as one value.**
    ///
    /// The three fields move together — a keyframe writer touches marks, baselines and curves in one
    /// artist action — so they are read and restored together, which is what makes "one undo step for
    /// the whole thing" true by construction rather than by three careful closures. It is deliberately
    /// *not* `withStructureUndo`: that bracket snapshots `layers`, `folders`, `viewPresets`,
    /// `motionGroups` and `guideStrokes` twice at a declared cost of 4096, which is the right price for
    /// a discrete structural pick and the wrong one for a channel edit made on every tick of a drag.
    struct KeyframeState: Equatable {
        var marks: [Int] = []
        var baselines: [String: Double] = [:]
        var tracks: [String: AnimationCurve] = [:]
    }

    /// **The target the keyframe writers address when nothing more specific is named: the current
    /// layer.**
    ///
    /// §2.22 puts the keyframe control in the timeline's control strip, and the timeline's own notion
    /// of "the thing you are working on" is `currentLayerIndex` — the highlighted row. §2.4 then makes
    /// the address exact: effect keys live *on the layer*, in absolute document frames, so there is no
    /// cel to disambiguate and the playhead supplies the rest.
    ///
    /// **A folder is a perfectly good `KeyframeTarget` and still is not this one.** Its grade animates
    /// (§2.21) and its sliders key like any layer's; what it does not have is a timeline row for the
    /// control to be *next to*, so "the folder the strip means" has no answer. Reaching a folder's
    /// channels from a list is the channel panel's job.
    var keyframeTarget: KeyframeTarget? { keyframeTarget(layerIndex: currentLayerIndex) }

    /// The target for one layer index, or nil if the index is not one. The index-to-id conversion in
    /// one place, so no caller does it by hand.
    func keyframeTarget(layerIndex: Int) -> KeyframeTarget? {
        layers.indices.contains(layerIndex) ? .layer(id: layers[layerIndex].id) : nil
    }

    /// The grade as **stored** on a target — presence, not value at a frame.
    ///
    /// `layerEffect` on the layer side rather than the raw `effect` field, because a `.raster` layer
    /// carrying a stale grade must not be treated as grading; on the folder side the field's presence
    /// *is* the effect-node form, so there is no second field to reconcile and stage 2b's overload
    /// makes the same call.
    func storedEffect(of target: KeyframeTarget) -> Effect? {
        switch target {
        case .layer(let id): return layers.first { $0.id == id }?.layerEffect
        case .folder(let id): return folders.first { $0.id == id }?.effect
        }
    }

    /// The grade at one frame — every keyed parameter evaluated, through whichever of the two
    /// resolvers this target owns.
    func resolvedEffect(of target: KeyframeTarget, atFrame frame: Int) -> Effect? {
        switch target {
        case .layer(let id): return layers.first { $0.id == id }?.layerEffect(atFrame: frame)
        case .folder(let id): return folders.first { $0.id == id }?.resolvedEffect(atFrame: frame)
        }
    }

    /// The target's own name, for a panel to say what it is about to write onto.
    func displayName(of target: KeyframeTarget) -> String {
        switch target {
        case .layer(let id): return layers.first { $0.id == id }?.name ?? "Layer"
        case .folder(let id): return folders.first { $0.id == id }?.name ?? "Group"
        }
    }

    /// Marks, baselines and curves as they stand. Answers with an empty state for a target that is not
    /// in the document rather than trapping, which is every other reader here.
    func keyframeState(of target: KeyframeTarget) -> KeyframeState {
        switch target {
        case .layer(let id):
            guard let layer = layers.first(where: { $0.id == id }) else { return KeyframeState() }
            return KeyframeState(marks: layer.keyframeMarks, baselines: layer.pendingBaselines,
                                 tracks: layer.effectTracks)
        case .folder(let id):
            guard let folder = folders.first(where: { $0.id == id }) else { return KeyframeState() }
            return KeyframeState(marks: folder.keyframeMarks, baselines: folder.pendingBaselines,
                                 tracks: folder.effectTracks)
        }
    }

    /// **The frames this target carries a keyframe on** — §2.26's bare marks, sorted.
    func keyframeMarks(of target: KeyframeTarget) -> [Int] { keyframeState(of: target).marks }

    /// Whether a keyframe already sits on `frame`. The predicate `KeyframeControl.write`'s third arm
    /// asks about, named so no caller writes `contains` by hand against an unsorted assumption.
    func hasKeyframeMark(_ target: KeyframeTarget, atFrame frame: Int) -> Bool {
        keyframeMarks(of: target).contains(frame)
    }

    /// **The ids of this target's effect channels that carry a curve at all**, in the descriptor
    /// table's order.
    ///
    /// **This is the loose predicate and it is what routing and the "hold this pose" walk use.** The
    /// strict one — the owner's "an animation" — is `listedAnimationChannelIDs` below;
    /// `AnimationCurve.isAnimated` carries the argument for why the two must stay apart.
    ///
    /// **The `effectTracks.isEmpty` guard is not merely an optimisation**, for `Effect.resolved`'s
    /// reason one file over: `Effect.parameters` rebuilds up to thirty-three closures on every call,
    /// and this is read from `AnimationTimeline`'s body, which SwiftUI re-evaluates on every
    /// `CanvasManager` publish — several times a scrub tick. The overwhelming majority of documents
    /// have no track at all, and for those this is one dictionary `isEmpty` and a return.
    func curvedEffectChannelIDs(of target: KeyframeTarget) -> [String] {
        channelIDs(of: target) { !$0.isEmpty }
    }

    /// **The ids that belong in the channel list the keyframe button opens** — the owner's definition
    /// of an animation, verbatim: *"animations will be added to the list when two keyframes are placed,
    /// and something changes in one keyframe which from the other."*
    ///
    /// Strictly narrower than `curvedEffectChannelIDs`: a channel keyed twice at the same value is a
    /// curve in force but is not yet an animation, and listing it would be offering the artist a graph
    /// with a flat line and no way to tell it from one they authored.
    func listedAnimationChannelIDs(of target: KeyframeTarget) -> [String] {
        channelIDs(of: target) { $0.isAnimated }
    }

    /// Whether one channel is an animation by the list's definition — `listedAnimationChannelIDs` for
    /// a single id, without building the array.
    func channelIsAnimated(_ target: KeyframeTarget, parameterID: String) -> Bool {
        keyframeState(of: target).tracks[parameterID]?.isAnimated ?? false
    }

    /// The shared walk behind the two predicates above. Over `parameters` rather than over the track
    /// dictionary, which is `Effect.resolved`'s rule and buys the descriptor table's deterministic
    /// order plus the `isScalarAnimatable` refusal in one place.
    private func channelIDs(of target: KeyframeTarget,
                            where matches: (AnimationCurve) -> Bool) -> [String] {
        let tracks = keyframeState(of: target).tracks
        guard !tracks.isEmpty, let effect = storedEffect(of: target) else { return [] }
        return effect.parameters.compactMap { parameter in
            guard parameter.isScalarAnimatable, let curve = tracks[parameter.id], matches(curve)
            else { return nil }
            return parameter.id
        }
    }

    /// **Where one edit to `parameter` on `target` should go**, with `KeyframeControl.write`'s four
    /// inputs read off the model rather than assembled by a view.
    ///
    /// The rule is a pure function so a logic test can reach it; *this* is the seam that keeps the
    /// caller from handing it the wrong four values. `Views/DrawingView.swift` is not in the test
    /// target, so a routing bug built there would be invisible to the fast tier.
    func keyframeWrite(_ target: KeyframeTarget, parameter: EffectParameter,
                       atFrame frame: Int) -> KeyframeControl.Write {
        let state = keyframeState(of: target)
        return KeyframeControl.write(
            isScalarAnimatable: parameter.isScalarAnimatable,
            channelHasCurve: state.tracks[parameter.id]?.isEmpty == false,
            markCount: state.marks.count,
            playheadIsOnMark: state.marks.contains(frame))
    }

    /// **Writes the grade back onto whichever of the two homes `target` names.**
    ///
    /// The one place the layer/folder split still shows on this path. The layer arm resolves the index
    /// *here*, at write time, rather than taking one from a caller — a restack while a settings bar is
    /// open would otherwise send the write to a neighbour.
    func setStoredEffect(of target: KeyframeTarget, to effect: Effect) {
        switch target {
        case .layer(let id):
            guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
            setLayerEffect(layerIndex: index, to: effect)
        case .folder(let id):
            setNodeEffect(id, to: effect)
        }
    }

    /// **One settings-bar edit, routed and performed** — `KeyframeControl.write`'s five arms with the
    /// four inputs read off the model and each arm's write carried out.
    ///
    /// **This lives in the model rather than in the settings bar's callback, and that is not tidiness.**
    /// `Views/DrawingView.swift` is not compiled into `PaintSoftwareUITests`, so a `switch` written
    /// there is a decision the fast tier cannot see: the rule would be pinned and the wiring that feeds
    /// it would not, which is the shape `KeyframeControl`'s own doc comment warns about. Everything the
    /// view is left holding is which slider moved and by how much.
    ///
    /// - Returns: the arm that was taken, so the caller can label its undo bracket — a drag that wrote
    ///   keys is `.effectKeyframes` and a drag that wrote a value is `.valueLayerEffect`, and an artist
    ///   who animated a bloom must not read "Adjust Layer Effect" and conclude the grade itself has
    ///   gone.
    @discardableResult
    func applyEffectParameterEdit(_ target: KeyframeTarget, parameter: EffectParameter,
                                  newValue: Double, atFrame frame: Int) -> KeyframeControl.Write {
        let route = keyframeWrite(target, parameter: parameter, atFrame: frame)
        // **The stored grade, never the resolved one.** The knobs show the value at the playhead;
        // writing that back would bake every *other* animated channel's value-at-this-frame into the
        // stored base as a side effect of dragging one slider. That base is invisible for as long as
        // its curve exists, so the corruption would surface much later, when the artist deleted the
        // curve and found a number they never typed.
        let stored = storedEffect(of: target)

        switch route {
        case .key:
            setEffectParameterKeys(target, frame: frame, values: [parameter.id: newValue])
        case .seedAndKey:
            // The old value comes from the stored grade because this channel has no curve to resolve
            // through — that absence is what put the edit in this arm.
            if let stored, let old = parameter.read(stored) {
                seedAndKeyChannel(target, parameterID: parameter.id,
                                  oldValue: old, newValue: newValue, atFrame: frame)
            }
        case .storedValueHoldingBaseline:
            // Both halves, and the ordinary write is not optional: a provisional edit that is never
            // committed is lost work, and a slider that means two different things depending on
            // invisible state is worse than either.
            if let stored {
                if let old = parameter.read(stored) {
                    holdBaseline(target, parameterID: parameter.id, value: old)
                }
                setStoredEffect(of: target, to: parameter.write(stored, newValue))
            }
        case .storedValue:
            if let stored { setStoredEffect(of: target, to: parameter.write(stored, newValue)) }
        }
        return route
    }

    // MARK: - The writers

    /// **Records the value a channel held before this edit** — `KeyframeControl.Write`'s
    /// `.storedValueHoldingBaseline` arm, and the owner's *"the previous value is held"*.
    ///
    /// **Written once per channel per keyframe cycle.** The first edit after a mark is the only one
    /// that knows the value at A; every later tick of the same drag reads a base this edit already
    /// moved, so a later write would replace the true baseline with a value the artist never sat on.
    /// An existing entry is therefore kept, and the call is free.
    ///
    /// **Records no undo step of its own, deliberately.** It changes no rendered value — nothing
    /// resolves through it until a keyframe lands — and it never travels alone: every call site pairs
    /// it with the ordinary value write, which is inside a bracket that has already snapshotted
    /// `layers` and `folders` wholesale and therefore restores this too. A step of its own would split
    /// one slider drag in two, which is the failure `setEffectParameterTrack` states the rule against.
    ///
    /// - Returns: whether anything was recorded.
    @discardableResult
    func holdBaseline(_ target: KeyframeTarget, parameterID: String, value: Double) -> Bool {
        var state = keyframeState(of: target)
        guard state.baselines[parameterID] == nil else { return false }
        state.baselines[parameterID] = value
        applyKeyframeState(state, to: target)
        return true
    }

    /// **Creates a channel from nothing with the old value on its neighbouring marks and the new value
    /// at the playhead** — `KeyframeControl.Write`'s `.seedAndKey` arm.
    ///
    /// This is the owner's *"the user modifies another slider while on B"*: A and B both exist, the
    /// artist is standing on one of them, and the value they are moving *away from* is what the other
    /// mark should hold. Doing it in one write rather than as "hold a baseline now, commit it later" is
    /// what makes that gesture produce an animation without a third keyframe press.
    ///
    /// **Only the immediate neighbours are seeded, and that is behaviourally identical to seeding every
    /// mark.** `AnimationCurve` extrapolates as a **constant hold** outside its first and last key
    /// (documented decision 2 there), so a value placed on the nearest mark below already holds at every
    /// mark below that, and likewise above. Fewer keys, same curve. Do not "fix" this to seed all — it
    /// would put keys on frames the artist never touched and make every one of them a handle to drag.
    ///
    /// - Returns: whether the document changed.
    @discardableResult
    func seedAndKeyChannel(_ target: KeyframeTarget, parameterID: String,
                           oldValue: Double, newValue: Double, atFrame frame: Int) -> Bool {
        guard let parameter = storedEffect(of: target)?.parameters.first(where: { $0.id == parameterID }),
              parameter.isScalarAnimatable
        else { return false }

        var state = keyframeState(of: target)
        let before = state
        state.tracks[parameterID] = Self.seeded(state.tracks[parameterID], marks: state.marks,
                                                frame: frame, oldValue: oldValue, newValue: newValue)
        // A channel that seeds is a channel that no longer needs its held value.
        state.baselines.removeValue(forKey: parameterID)
        guard state != before else { return false }

        commitKeyframeState(state, from: before, to: target, label: .effectKeyframes)
        return true
    }

    /// **Places a keyframe on `frame`** — §2.26's whole write, and one undo step for all of it.
    ///
    /// Three things happen, in this order:
    ///
    /// 1. **The mark is recorded**, if it is not already there. A mark with no channel is legal and is
    ///    the point: *"keyframe A is added, nothing is saved."*
    /// 2. **Every held baseline is committed and cleared.** The old value goes onto the nearest mark
    ///    below and the nearest mark above (whichever exist — see `seedAndKeyChannel` for why only the
    ///    immediate neighbours), and the channel's **current stored value** goes on `frame`. This is
    ///    the owner's *"that previous value gets saved to A and the new value gets saved to B and the
    ///    held value is discarded."*
    /// 3. **Every channel that already had a curve gets a key on `frame` holding the value it
    ///    resolves to there** — §2.24's "hold this pose here", read off the *resolved* grade rather than
    ///    the stored one, which is the difference between holding what is on screen and holding what
    ///    was typed before anything was animated. Without it, placing a new mark lets every other
    ///    animated channel drift through it.
    ///
    /// **Placing a mark on a frame that already has one is not a no-op.** The mark itself does not
    /// change, but steps 2 and 3 still run — which is the owner's *"modifies another slider while on
    /// B"* reached by a second press instead of by the seed arm, and refusing it would make a keyframe
    /// press silently do nothing at the exact moment the artist expects it to save their edit.
    ///
    /// **A target with no grade at all still takes the mark.** A mark is a point in time rather than a
    /// property of an effect, and the later stages key transforms and object channels onto the same
    /// marks.
    ///
    /// - Returns: whether the document changed.
    @discardableResult
    func addKeyframe(_ target: KeyframeTarget, atFrame frame: Int) -> Bool {
        guard targetExists(target) else { return false }

        let before = keyframeState(of: target)
        var state = before

        if !state.marks.contains(frame) {
            state.marks.append(frame)
            state.marks.sort()
        }

        if let stored = storedEffect(of: target) {
            let resolved = resolvedEffect(of: target, atFrame: frame)
            for parameter in stored.parameters where parameter.isScalarAnimatable {
                if let baseline = before.baselines[parameter.id] {
                    // 2. Commit the held value. `stored`, not `resolved`: this channel has no curve to
                    // resolve through — that is what made it a baseline rather than an auto-key.
                    guard let current = parameter.read(stored) else { continue }
                    state.tracks[parameter.id] = Self.seeded(state.tracks[parameter.id],
                                                             marks: state.marks, frame: frame,
                                                             oldValue: baseline, newValue: current)
                } else if before.tracks[parameter.id]?.isEmpty == false {
                    // 3. Hold the pose. Skipped for a channel that just seeded, whose key on `frame`
                    // is the artist's new value and must not be overwritten by the old one resolved
                    // through the curve that write just created.
                    guard let resolved, let value = parameter.read(resolved) else { continue }
                    var curve = state.tracks[parameter.id] ?? AnimationCurve()
                    curve.setKey(AnimationCurve.Key(frame: frame, value: value))
                    state.tracks[parameter.id] = curve
                }
            }
        }
        state.baselines = [:]

        guard state != before else { return false }
        commitKeyframeState(state, from: before, to: target, label: .addKeyframe)
        return true
    }

    /// **Drops the mark on `frame` and every channel's key on it**, as one undo step.
    ///
    /// Both halves, because the artist asked for the keyframe to go: leaving the keys behind would
    /// take the marker off the timeline and leave the animation doing exactly what it did, which is
    /// the shape of a control that appears not to work. A channel left with no keys is removed rather
    /// than stored empty — `setEffectParameterTrack`'s rule, and the state that would otherwise show
    /// up in the channel list animating nothing.
    ///
    /// - Returns: whether the document changed.
    @discardableResult
    func removeKeyframe(_ target: KeyframeTarget, atFrame frame: Int) -> Bool {
        clearKeyframes(target, inFrames: frame ..< (frame + 1), label: .removeKeyframe)
    }

    /// **Drops every mark and every key in a half-open frame range**, as one undo step.
    ///
    /// The owner's *"clear all keyframes in that cel"* resolves to the frames that cel block covers,
    /// and **the caller supplies that range rather than this function deriving it**: a layer channel is
    /// in absolute document frames (§2.4) and has no cel to ask, so a cel-derived range is the caller's
    /// knowledge, not this writer's.
    ///
    /// - Returns: whether the document changed.
    @discardableResult
    func clearKeyframes(_ target: KeyframeTarget, inFrames frames: Range<Int>) -> Bool {
        clearKeyframes(target, inFrames: frames, label: .clearKeyframes)
    }

    /// The body of both, with the label the artist reads passed in — "remove keyframe" and "clear
    /// keyframes" are the same edit and two different things to want back.
    @discardableResult
    private func clearKeyframes(_ target: KeyframeTarget, inFrames frames: Range<Int>,
                                label: HistoryActionLabel) -> Bool {
        guard targetExists(target), !frames.isEmpty else { return false }

        let before = keyframeState(of: target)
        var state = before
        state.marks.removeAll { frames.contains($0) }
        for (id, curve) in state.tracks {
            var trimmed = curve
            for frame in frames { trimmed.removeKey(atFrame: frame) }
            if trimmed.isEmpty { state.tracks.removeValue(forKey: id) } else { state.tracks[id] = trimmed }
        }

        guard state != before else { return false }
        commitKeyframeState(state, from: before, to: target, label: label)
        return true
    }

    /// **Inserts or replaces one key on each of several channels of one target, as one undo step** —
    /// the write `setEffectParameterTrack` was missing, and the one the auto-key arm leans on.
    ///
    /// **Why not `setEffectParameterTrack` in a loop.** Two reasons, and the second is the one that
    /// bites. It is a *whole-curve* replace, so a caller would have to read, mutate and hand back the
    /// curve at each of `n` channels — fine. But it records **one undo step per call**, so a single
    /// keyframe press would cost the artist one press of Undo per animated channel to take back.
    /// `bakePreciseStrokes` states the rule this follows: collect the edits, mutate, register **one**
    /// `recordUndo` over all of them, *"rather than registering per cel, which would cost the artist
    /// one press per cel to take back a single menu tap."*
    ///
    /// **The walk is over `parameters`, never over `values`**, which is `Effect.resolved`'s rule and
    /// buys the same three things: an id this effect does not have is ignored rather than stored, the
    /// order is the table's and therefore deterministic, and the `isScalarAnimatable` refusal lives in
    /// exactly one place — a track that would store and render nothing cannot be created here any more
    /// than it can at either `setEffectParameterTrack`.
    ///
    /// **Records nothing while an enclosing bracket is open**: a slider drag opens a structure gesture,
    /// that gesture has already snapshotted `layers` *and* `folders`, so a step here would split one
    /// drag into two. The enclosing `commitStructureGesture` supplies the label — see `DrawingView`,
    /// which passes `.effectKeyframes` when the drag wrote keys and `.valueLayerEffect` when it wrote
    /// a value.
    ///
    /// - Returns: how many channels actually changed. A key identical to one already on that frame is
    ///   not a change and is not counted, so a second press on an unmoved playhead records no undo step.
    @discardableResult
    func setEffectParameterKeys(_ target: KeyframeTarget, frame: Int,
                                values: [String: Double]) -> Int {
        guard !values.isEmpty, let effect = storedEffect(of: target) else { return 0 }

        let before = keyframeState(of: target)
        var state = before
        var changed = 0

        for parameter in effect.parameters {
            guard parameter.isScalarAnimatable, let value = values[parameter.id] else { continue }
            let existing = state.tracks[parameter.id]
            var curve = existing ?? AnimationCurve()
            curve.setKey(AnimationCurve.Key(frame: frame, value: value))
            guard curve != existing else { continue }
            state.tracks[parameter.id] = curve
            changed += 1
        }
        guard changed > 0 else { return 0 }

        commitKeyframeState(state, from: before, to: target, label: .effectKeyframes)
        return changed
    }

    // MARK: - Shared machinery

    private func targetExists(_ target: KeyframeTarget) -> Bool {
        switch target {
        case .layer(let id): return layers.contains { $0.id == id }
        case .folder(let id): return folders.contains { $0.id == id }
        }
    }

    /// `existing` with `oldValue` keyed onto the marks either side of `frame` and `newValue` on
    /// `frame` itself.
    ///
    /// **A neighbour that already carries a key is left alone.** That key is a value the artist
    /// authored or a pose a previous keyframe held, and overwriting it with a baseline would move a
    /// point of the curve nobody asked to move. `frame`'s own key *is* replaced, because that is the
    /// edit being made.
    private static func seeded(_ existing: AnimationCurve?, marks: [Int], frame: Int,
                               oldValue: Double, newValue: Double) -> AnimationCurve {
        var curve = existing ?? AnimationCurve()
        if let below = marks.last(where: { $0 < frame }), curve.key(atFrame: below) == nil {
            curve.setKey(AnimationCurve.Key(frame: below, value: oldValue))
        }
        if let above = marks.first(where: { $0 > frame }), curve.key(atFrame: above) == nil {
            curve.setKey(AnimationCurve.Key(frame: above, value: oldValue))
        }
        curve.setKey(AnimationCurve.Key(frame: frame, value: newValue))
        return curve
    }

    /// Applies a new state and records the one undo step that takes it back.
    ///
    /// **Deliberately not routed through `withStructureUndo`**, for `setEffectParameterTrack`'s reason
    /// verbatim: that bracket snapshots `layers`, `folders`, `viewPresets`, `motionGroups` and
    /// `guideStrokes` twice at a declared cost of 4096, which is the right price for a discrete
    /// structural pick and the wrong one for a channel edit made on every tick of a slider drag.
    private func commitKeyframeState(_ state: KeyframeState, from before: KeyframeState,
                                     to target: KeyframeTarget, label: HistoryActionLabel) {
        // Every document edit is a canvas edit: a pending shape/fill/text transient bakes first, as its
        // own earlier step. Re-entrant-safe, so calling it inside a bracket that already did is free.
        beginCanvasEdit()
        applyKeyframeState(state, to: target)

        guard structureUndoDepth == 0, gestureSnapshot == nil else { return }
        recordUndo(label: label, cost: Self.stateUndoCost(before) + Self.stateUndoCost(state),
                   undo: { [weak self] in self?.applyKeyframeState(before, to: target) },
                   redo: { [weak self] in self?.applyKeyframeState(state, to: target) })
    }

    /// The one mutation every direction of every undo above goes through. **The target is re-resolved
    /// on every call rather than captured as a position**, which is what `KeyframeTarget`'s all-ids
    /// shape buys: a restack between the edit and the undo moves an index and cannot move an id, and a
    /// folder deleted and restored is a different slot in `folders` under the same id.
    private func applyKeyframeState(_ state: KeyframeState, to target: KeyframeTarget) {
        switch target {
        case .layer(let id):
            guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
            layers[index].keyframeMarks = state.marks
            layers[index].pendingBaselines = state.baselines
            layers[index].effectTracks = state.tracks
        case .folder(let id):
            guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
            folders[index].keyframeMarks = state.marks
            folders[index].pendingBaselines = state.baselines
            folders[index].effectTracks = state.tracks
        }
    }

    /// `CanvasManager.trackUndoCost` summed over a whole state — the same 64 + 96·keys estimate per
    /// curve, plus a few bytes an `Int` mark and a `Double` baseline each cost. The same point about it
    /// applies: what matters is that it is *small*, so a session that keyframes heavily costs the
    /// history what a couple of structural edits do rather than what one whole-cel snapshot does.
    private static func stateUndoCost(_ state: KeyframeState) -> Int {
        state.tracks.values.reduce(0) { $0 + 64 + 96 * $1.keys.count }
            + 8 * state.marks.count
            + 72 * state.baselines.count
    }
}
