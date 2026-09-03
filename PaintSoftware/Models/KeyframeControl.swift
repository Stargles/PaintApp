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
    /// **The keyframes carry the state**: a keyframe is placed, edits are made, another keyframe is
    /// placed, and the pair of them is the animation. So "what does this edit do" is answered by where
    /// the playhead stands relative to the target's keyframes — document state the artist can see on
    /// the timeline — rather than by a flag they have to remember they set.
    ///
    /// 1. **Not scalar-animatable → `.storedValue`.** The stepped, array and colour parameters
    ///    (`EffectParameter.isScalarAnimatable` names why for each of the nine) are refused here as
    ///    well as at the resolver, so the app cannot reach a track that stores and renders nothing.
    /// 2. **The channel already has a curve → `.key`.** This is the auto-key arm and it takes
    ///    precedence over everything below it.
    /// 3. **Keyframes exist and the playhead is on one, with another to seed onto → `.seedAndKey`.**
    /// 4. **Keyframes exist and the playhead is not on one (or is on the only one) → hold the
    ///    baseline.**
    /// 5. **No keyframes at all → `.storedValue`.** On a document nobody has keyframed a slider is a
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
    /// **`keyframeCount` rather than a bare `hasKeyframes`, and that is arm 3's whole correctness.**
    /// Seeding needs a *neighbouring* keyframe to put the old value on, and when the playhead's is the
    /// only one there is none — seeding would then produce a one-key curve pinning the new value, and
    /// the artist's old value would be lost with nothing on screen to explain it. The owner's canonical
    /// story is exactly that case: *"keyframe A is added, nothing is saved. A slider is then adjusted.
    /// The previous value is held. Then keyframe B is added"* — so with one keyframe the answer must be
    /// arm 4, and the value reaches A when B lands. `playheadIsOnKeyframe && keyframeCount > 1` is the
    /// same statement as "there is a keyframe other than this one", because the playhead's own is in
    /// the count.
    ///
    /// **Both counts are of `CanvasManager.keyframeFrames(of:)` — marks *and* keyed frames.** A frame a
    /// channel keys on with no mark beside it is a keyframe the artist placed with a slider, and
    /// counting only the stored marks is what made an edit at the last of three keyframes seed onto the
    /// first.
    static func write(isScalarAnimatable: Bool,
                      channelHasCurve: Bool,
                      keyframeCount: Int,
                      playheadIsOnKeyframe: Bool) -> Write {
        guard isScalarAnimatable else { return .storedValue }
        if channelHasCurve { return .key }
        guard keyframeCount > 0 else { return .storedValue }
        return (playheadIsOnKeyframe && keyframeCount > 1) ? .seedAndKey : .storedValueHoldingBaseline
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

    /// **The container pose as stored on a target** — §4.4's transformation layer on the layer side,
    /// §2.21's folder twin on the other. `storedEffect(of:)`'s shape one payload over, including its
    /// asymmetry: `layerTransform` rather than the raw field, because a `.raster` layer carrying a
    /// pose left behind by a kind change poses nothing, while a folder's field's presence *is* the
    /// answer and there is no second field to reconcile.
    func containerPose(of target: KeyframeTarget) -> LayerPose? {
        switch target {
        case .layer(let id): return layers.first { $0.id == id }?.layerTransform
        case .folder(let id): return folders.first { $0.id == id }?.transform
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

    /// **A keyframe is any frame the target marks explicitly *or* any of its channels holds a key on**,
    /// ascending and unique — the one accessor, and the only definition.
    ///
    /// **The two lists cannot disagree, because they are disjoint.** A mark is stored *only* for a
    /// frame no channel keys (`marks(_:droppingKeyed:)`), so this union is a partition rather than an
    /// overlap: a key is the keyframe wherever there is one, and a mark is the keyframe everywhere
    /// else. That is what makes the owner's rule of 2026-09-03 true by construction — *"if a node
    /// exists on the graph editor, it should also exist on the cel as an indicator and vice versa"* —
    /// and it is what replaced §2.28's original arrangement, where a mark survived its key being
    /// dragged away in the graph editor and drew a keyframe with nothing under it.
    ///
    /// **A target with no grade contributes no curves, and that asymmetry is deliberate.**
    /// `storedEffect(of:)`'s rule: a layer that is not in effect form grades nothing, so tracks left on
    /// it by a kind change are storage rather than animation and must not draw a marker for a value the
    /// canvas is not showing. A **mark** is not a value at all — `addKeyframe` takes one on a target
    /// with no grade whatsoever, and later stages key transforms onto the same marks — so gating those
    /// would hide the entire first step of the workflow on every ordinary drawing layer.
    ///
    /// **The pose channels are part of this too, and stage 5 is where that stopped being theoretical.**
    /// A transform key is a key — the two device reports that produced §2.28 were both the timeline and
    /// the model asking different questions, and a pose channel omitted here would reproduce both of
    /// them exactly (a diamond with no Remove Keyframe, and a seed arm stepping over a frame the artist
    /// can see). The keys live on the layer's *cels* in cel-local frames (§3.1) and are converted by
    /// `poseKeyframeFrames(inLayer:)`, which is the one place that conversion happens.
    func keyframeFrames(of target: KeyframeTarget) -> [Int] {
        let state = keyframeState(of: target)
        return keyframeFrames(of: target, marks: state.marks, tracks: state.tracks)
    }

    /// **The same union, taken against marks and curves a writer is holding mid-edit** — which is the
    /// only other shape anything is allowed to ask this in.
    ///
    /// `addKeyframe` needs the union over its *new* marks and its *old* curves, and `seedAndKeyChannel`
    /// needs it before it writes; neither can go through `keyframeFrames(of:)`, which re-reads the
    /// document. **Both of them used to call a static form** whose `poseFrames` defaulted to empty — so
    /// the union had two spellings in one file, one of which could not see a pose key. That is
    /// precisely the divergence §2.28 exists to forbid, and its two symptoms are the ones the owner
    /// reported: the neighbour search steps over a keyframe the artist can see, and the seed arm writes
    /// onto the wrong one. The static form is gone and this stands in its place, so the pose frames
    /// cannot be forgotten by omission.
    func keyframeFrames(of target: KeyframeTarget,
                        marks: [Int], tracks: [String: AnimationCurve]) -> [Int] {
        var frames = keyedFrames(of: target, tracks: tracks)
        frames.formUnion(marks)
        return frames.sorted()
    }

    /// **The frames some channel of `target` holds a key on** — the keyed half of the union above, and
    /// the predicate `marks(_:droppingKeyed:)` prunes against.
    ///
    /// **The `isEmpty` fast paths are what make this affordable from a SwiftUI body.** The overwhelming
    /// majority of documents carry no track at all, and for those this is one dictionary `isEmpty` and
    /// one per-cel `isEmpty` per cel; for one that does it is a walk of the curves' own key arrays and
    /// never a call to `Effect.parameters`, which rebuilds up to thirty-three closures.
    func keyedFrames(of target: KeyframeTarget) -> Set<Int> {
        keyedFrames(of: target, tracks: keyframeState(of: target).tracks)
    }

    /// The same, against a track dictionary the caller is holding mid-edit.
    func keyedFrames(of target: KeyframeTarget, tracks: [String: AnimationCurve]) -> Set<Int> {
        var keyed: Set<Int> = []
        if !tracks.isEmpty, storedEffect(of: target) != nil {
            for curve in tracks.values {
                for key in curve.keys { keyed.insert(key.frame) }
            }
        }
        // A pose key is a landed key exactly as a curve key is. Ungated by the grade, unlike the
        // effect curves: a pose channel is not a property of an effect at all, so a drawing layer with
        // no grade whatsoever still carries its transform keys.
        //
        // **A folder holds no cels, so it holds no *object* channels — and since §4.4 it holds a
        // container pose of its own, which this used to miss.** The comment here said "a folder holds
        // no cels, so it holds no object channels" and stopped, which was true and was read as
        // exhaustive; `LayerFolder.transform` arrived afterwards with a `TransformTrack` on it, and a
        // key on a folder's pose therefore drew a node in the graph editor with no indicator beside
        // it. That is §2.28's biconditional broken through the door §2.28 could not have known about.
        // `poseKeyframeFrames(inLayer:)` folds the layer's own container pose for the same reason.
        switch target {
        case .layer(let id): keyed.formUnion(poseKeyframeFrames(inLayer: id))
        case .folder(let id): keyed.formUnion(poseKeyframeFrames(inFolder: id))
        }
        return keyed
    }

    /// **A mark on a frame some channel keys is redundant, and it goes** — the owner's rule of
    /// 2026-09-03, and the one line that keeps the two lists from ever coming apart.
    ///
    /// It supersedes the last paragraph of §2.28, which said the opposite in as many words: *"a key is
    /// a value some channel holds and a mark is the artist saying this frame is a keyframe, and the two
    /// come apart the moment that key is dragged or deleted in the graph editor."* They did, and what
    /// the artist saw was a keyframe indicator on a cel with no node under it in the graph editor —
    /// reported three times. **A mark that has been keyed can therefore never be orphaned by a later
    /// edit, because it is no longer there to orphan.**
    ///
    /// Nothing is lost by dropping it. A mark is only ever load-bearing while it is *un*keyed: once a
    /// channel keys the frame, every question anything asks — is there a keyframe here, how many are
    /// there, which is nearest below, draw a diamond — is answered by the key. §2.26's *"keyframe A is
    /// added, nothing is saved"* is exactly the un-keyed case, which is why `keyframeMarks` still
    /// exists and cannot be deleted outright.
    ///
    /// - Parameter keyed: every frame a channel keys **before or after** the write being made. Both
    ///   halves: the "after" set is what stops a mark being written under a key, and the "before" set
    ///   is what makes a key dragged *off* a marked frame take the mark with it, which is the reported
    ///   symptom and is also how a document saved under the old rule heals itself on first touch.
    static func marks(_ marks: [Int], droppingKeyed keyed: Set<Int>) -> [Int] {
        guard !marks.isEmpty, !keyed.isEmpty else { return marks }
        return marks.filter { !keyed.contains($0) }
    }

    /// Whether a keyframe already sits on `frame`. The predicate `KeyframeControl.write`'s third arm
    /// asks about, named so no caller writes `contains` by hand against an unsorted assumption.
    func hasKeyframe(_ target: KeyframeTarget, atFrame frame: Int) -> Bool {
        keyframeFrames(of: target).contains(frame)
    }

    /// Whether any keyframe sits inside a half-open frame range — `clearKeyframes(_:inFrames:)`'s
    /// question asked without performing it, so the cel menu can offer "Clear Keyframes" only when
    /// there is something for it to clear.
    ///
    /// **A range query rather than a container lookup, because a cel does not contain keyframes.**
    /// §2.4 and §2.26 both put keys and marks on the *layer*, in absolute document frames, so "the
    /// keyframes in that cel" means the ones whose frame falls in the span that cel block covers —
    /// which is `celFrameRange(layerIndex:celIndex:)`, and is the caller's knowledge rather than
    /// this predicate's.
    func hasKeyframe(_ target: KeyframeTarget, inFrames frames: Range<Int>) -> Bool {
        keyframeFrames(of: target).contains { frames.contains($0) }
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
    /// **Effect channels only, and it stays that way after §11.7 while `listedAnimationChannelIDs`
    /// does not.** Its one caller is `DrawingView`'s `animatedChannelIDs`, which marks the *sliders*
    /// in the effect settings bar that carry a curve — a pose channel has no slider, so adding one
    /// here would put an id in a set nothing can match while making the name a lie. The name is the
    /// contract.
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
    /// **And since KEYFRAMES.md §11.7 it lists the pose channels too**, which is what the band draws
    /// and is therefore what this has to say. The grade's channels first and the poses after, which
    /// is `graphBandListing(of:)`'s order and the only place that order is decided — the two are
    /// pinned equal by `TimelineGraphBandLogicTests`, in both directions, because two
    /// implementations of one invariant is the defect §2.28 was written about.
    ///
    /// **Per *component*, not per track.** A track is animated the moment two of its keys hold
    /// different poses, but a pure translation leaves Scale X, Scale Y, Rotation and Skew flat — so a
    /// track-level answer here would list four channels the band draws as dashed flat lines and call
    /// them animations. The predicate is the same one every other channel gets, applied to the
    /// synthesised sub-curve: `AnimationCurve.isAnimated`.
    func listedAnimationChannelIDs(of target: KeyframeTarget) -> [String] {
        let grade = channelIDs(of: target) { $0.isAnimated }
        let sources = poseSources(of: target)
        guard !sources.isEmpty else { return grade }
        return grade + TimelineGraphBand.poseChannels(sources, descriptorOffset: 0)
            .channels.filter(\.isAnimated).map(\.parameterID)
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
        let placed = keyframeFrames(of: target)
        return KeyframeControl.write(
            isScalarAnimatable: parameter.isScalarAnimatable,
            channelHasCurve: keyframeState(of: target).tracks[parameter.id]?.isEmpty == false,
            keyframeCount: placed.count,
            playheadIsOnKeyframe: placed.contains(frame))
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
    /// keyframe.** `AnimationCurve` extrapolates as a **constant hold** outside its first and last key
    /// (documented decision 2 there), so a value placed on the nearest keyframe below already holds at
    /// every one below that, and likewise above. Fewer keys, same curve. Do not "fix" this to seed all —
    /// it would put keys on frames the artist never touched and make every one a handle to drag.
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
        let placed = keyframeFrames(of: target, marks: state.marks, tracks: state.tracks)
        state.tracks[parameterID] = Self.seeded(state.tracks[parameterID], keyframes: placed,
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
    ///
    ///    **And it does not survive steps 2 and 3 keying the frame it names.** `commitKeyframeState`
    ///    prunes it — `marks(_:droppingKeyed:)` — so a press that lands a key stores the key alone.
    ///    This reverses §2.28's closing paragraph, which kept the mark on the grounds that *"a key is
    ///    a value some channel holds and a mark is the artist saying this frame is a keyframe"*: true,
    ///    but what it bought was a keyframe indicator that outlived the node under it, which the owner
    ///    reported three times. The guard here therefore stays what it always was, a dedupe of `marks`
    ///    against itself; the pruning is one level down, where every writer reaches it.
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
        // **The neighbour search's view of the timeline, taken once.** Three things it must be: the
        // *union*, so a keyframe the artist placed with a slider is a neighbour like any other; a
        // snapshot of `before.tracks` rather than of the tracks being written, because seeding one
        // channel adds keys and would otherwise move the next channel's neighbour — an order
        // dependence over a dictionary, which has none; and **§2.28's union including the pose
        // channels**, which is what `keyframeFrames(of:marks:tracks:)` supplies and what the static
        // two-argument form silently did not. It feeds `poseDeltaForKeyframe` below as well as the
        // effect loop, so a pose key missing from it seeds a pose baseline onto the wrong frame — or,
        // when it is the only other keyframe there is, onto no frame at all, discarding the baseline
        // and the animation with it.
        let placed = keyframeFrames(of: target, marks: state.marks, tracks: before.tracks)

        if let stored = storedEffect(of: target) {
            let resolved = resolvedEffect(of: target, atFrame: frame)
            for parameter in stored.parameters where parameter.isScalarAnimatable {
                if let baseline = before.baselines[parameter.id] {
                    // 2. Commit the held value. `stored`, not `resolved`: this channel has no curve to
                    // resolve through — that is what made it a baseline rather than an auto-key.
                    guard let current = parameter.read(stored) else { continue }
                    state.tracks[parameter.id] = Self.seeded(state.tracks[parameter.id],
                                                             keyframes: placed, frame: frame,
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

        let (poses, posesBefore) = poseDeltaForKeyframe(target, atFrame: frame, keyframes: placed)

        guard state != before || !poses.isEmpty else { return false }
        commitKeyframeState(state, from: before, to: target, label: .addKeyframe,
                            poses: poses, posesBefore: posesBefore)
        return true
    }

    /// **Steps 2 and 3 again, in the pose channel's own currency** — KEYFRAMES.md stage 5.
    ///
    /// The effect loop above walks the grade's descriptors; this walks the layer's *cels*, because a
    /// transform channel lives on the cel in cel-local frames (§3.1) while a grade's lives on the
    /// layer in absolute ones. Everything else is the same two steps:
    ///
    /// 2. **Every held pose is committed and cleared.** The baseline — where the drawing *was* — goes
    ///    onto the nearest keyframe below and above, and the channel's current stored value goes on
    ///    this frame. A pose channel's stored value is always the **resting** pose, because its base
    ///    is the cel's own geometry (`CanvasManager.CelPoseState` carries that argument), so there is
    ///    no `parameter.read(stored)` to do here — the value is known.
    /// 3. **Every channel that already has a track takes a key holding the pose it resolves to
    ///    here**, §2.24's surviving half. Without it, placing a new mark lets an animated drawing
    ///    drift straight through it.
    ///
    /// **A cel takes a key only for a mark inside its own span.** Cel-local frame `n` on a cel of
    /// `frameCount` frames means the mark is on that cel; a mark before or after it addresses a
    /// different cel, or none, and keying there would put a handle at a negative frame that nothing
    /// can draw and `splitCel`'s rule would then have to carry.
    private func poseDeltaForKeyframe(_ target: KeyframeTarget, atFrame frame: Int,
                                      keyframes placed: [Int]) -> (KeyframePoseDelta, KeyframePoseDelta) {
        var after = KeyframePoseDelta()
        var before = KeyframePoseDelta()

        // **The container's channel first, and it belongs to both homes.** §3.1: it keys in absolute
        // document frames, so there is no cel span to fall inside and no conversion to make — which
        // is also why it sits outside the loop rather than inside it. A folder reaches only this
        // half, because it holds no cels.
        if let container = containerPose(of: target), !container.track.isEmpty || container.baseline != nil {
            var now = container
            if let baseline = container.baseline {
                now.track = CanvasManager.seedingContainer(now.track, keyframes: placed, frame: frame,
                                                           oldPose: baseline, newPose: container.pose)
                now.baseline = nil
            } else {
                // §2.24's surviving half: a channel that already has a curve takes a key holding the
                // pose it *resolves* to here, or placing a mark lets the container drift straight
                // through it.
                if let resolved = now.track.pose(atDocumentFrame: frame) {
                    now.track.setKey(TransformTrack.Key(frame: frame, pose: resolved))
                }
            }
            if now != container {
                before.container = container
                after.container = now
            }
        }

        guard case .layer(let layerID) = target,
              let index = layers.firstIndex(where: { $0.id == layerID }) else { return (after, before) }

        for cel in layers[index].cels {
            guard !cel.transformTracks.isEmpty || !cel.pendingPoseBaselines.isEmpty else { continue }
            // §2.18 again: an in-between carries no object channels, so a mark on one keys nothing.
            guard cel.interpolation == nil else { continue }
            let local = frame - cel.startFrame
            guard local >= 0, local < cel.frameCount else { continue }
            let localKeyframes = placed.map { $0 - cel.startFrame }

            let was = CelPoseState(tracks: cel.transformTracks, baselines: cel.pendingPoseBaselines)
            var now = was
            for (id, baseline) in was.baselines {
                var track = now.tracks[id] ?? TransformTrack()
                if let below = localKeyframes.last(where: { $0 < local }), track.key(atFrame: below) == nil {
                    track.setKey(TransformTrack.Key(frame: below, pose: baseline))
                }
                if let above = localKeyframes.first(where: { $0 > local }), track.key(atFrame: above) == nil {
                    track.setKey(TransformTrack.Key(frame: above, pose: baseline))
                }
                track.setKey(TransformTrack.Key(frame: local, pose: PoseQuad(restingIn: baseline.box)))
                now.tracks[id] = track
            }
            for (id, track) in was.tracks where was.baselines[id] == nil && !track.isEmpty {
                // Read off the *resolved* pose rather than the stored geometry, which is the
                // difference between holding what is on screen and holding where the ink is filed.
                guard let resolved = track.pose(atCelLocalFrame: local) else { continue }
                var held = now.tracks[id] ?? TransformTrack()
                held.setKey(TransformTrack.Key(frame: local, pose: resolved))
                now.tracks[id] = held
            }
            now.baselines = [:]

            guard now != was else { continue }
            before.cels[cel.id] = was
            after.cels[cel.id] = now
        }
        return (after, before)
    }

    /// **Drops the mark on `frame` and every channel's key on it**, as one undo step.
    ///
    /// Both halves, because the artist asked for the keyframe to go: leaving the keys behind would
    /// take the marker off the timeline and leave the animation doing exactly what it did, which is
    /// the shape of a control that appears not to work. A channel left with no keys is removed rather
    /// than stored empty — `setEffectParameterTrack`'s rule, and the state that would otherwise show
    /// up in the channel list animating nothing.
    ///
    /// **Both halves is also what makes this work on a keyframe that has no mark at all** — one placed
    /// by moving a slider, which `keyframeFrames(of:)` counts and which the artist can therefore reach.
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

        // **The pose channels go with them**, for the same reason the curve keys do: the artist asked
        // for the keyframe to go, and leaving the keys behind would take the marker off the timeline
        // and leave the drawing moving exactly as it did — a control that appears not to work.
        let (poses, posesBefore) = poseDeltaClearing(target, inFrames: frames)

        guard state != before || !poses.isEmpty else { return false }
        commitKeyframeState(state, from: before, to: target, label: label,
                            poses: poses, posesBefore: posesBefore)
        return true
    }

    /// The pose half of `clearKeyframes`, as a delta over the cels it touches. `frames` is absolute
    /// and each cel converts it — the same conversion `poseKeyframeFrames(inLayer:)` makes in the
    /// other direction, and the only two places either happens.
    private func poseDeltaClearing(_ target: KeyframeTarget,
                                   inFrames frames: Range<Int>) -> (KeyframePoseDelta, KeyframePoseDelta) {
        var after = KeyframePoseDelta()
        var before = KeyframePoseDelta()

        // **The container's own keys go too, and until §4.4 was reachable nothing dropped them.**
        // `keyedFrames(of:)` folds them into §2.28's union, so the timeline drew a keyframe for one;
        // Remove Keyframe then took the mark it did not have and left the key it did, which is the
        // biconditional broken in the direction §2.28 was reported from. Absolute frames, no cel
        // conversion (§3.1), and both homes — a folder holds no cels and reaches only this half.
        if let container = containerPose(of: target), !container.track.isEmpty {
            var now = container
            for frame in frames { now.track.removeKey(atFrame: frame) }
            // A baseline whose channel has no keys left has nothing to be committed onto — the rule
            // `clearPoseKeys` applies one container down.
            if now.track.isEmpty { now.baseline = nil }
            if now != container {
                before.container = container
                after.container = now
            }
        }

        guard case .layer(let layerID) = target,
              let index = layers.firstIndex(where: { $0.id == layerID }) else { return (after, before) }
        for cel in layers[index].cels where !cel.transformTracks.isEmpty {
            let was = CelPoseState(tracks: cel.transformTracks, baselines: cel.pendingPoseBaselines)
            var now = was
            for (id, track) in now.tracks {
                var trimmed = track
                for frame in frames { trimmed.removeKey(atFrame: frame - cel.startFrame) }
                // A channel left with no keys is removed rather than stored empty —
                // `setEffectParameterTrack`'s rule, and the state that would otherwise sit in the
                // channel list animating nothing.
                if trimmed.isEmpty { now.tracks.removeValue(forKey: id) } else { now.tracks[id] = trimmed }
            }
            now.baselines = now.baselines.filter { now.tracks[$0.key] != nil }
            guard now != was else { continue }
            before.cels[cel.id] = was
            after.cels[cel.id] = now
        }
        return (after, before)
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

    /// `existing` with `oldValue` keyed onto the keyframes either side of `frame` and `newValue` on
    /// `frame` itself.
    ///
    /// - Parameter keyframes: ascending — `CanvasManager.keyframes(marks:tracks:)`' frames, so a
    ///   keyframe the artist placed with a slider counts as a neighbour exactly as a marked one does.
    ///   Taken *once* by each caller before it starts writing, because seeding one channel adds keys
    ///   and would otherwise move the next channel's neighbour.
    ///
    /// **A neighbour that already carries a key is left alone.** That key is a value the artist
    /// authored or a pose a previous keyframe held, and overwriting it with a baseline would move a
    /// point of the curve nobody asked to move. `frame`'s own key *is* replaced, because that is the
    /// edit being made.
    private static func seeded(_ existing: AnimationCurve?, keyframes: [Int], frame: Int,
                               oldValue: Double, newValue: Double) -> AnimationCurve {
        var curve = existing ?? AnimationCurve()
        if let below = keyframes.last(where: { $0 < frame }), curve.key(atFrame: below) == nil {
            curve.setKey(AnimationCurve.Key(frame: below, value: oldValue))
        }
        if let above = keyframes.first(where: { $0 > frame }), curve.key(atFrame: above) == nil {
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
    /// **The pose channels one keyframe write also touches, as a delta rather than a whole state.**
    ///
    /// Only the cels this edit actually changes are in it, keyed by cel id. A whole-layer capture
    /// would be `O(cels)` on a path a 300–1000 cel document walks on every keyframe press, and the
    /// question "which cels did this write touch" has an exact answer at the point of writing, so the
    /// delta is both cheaper and more honest than a snapshot.
    ///
    /// It rides in the *same* undo record as the marks, baselines and curves for `KeyframeState`'s own
    /// reason: one artist action touches all of them, so one step covers all of them by construction
    /// rather than by four careful closures.
    /// **And the container's own pose beside them**, §4.4's transformation layer, which is not a cel
    /// and so has nowhere in the dictionary to live. It arrived after this type and was missed by
    /// both producers: `keyedFrames(of:)` folds a container pose key into §2.28's union, so the
    /// timeline drew a diamond for one — and Remove Keyframe then took the mark and left the key,
    /// which is a control that appears not to work. Nil means *untouched*, which is every document
    /// with no transformation layer in it.
    struct KeyframePoseDelta: Equatable {
        var cels: [UUID: CelPoseState] = [:]
        var container: LayerPose?

        static let none = KeyframePoseDelta()
        var isEmpty: Bool { cels.isEmpty && container == nil }
    }

    private func commitKeyframeState(_ state: KeyframeState, from before: KeyframeState,
                                     to target: KeyframeTarget, label: HistoryActionLabel,
                                     poses: KeyframePoseDelta = .none,
                                     posesBefore: KeyframePoseDelta = .none) {
        var state = state
        // Every document edit is a canvas edit: a pending shape/fill/text transient bakes first, as its
        // own earlier step. Re-entrant-safe, so calling it inside a bracket that already did is free.
        beginCanvasEdit()
        // **Taken before the write as well as after, and free when there is no mark to prune** —
        // `marks(_:droppingKeyed:)` carries the argument for both halves. This is the funnel every
        // writer in this file reaches, so `addKeyframe`'s own mark is dropped by the same keys that
        // write commits, in the one call that writes them.
        let keyedBefore = state.marks.isEmpty ? [] : keyedFrames(of: target)
        applyKeyframeState(state, to: target)
        applyPoseDelta(poses, to: target)
        if !state.marks.isEmpty {
            let pruned = Self.marks(state.marks,
                                    droppingKeyed: keyedBefore.union(keyedFrames(of: target)))
            if pruned != state.marks {
                state.marks = pruned
                applyKeyframeState(state, to: target)
            }
        }

        guard structureUndoDepth == 0, gestureSnapshot == nil else { return }
        recordUndo(label: label, cost: Self.stateUndoCost(before) + Self.stateUndoCost(state),
                   undo: { [weak self] in
                       self?.applyKeyframeState(before, to: target)
                       self?.applyPoseDelta(posesBefore, to: target)
                   },
                   redo: { [weak self] in
                       self?.applyKeyframeState(state, to: target)
                       self?.applyPoseDelta(poses, to: target)
                   })
    }

    /// Writes a pose delta onto the cels it names. A folder target carries none — it holds no cels.
    private func applyPoseDelta(_ delta: KeyframePoseDelta, to target: KeyframeTarget) {
        guard !delta.isEmpty else { return }
        if case .layer(let layerID) = target {
            for (celID, state) in delta.cels {
                applyCelPoseState(state, layerID: layerID, celID: celID)
            }
        }
        // The raw field, gated on the accessor by whoever built the delta — a delta only ever names
        // a container the target is actually posing through, so writing it back cannot put a pose
        // left inert by a kind change into force. Both homes, §2.21: a folder holds no cels and its
        // pose is therefore the *whole* of its pose delta.
        guard let container = delta.container else { return }
        switch target {
        case .layer(let id):
            guard let index = layers.firstIndex(where: { $0.id == id }),
                  layers[index].transform != container else { return }
            layers[index].transform = container
        case .folder(let id):
            guard let index = folders.firstIndex(where: { $0.id == id }),
                  folders[index].transform != container else { return }
            folders[index].transform = container
        }
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
