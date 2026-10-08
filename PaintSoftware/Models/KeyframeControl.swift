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

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }
}

/// **What a target shows on the timeline: its keys, and the frames primed with no key yet** — TODO
/// (139). Two indicators, because they are two things to the artist: a key is a value some channel
/// holds there (and a node in the graph editor), and a primed frame is where Add Keys was pressed and
/// nothing has changed yet — the next edit keys there, and only what it changes.
///
/// **Disjoint by construction.** `commitKeyframeState` drops a mark a key lands on
/// (`marks(_:droppingKeyed:)`), so a frame is keyed or primed and never both; `primed` subtracts the
/// keyed frames anyway, so a mark left beside a key by any path draws as the key it is.
struct PlacedKeys: Equatable {
    /// Every frame either kind sits on, ascending and unique — §2.28's union,
    /// `CanvasManager.keyframeFrames(of:)`. What the marker runs are grouped over, and the frames a
    /// channel with no curve is seeded onto (`AnimationCurve.seeded`).
    let frames: [Int]
    /// The frames primed with no key, ascending — drawn with their own indicator, and the frames an
    /// animated channel holds when it is edited past them (`AnimationCurve.keyed`).
    let primed: [Int]

    static let none = PlacedKeys(frames: [], primed: [])

    /// The same frames moved by `offset` — a layer's absolute frames into a cel's own (§3.1).
    func shifted(by offset: Int) -> PlacedKeys {
        PlacedKeys(frames: frames.map { $0 + offset }, primed: primed.map { $0 + offset })
    }

    /// Only the frames inside `span` — a cel's keys never live outside `0..<frameCount` (TODO (62)).
    func restricted(to span: Range<Int>) -> PlacedKeys {
        PlacedKeys(frames: frames.filter(span.contains), primed: primed.filter(span.contains))
    }
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
        /// **The `TargetChannel` curves** — TODO (21)'s second channel kind, in the same state
        /// object rather than in a store of its own reached separately.
        ///
        /// That is the whole of what made a second kind cheap. Every writer here already reads this
        /// state, mutates it and hands it to `commitKeyframeState`, so a dictionary added *here*
        /// gets one undo step, §2.28's `marks(_:droppingKeyed:)` rule and the id-addressed
        /// re-resolution for free — and cannot acquire a second, drifting definition of "a
        /// keyframe", because there is no second round trip for it to drift in.
        var channelTracks: [String: AnimationCurve] = [:]
        /// The held pre-edit values for those channels — `Layer.channelBaselines`, apart from
        /// `baselines` for that field's stated reason (the grade's writers prune `baselines`).
        var channelBaselines: [String: Double] = [:]
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
    /// (§2.21) and its sliders key like any layer's, and since TODO (21)'s folder band its row can be
    /// picked in the timeline (`selectedFolderID`) — but that pick is the *graph editor band's* row,
    /// not the brush's, and the writers that default to this one are writing where a slider or a
    /// take lands, which is a layer. The band asks `graphBandTarget` instead, which reads the pick
    /// ahead of this.
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

    /// **The grade whose settings bar belongs on screen because its layer is the one the artist is
    /// on** — TODO (118), the owner: *"Right now in an effect, you have to click effect settings to
    /// bring up the editing menu. Just have it be there automatically when the effect layer is
    /// currently selected."* Nil when the current layer carries no grade.
    ///
    /// **`layerEffect`, which is the app's one answer to "is this layer an effect"** (`Layer
    /// .layerEffect`'s own doc says so): a `.value` layer in effect mode, and a vector layer carrying a
    /// grade through its ink (TODO (92)). It follows `currentLayerIndex` by whatever route that moves
    /// — a rail row, a timeline name, a block, an undo — so there is nowhere for a bar to be left up
    /// over a layer the artist has left, and nothing to close.
    ///
    /// Compositor *nodes* are not here. A node has no selected state in the rail (its row expands and
    /// collapses), so its bar is still raised from its options — `DrawingView.effectBarTarget`.
    var effectLayerOnBar: KeyframeTarget? {
        guard layers.indices.contains(currentLayerIndex),
              layers[currentLayerIndex].layerEffect != nil else { return nil }
        return .layer(id: layers[currentLayerIndex].id)
    }

    /// **The container pose as stored on a target** — §4.4's transformation layer, and nothing on a
    /// folder: a folder poses nothing since TODO (71), whose Move lifts the folder's *contents* into
    /// the Move tool's own float instead. `storedEffect(of:)`'s shape one payload over, including its
    /// asymmetry: `layerTransform` rather than the raw field, because a `.raster` layer carrying a
    /// pose left behind by a kind change poses nothing.
    func containerPose(of target: KeyframeTarget) -> LayerPose? {
        guard case .layer(let id) = target else { return nil }
        return layers.first { $0.id == id }?.layerTransform
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
                                 tracks: layer.effectTracks,
                                 channelTracks: layer.channelTracks,
                                 channelBaselines: layer.channelBaselines)
        case .folder(let id):
            guard let folder = folders.first(where: { $0.id == id }) else { return KeyframeState() }
            return KeyframeState(marks: folder.keyframeMarks, baselines: folder.pendingBaselines,
                                 tracks: folder.effectTracks,
                                 channelTracks: folder.channelTracks,
                                 channelBaselines: folder.channelBaselines)
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
    /// canvas is not showing. A **mark** is not a value at all — `addKeys` takes one on a target
    /// with no grade whatsoever, and later stages key transforms onto the same marks — so gating those
    /// would hide the entire first step of the workflow on every ordinary drawing layer.
    ///
    /// **The pose channels are part of this too, and stage 5 is where that stopped being theoretical.**
    /// A transform key is a key — the two device reports that produced §2.28 were both the timeline and
    /// the model asking different questions, and a pose channel omitted here would reproduce both of
    /// them exactly (a diamond with no Remove Keys, and a seed arm stepping over a frame the artist
    /// can see). The keys live on the layer's *cels* in cel-local frames (§3.1) and are converted by
    /// `poseKeyframeFrames(inLayer:)`, which is the one place that conversion happens.
    func keyframeFrames(of target: KeyframeTarget) -> [Int] {
        keyframeFrames(of: target, in: keyframeState(of: target))
    }

    /// **The same union, taken against marks and curves a writer is holding mid-edit** — which is the
    /// only other shape anything is allowed to ask this in.
    ///
    /// `addKeys` needs the union over its *new* marks and its *old* curves, and `seedAndKeyChannel`
    /// needs it before it writes; neither can go through `keyframeFrames(of:)`, which re-reads the
    /// document. **Both of them used to call a static form** whose `poseFrames` defaulted to empty — so
    /// the union had two spellings in one file, one of which could not see a pose key. That is
    /// precisely the divergence §2.28 exists to forbid, and its two symptoms are the ones the owner
    /// reported: the neighbour search steps over a keyframe the artist can see, and the seed arm writes
    /// onto the wrong one. The static form is gone and this stands in its place, so the pose frames
    /// cannot be forgotten by omission.
    /// **It takes the whole `KeyframeState` rather than the two fields it happens to need**, and
    /// that is the correction TODO (21)'s second channel kind forced. The signature used to be
    /// `(marks:tracks:)`, which meant a caller holding a mid-edit state had to remember to pass each
    /// dictionary — and the *previous* version of that signature, a static one whose `poseFrames`
    /// defaulted to empty, is exactly what let a pose key go missing from the union and produced two
    /// of the owner's device reports. A second track dictionary would have added a second thing to
    /// forget. A state object cannot be partially handed over.
    func keyframeFrames(of target: KeyframeTarget, in state: KeyframeState) -> [Int] {
        var frames = keyedFrames(of: target, in: state)
        frames.formUnion(state.marks)
        return frames.sorted()
    }

    /// **The same union, split into keys and primed frames** — what the timeline and the folder's
    /// Add Keys row draw (`PlacedKeys`). One read of the state, so the two halves are of one document.
    func placedKeys(of target: KeyframeTarget) -> PlacedKeys {
        placedKeys(of: target, in: keyframeState(of: target))
    }

    /// The same, against a state the caller is holding mid-edit — `keyframeFrames(of:in:)`'s reason.
    func placedKeys(of target: KeyframeTarget, in state: KeyframeState) -> PlacedKeys {
        let keyed = keyedFrames(of: target, in: state)
        guard !state.marks.isEmpty || !keyed.isEmpty else { return .none }
        return PlacedKeys(frames: keyed.union(state.marks).sorted(),
                          primed: Set(state.marks).subtracting(keyed).sorted())
    }

    /// **The frames some channel of `target` holds a key on** — the keyed half of the union above, and
    /// the predicate `marks(_:droppingKeyed:)` prunes against.
    ///
    /// **The `isEmpty` fast paths are what make this affordable from a SwiftUI body.** The overwhelming
    /// majority of documents carry no track at all, and for those this is one dictionary `isEmpty` and
    /// one per-cel `isEmpty` per cel; for one that does it is a walk of the curves' own key arrays and
    /// never a call to `Effect.parameters`, which rebuilds up to thirty-three closures.
    func keyedFrames(of target: KeyframeTarget) -> Set<Int> {
        keyedFrames(of: target, in: keyframeState(of: target))
    }

    /// The same, against a state the caller is holding mid-edit.
    func keyedFrames(of target: KeyframeTarget, in state: KeyframeState) -> Set<Int> {
        var keyed: Set<Int> = []
        if !state.tracks.isEmpty, storedEffect(of: target) != nil {
            for curve in state.tracks.values {
                for key in curve.keys { keyed.insert(key.frame) }
            }
        }
        // **A `TargetChannel` key is a keyframe, and it is ungated exactly as a pose key is.**
        // Opacity is not a property of the grade: a plain drawing layer with no effect whatsoever
        // still has one, the compositor reads it at every frame, so a key on it is a frame the
        // artist can see a change at. Gating these on `storedEffect` — the line above, which is
        // right for the grade's own channels because a track left behind by a kind change renders
        // nothing — would reproduce §2.28's divergence precisely: a node in the graph editor with no
        // indicator on the cel, and a Remove Keys that is not offered for a key that exists.
        for curve in state.channelTracks.values {
            for key in curve.keys { keyed.insert(key.frame) }
        }
        // A pose key is a landed key exactly as a curve key is. Ungated by the grade, unlike the
        // effect curves: a pose channel is not a property of an effect at all, so a drawing layer with
        // no grade whatsoever still carries its transform keys. **A folder holds no cels and — since
        // TODO (71) — no pose of its own, so it holds no pose channels at all**; its keys are all in
        // the two dictionaries folded above.
        if case .layer(let id) = target { keyed.formUnion(poseKeyframeFrames(inLayer: id)) }
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

    /// Whether any keyframe sits inside a half-open frame range — `clearKeys(_:inFrames:)`'s
    /// question asked without performing it, so the cel menu can offer "Clear Keys" only when
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
    /// **Per *component*, not per track** — each component is its own curve since TODO (139), and
    /// the predicate is the same one every other channel gets: `AnimationCurve.isAnimated`.
    /// **And since TODO (21)'s second channel kind it lists the target's own scalars too**, between
    /// the grade's channels and the poses — `graphBandListing(of:)`'s order and the only place that
    /// order is decided. The two are pinned equal by `TimelineGraphBandLogicTests` in both
    /// directions, which is what stops a channel appearing in the band and not in the list.
    func listedAnimationChannelIDs(of target: KeyframeTarget) -> [String] {
        let grade = channelIDs(of: target) { $0.isAnimated }
        let own = targetChannelIDs(of: target) { $0.isAnimated }
        let sources = poseSources(of: target)
        guard !sources.isEmpty else { return grade + own }
        return grade + own + TimelineGraphBand.poseChannels(sources, descriptorOffset: 0)
            .filter(\.isAnimated).map(\.parameterID)
    }

    /// Whether one channel is an animation by the list's definition — `listedAnimationChannelIDs` for
    /// a single id, without building the array.
    func channelIsAnimated(_ target: KeyframeTarget, parameterID: String) -> Bool {
        let state = keyframeState(of: target)
        // Both stores, because an id belongs to exactly one of them (`TargetChannel`'s namespace
        // rule) and the caller asking this does not know which — it holds an id off the channel
        // list, which lists both kinds.
        return state.tracks[parameterID]?.isAnimated
            ?? state.channelTracks[parameterID]?.isAnimated
            ?? false
    }

    /// **The same walk over `TargetChannel.all`** — the target's own scalars, which are in force on
    /// every layer and folder and are therefore *not* gated on a grade being present. That
    /// asymmetry with `channelIDs` below is `keyedFrames`' asymmetry stated a second time, and it
    /// is the whole difference between the two channel kinds.
    private func targetChannelIDs(of target: KeyframeTarget,
                                  where matches: (AnimationCurve) -> Bool) -> [String] {
        let tracks = keyframeState(of: target).channelTracks
        guard !tracks.isEmpty else { return [] }
        return TargetChannel.all.compactMap { channel in
            guard let curve = tracks[channel.id], matches(curve) else { return nil }
            return channel.id
        }
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
    ///   keys is `.effectKeys` and a drag that wrote a value is `.valueLayerEffect`, and an artist
    ///   who animated a bloom must not read "Adjust Layer Effect" and conclude the grade itself has
    ///   gone.
    @discardableResult
    func applyEffectParameterEdit(_ target: KeyframeTarget, parameter: EffectParameter,
                                  newValue: Double, atFrame frame: Int) -> KeyframeControl.Write {
        // **A live take takes the routing decision away, and that is the whole of §5's intercept.**
        // The five arms below each write a *key* or the *base*; keying per reported value is the
        // aliased sample §5 forbids in its first paragraph, and would leave 72 keys a channel on a
        // three-second take. So the value is captured with its wall time and the edit falls through
        // to `.storedValue` — the base is a scratch pad for the length of the take and
        // `stopRecording` puts it back. The artist sees the value move under their finger either
        // way, which is what a recorder they cannot watch would fail to give them.
        if parameter.isScalarAnimatable,
           recordParameterSample(target, parameterID: parameter.id, value: newValue) {
            if let stored = storedEffect(of: target) {
                setStoredEffect(of: target, to: parameter.write(stored, newValue))
            }
            return .storedValue
        }

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
        let placed = keyframeFrames(of: target, in: state)
        state.tracks[parameterID] = AnimationCurve.seeded(state.tracks[parameterID], keyframes: placed,
                                                frame: frame, oldValue: oldValue, newValue: newValue)
        // A channel that seeds is a channel that no longer needs its held value.
        state.baselines.removeValue(forKey: parameterID)
        guard state != before else { return false }

        commitKeyframeState(state, from: before, to: target, label: .effectKeys)
        return true
    }

    /// **Add Keys: primes `frame`, and commits whatever edits were held for it** — TODO (139),
    /// KEYFRAMES.md §2.31, and one undo step for all of it.
    ///
    /// Two things happen, in this order:
    ///
    /// 1. **The mark is recorded**, if it is not already there. A mark with no channel is legal and is
    ///    the point: the owner's *"you select 'add keys' which primes it"* — the frame is primed and
    ///    nothing is keyed.
    ///
    ///    **And it does not survive step 2 keying the frame it names.** `commitKeyframeState` prunes
    ///    it — `marks(_:droppingKeyed:)` — so a press that lands a key stores the key alone, and the
    ///    timeline draws a key there rather than a primed frame.
    /// 2. **Every held baseline is committed and cleared.** The old value goes onto the nearest
    ///    keyframe below and the nearest above (whichever exist — see `seedAndKeyChannel` for why only
    ///    the immediate neighbours), and the channel's **current stored value** goes on `frame`. A
    ///    baseline is held only by a channel the artist changed, so this keys *"only the things that
    ///    changed"* and keys each of them on both primed frames.
    ///
    /// **What it no longer does is key every animated channel on `frame`.** That was §2.24's "hold this
    /// pose here", and it put a key on every channel the artist had not touched — exactly what the
    /// ruling forbids. The hold moved to the edit: `AnimationCurve.keyed` holds a changed channel's
    /// value on the keyframes either side of the playhead, so a primed frame still keeps its value
    /// when a channel is edited past it, and only that channel takes the key.
    ///
    /// **Priming a frame that is already primed is not a no-op when something is held**: step 2 still
    /// runs, which is the owner's *"modifies another slider while on B"* reached by a second press, and
    /// refusing it would make the press silently do nothing at the moment the artist expects it to save
    /// their edit.
    ///
    /// **A target with no grade at all still takes the mark.** A mark is a point in time rather than a
    /// property of an effect, and transforms and object channels key onto the same marks.
    ///
    /// - Returns: whether the document changed.
    @discardableResult
    func addKeys(_ target: KeyframeTarget, atFrame frame: Int) -> Bool {
        guard targetExists(target) else { return false }

        let before = keyframeState(of: target)
        var state = before

        if !state.marks.contains(frame) {
            state.marks.append(frame)
            state.marks.sort()
        }
        // **The neighbour search's view of the timeline, taken once**: the *union*, so a keyframe the
        // artist placed with a slider is a neighbour like any other; the *new* marks against the *old*
        // curves, because seeding one channel adds keys and would otherwise move the next channel's
        // neighbour — an order dependence over a dictionary, which has none; and the pose channels
        // with the rest, which `keyframeFrames(of:in:)` supplies so `poseDeltaForKeyframe` below
        // cannot seed a held pose onto the wrong frame.
        var neighbourState = before
        neighbourState.marks = state.marks
        let placed = placedKeys(of: target, in: neighbourState)

        if let stored = storedEffect(of: target) {
            for parameter in stored.parameters where parameter.isScalarAnimatable {
                // `stored`, not resolved: a channel holding a baseline has no curve to resolve
                // through — that is what made it a baseline rather than an auto-key.
                guard let baseline = before.baselines[parameter.id],
                      let current = parameter.read(stored) else { continue }
                state.tracks[parameter.id] = AnimationCurve.seeded(state.tracks[parameter.id],
                                                                   keyframes: placed.frames, frame: frame,
                                                                   oldValue: baseline, newValue: current)
            }
        }
        state.baselines = [:]

        // **The same commit for the target's own scalars** — TODO (21)'s second channel kind, with the
        // descriptor table swapped and no grade to gate on: opacity is a property of every layer, so a
        // press on a plain drawing layer commits a held opacity exactly as it commits a held bloom.
        for channel in TargetChannel.all {
            guard let baseline = before.channelBaselines[channel.id],
                  let current = storedValue(of: target, channel: channel) else { continue }
            state.channelTracks[channel.id] = AnimationCurve.seeded(state.channelTracks[channel.id],
                                                                    keyframes: placed.frames, frame: frame,
                                                                    oldValue: baseline, newValue: current)
        }
        state.channelBaselines = [:]

        let (poses, posesBefore) = poseDeltaForKeyframe(target, atFrame: frame, placed: placed)

        guard state != before || !poses.isEmpty else { return false }
        commitKeyframeState(state, from: before, to: target, label: .addKeys,
                            poses: poses, posesBefore: posesBefore)
        return true
    }

    /// **Step 2 again, in the pose channel's own currency** — one component at a time since TODO
    /// (139).
    ///
    /// The effect loop above walks the grade's descriptors; this walks the layer's *cels*, because a
    /// transform channel lives on the cel in cel-local frames (§3.1) while a grade's lives on the
    /// layer in absolute ones. **Every held pose is committed and cleared — on the components it
    /// changed.** The baseline is where the drawing *was*; the channel's current value is the
    /// **resting** pose for a cel, whose base is its own geometry (`CanvasManager.CelPoseState`), and
    /// the stored base for a container. `TransformTrack.key(_:over:atFrame:placed:)` keys exactly
    /// the components that differ between the two, so a sideways Move between two primed frames keys
    /// X and Y and nothing else.
    ///
    /// **A cel takes a key only for a mark inside its own span**, and the neighbours a held pose is
    /// seeded onto obey the same fence — TODO (62): a key never lives outside `0..<frameCount`.
    private func poseDeltaForKeyframe(_ target: KeyframeTarget, atFrame frame: Int,
                                      placed: PlacedKeys) -> (KeyframePoseDelta, KeyframePoseDelta) {
        var after = KeyframePoseDelta()
        var before = KeyframePoseDelta()

        // **The container's channel first.** §3.1: it keys in absolute document frames, so there is
        // no cel span to fall inside and no conversion to make.
        if let container = containerPose(of: target), let baseline = container.baseline {
            var now = container
            if let old = PoseComponents.decompose(baseline, inBox: container.track.box) {
                now.track.key(container.baseValues, over: old, atFrame: frame, placed: placed)
            }
            now.baseline = nil
            before.container = container
            after.container = now
        }

        guard case .layer(let layerID) = target,
              let index = layers.firstIndex(where: { $0.id == layerID }) else { return (after, before) }

        for cel in layers[index].cels where !cel.pendingPoseBaselines.isEmpty {
            // §2.18 again: an in-between carries no object channels, so a mark on one keys nothing.
            guard cel.interpolation == nil else { continue }
            let local = frame - cel.startFrame
            guard local >= 0, local < cel.frameCount else { continue }
            let celPlaced = placed.shifted(by: -cel.startFrame).restricted(to: 0..<cel.frameCount)

            let was = CelPoseState(tracks: cel.transformTracks, baselines: cel.pendingPoseBaselines)
            var now = was
            for (id, baseline) in was.baselines {
                var track = now.tracks[id] ?? TransformTrack(box: baseline.box)
                guard let old = PoseComponents.decompose(baseline, inBox: track.box) else { continue }
                track.key(track.restValues, over: old, atFrame: local, placed: celPlaced)
                now.tracks[id] = track.isEmpty ? nil : track
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
    func removeKeys(_ target: KeyframeTarget, atFrame frame: Int) -> Bool {
        clearKeys(target, inFrames: frame ..< (frame + 1), label: .removeKeys)
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
    func clearKeys(_ target: KeyframeTarget, inFrames frames: Range<Int>) -> Bool {
        clearKeys(target, inFrames: frames, label: .clearKeys)
    }

    /// The body of both, with the label the artist reads passed in — "remove keyframe" and "clear
    /// keyframes" are the same edit and two different things to want back.
    @discardableResult
    private func clearKeys(_ target: KeyframeTarget, inFrames frames: Range<Int>,
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
        // The target's own scalars go the same way and for the same reason: the artist asked for the
        // keyframe to go, and leaving an opacity key behind would take the marker off the timeline
        // and leave the fade running — a control that appears not to work.
        for (id, curve) in state.channelTracks {
            var trimmed = curve
            for frame in frames { trimmed.removeKey(atFrame: frame) }
            if trimmed.isEmpty { state.channelTracks.removeValue(forKey: id) }
            else { state.channelTracks[id] = trimmed }
        }
        // A baseline whose channel has no keys left has nothing to be committed onto —
        // `poseDeltaClearing` applies the same rule one currency over.
        state.channelBaselines = state.channelBaselines.filter { state.channelTracks[$0.key] != nil }

        // **The pose channels go with them**, for the same reason the curve keys do: the artist asked
        // for the keyframe to go, and leaving the keys behind would take the marker off the timeline
        // and leave the drawing moving exactly as it did — a control that appears not to work.
        let (poses, posesBefore) = poseDeltaClearing(target, inFrames: frames)

        guard state != before || !poses.isEmpty else { return false }
        commitKeyframeState(state, from: before, to: target, label: label,
                            poses: poses, posesBefore: posesBefore)
        return true
    }

    /// The pose half of `clearKeys`, as a delta over the cels it touches. `frames` is absolute
    /// and each cel converts it — the same conversion `poseKeyframeFrames(inLayer:)` makes in the
    /// other direction, and the only two places either happens.
    private func poseDeltaClearing(_ target: KeyframeTarget,
                                   inFrames frames: Range<Int>) -> (KeyframePoseDelta, KeyframePoseDelta) {
        var after = KeyframePoseDelta()
        var before = KeyframePoseDelta()

        // **The container's own keys go too, and until §4.4 was reachable nothing dropped them.**
        // `keyedFrames(of:)` folds them into §2.28's union, so the timeline drew a keyframe for one;
        // Remove Keys then took the mark it did not have and left the key it did, which is the
        // biconditional broken in the direction §2.28 was reported from. Absolute frames, no cel
        // conversion (§3.1), and both homes — a folder holds no cels and reaches only this half.
        if let container = containerPose(of: target), !container.track.isEmpty {
            var now = container
            for frame in frames { now.track.removeKeys(atFrame: frame) }
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
                for frame in frames { trimmed.removeKeys(atFrame: frame - cel.startFrame) }
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
    /// **Each key is `AnimationCurve.keyed`**: a channel that is already animated first holds what it
    /// showed on every primed frame its edit would reshape — the hold Add Keys used to make for every
    /// channel at the press, made now for the one channel that changed (TODO (139)).
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
    /// which passes `.effectKeys` when the drag wrote keys and `.valueLayerEffect` when it wrote
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
        let primed = placedKeys(of: target, in: before).primed

        for parameter in effect.parameters {
            guard parameter.isScalarAnimatable, let value = values[parameter.id] else { continue }
            let existing = state.tracks[parameter.id]
            let curve = (existing ?? AnimationCurve()).keyed(value, atFrame: frame, holding: primed)
            guard curve != existing else { continue }
            state.tracks[parameter.id] = curve
            changed += 1
        }
        guard changed > 0 else { return 0 }

        commitKeyframeState(state, from: before, to: target, label: .effectKeys)
        return changed
    }

    /// **Replaces whole curves on several channels at once, as one step** — KEYFRAMES.md §5's
    /// recorder, which is the only caller and the reason this exists beside `setEffectParameterKeys`
    /// rather than being spelled by it.
    ///
    /// That one writes **one key per channel** at a frame and merges into whatever curve is there;
    /// a take writes a *whole curve* per channel and replaces it, because the take is the animation
    /// rather than an adjustment to one. Both reach `commitKeyframeState`, so both get §2.28's
    /// `marks(_:droppingKeyed:)` rule applied once over the whole write — which is the thing that
    /// must not be spelled twice, since a mark stranded beside a key is three device reports.
    ///
    /// **Curves are refused per channel rather than per call.** A parameter that is not scalar
    /// animatable, or is not a parameter of the grade in force, is skipped and the rest are written:
    /// the alternative is one bad channel discarding a whole take.
    ///
    /// - Returns: how many channels changed.
    @discardableResult
    func setEffectParameterCurves(_ target: KeyframeTarget,
                                  curves: [String: AnimationCurve]) -> Int {
        guard !curves.isEmpty, let effect = storedEffect(of: target) else { return 0 }

        let before = keyframeState(of: target)
        var state = before
        var changed = 0

        for parameter in effect.parameters {
            guard parameter.isScalarAnimatable, let curve = curves[parameter.id] else { continue }
            // Empty is removal, exactly as `setEffectParameterTrack` treats it: a curve with no keys
            // is a channel that exists, animates nothing, and shows up in a channel list.
            let after: AnimationCurve? = curve.isEmpty ? nil : curve
            guard after != state.tracks[parameter.id] else { continue }
            if let after { state.tracks[parameter.id] = after }
            else { state.tracks.removeValue(forKey: parameter.id) }
            changed += 1
        }
        guard changed > 0 else { return 0 }

        commitKeyframeState(state, from: before, to: target, label: .recordAnimation)
        return changed
    }

    // MARK: - Shared machinery

    /// Not `private`: `TransformKeyframes.swift`'s `writeContainerPose` guards on it too, for a
    /// container pose committed onto a folder that was deleted between the box going up and the
    /// artist's finger lifting — the same race `writeContainerPose`'s layer arm always guarded
    /// against by looking `layerID` up directly, generalised the day that lookup became a `switch`.
    func targetExists(_ target: KeyframeTarget) -> Bool {
        switch target {
        case .layer(let id): return layers.contains { $0.id == id }
        case .folder(let id): return folders.contains { $0.id == id }
        }
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
    /// timeline drew a diamond for one — and Remove Keys then took the mark and left the key,
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
        // writer in this file reaches, so `addKeys`'s own mark is dropped by the same keys that
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

    /// Writes a pose delta onto the cels it names and the container pose it carries. A folder target
    /// carries neither — it holds no cels and, since TODO (71), no pose.
    private func applyPoseDelta(_ delta: KeyframePoseDelta, to target: KeyframeTarget) {
        guard !delta.isEmpty, case .layer(let layerID) = target,
              let index = layers.firstIndex(where: { $0.id == layerID }) else { return }
        for (celID, state) in delta.cels {
            applyCelPoseState(state, layerID: layerID, celID: celID)
            // `commitCelPoseState`'s pairing: a pose change is a change to what the cel shows.
            celContentChangedOutsideStroke(layerID: layerID, celID: celID)
        }
        // The raw field, gated on the accessor by whoever built the delta — a delta only ever names
        // a container the target is actually posing through, so writing it back cannot put a pose
        // left inert by a kind change into force.
        guard let container = delta.container, layers[index].transform != container else { return }
        layers[index].transform = container
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
            layers[index].channelTracks = state.channelTracks
            layers[index].channelBaselines = state.channelBaselines
        case .folder(let id):
            guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
            folders[index].keyframeMarks = state.marks
            folders[index].pendingBaselines = state.baselines
            folders[index].effectTracks = state.tracks
            folders[index].channelTracks = state.channelTracks
            folders[index].channelBaselines = state.channelBaselines
        }
    }

    /// `CanvasManager.trackUndoCost` summed over a whole state — the same 64 + 96·keys estimate per
    /// curve, plus a few bytes an `Int` mark and a `Double` baseline each cost. The same point about it
    /// applies: what matters is that it is *small*, so a session that keyframes heavily costs the
    /// history what a couple of structural edits do rather than what one whole-cel snapshot does.
    private static func stateUndoCost(_ state: KeyframeState) -> Int {
        state.tracks.values.reduce(0) { $0 + 64 + 96 * $1.keys.count }
            + state.channelTracks.values.reduce(0) { $0 + 64 + 96 * $1.keys.count }
            + 8 * state.marks.count
            + 72 * (state.baselines.count + state.channelBaselines.count)
    }
}

// MARK: - The target's own scalars — KEYFRAMES.md TODO (21)'s second channel kind

/// **Everything a `TargetChannel` needs that an `EffectParameter` already had**, and deliberately
/// nothing more.
///
/// The five-arm routing rule itself is *not* repeated here: `KeyframeControl.write` is a pure
/// function of four values and both channel kinds hand it the same four. What differs between them
/// is only where the number is read from and written to, which is two key paths on the descriptor —
/// so what follows is `applyEffectParameterEdit`'s shape with `parameter.read`/`parameter.write`
/// swapped for `storedValue`/`setStoredValue` and the track dictionary swapped for the other one.
/// Everything downstream — the union, the mark rule, the undo step, the recorder — is shared.
extension CanvasManager {

    /// This channel's **stored** value on a target, or nil if the target is not in the document — or
    /// is a folder and the channel is one a folder does not own (`TargetChannel.folderPath`).
    /// `storedEffect(of:)`'s counterpart, and note there is no `layerEffect`-style accessor to route
    /// through: opacity is in force on every layer whatever its kind, so there is no mode to ask
    /// about.
    func storedValue(of target: KeyframeTarget, channel: TargetChannel) -> Double? {
        switch target {
        case .layer(let id): return layers.first { $0.id == id }?[keyPath: channel.layerPath]
        case .folder(let id):
            guard let path = channel.folderPath else { return nil }
            return folders.first { $0.id == id }?[keyPath: path]
        }
    }

    /// **Writes the number back onto whichever of the two homes `target` names.**
    ///
    /// The index is resolved *here*, at write time, rather than taken from a caller — a restack
    /// while a slider is open would otherwise send the write to a neighbour. That is
    /// `setStoredEffect(of:to:)`'s rule, and it is the reason `KeyframeTarget` carries ids on both
    /// arms.
    func setStoredValue(of target: KeyframeTarget, channel: TargetChannel, to value: Double) {
        let clamped = channel.clamped(value)
        switch target {
        case .layer(let id):
            guard let index = layers.firstIndex(where: { $0.id == id }),
                  layers[index][keyPath: channel.layerPath] != clamped else { return }
            layers[index][keyPath: channel.layerPath] = clamped
        case .folder(let id):
            guard let path = channel.folderPath,
                  let index = folders.firstIndex(where: { $0.id == id }),
                  folders[index][keyPath: path] != clamped else { return }
            folders[index][keyPath: path] = clamped
        }
    }

    /// `keyframeWrite(_:parameter:atFrame:)` for a target channel — the *same* rule with the same
    /// four inputs, read off the other store.
    ///
    /// `isScalarAnimatable` is `true` by construction: `TargetChannel` describes a continuous
    /// `Double` and there is no stepped or compound member of the table to refuse. Passing the
    /// literal rather than deleting the parameter keeps `KeyframeControl.write` one function with
    /// one set of arms, which is what makes the two kinds provably route alike.
    func keyframeWrite(_ target: KeyframeTarget, channel: TargetChannel,
                       atFrame frame: Int) -> KeyframeControl.Write {
        let state = keyframeState(of: target)
        let placed = keyframeFrames(of: target, in: state)
        return KeyframeControl.write(
            isScalarAnimatable: true,
            channelHasCurve: state.channelTracks[channel.id]?.isEmpty == false,
            keyframeCount: placed.count,
            playheadIsOnKeyframe: placed.contains(frame))
    }

    /// **One opacity-slider edit, routed and performed** — `applyEffectParameterEdit`'s twin, arm
    /// for arm.
    ///
    /// - Returns: the arm taken, so the caller can label its undo bracket. A drag that wrote keys is
    ///   the channel's `keyframeLabel` and a drag that wrote a value is its `editLabel`; an artist
    ///   who animated opacity must not read "change opacity" and conclude the fade itself has gone.
    @discardableResult
    func applyTargetChannelEdit(_ target: KeyframeTarget, channel: TargetChannel,
                                newValue: Double, atFrame frame: Int) -> KeyframeControl.Write {
        // **A live take takes the routing decision away** — §5's intercept, and it is the *same*
        // intercept: `recordParameterSample` is keyed by an id string and knows nothing about which
        // store the channel lives in, so a scalar surface plugs into the recorder by calling it.
        // Keying per reported value is the aliased sample §5 forbids in its first paragraph.
        if recordParameterSample(target, parameterID: channel.id, value: newValue) {
            setStoredValue(of: target, channel: channel, to: newValue)
            return .storedValue
        }

        let route = keyframeWrite(target, channel: channel, atFrame: frame)
        // **The stored value, never the resolved one** — `applyEffectParameterEdit`'s rule: writing
        // back what the playhead resolves to would bake a curve's value-at-this-frame into the base
        // as a side effect, and that base is invisible for as long as its curve exists.
        let stored = storedValue(of: target, channel: channel)

        switch route {
        case .key:
            setTargetChannelKeys(target, frame: frame, values: [channel.id: newValue])
        case .seedAndKey:
            if let stored {
                seedAndKeyTargetChannel(target, channel: channel,
                                        oldValue: stored, newValue: newValue, atFrame: frame)
            }
        case .storedValueHoldingBaseline:
            // Both halves, and the ordinary write is not optional: a provisional edit that is never
            // committed is lost work (§2.27's second consequence).
            if let stored { holdChannelBaseline(target, channelID: channel.id, value: stored) }
            setStoredValue(of: target, channel: channel, to: newValue)
        case .storedValue:
            setStoredValue(of: target, channel: channel, to: newValue)
        }
        return route
    }

    /// `holdBaseline` in the other store. Written once per channel per keyframe cycle for that
    /// method's reason — the first edit after a mark is the only one that knows the value at A.
    @discardableResult
    func holdChannelBaseline(_ target: KeyframeTarget, channelID: String, value: Double) -> Bool {
        var state = keyframeState(of: target)
        guard state.channelBaselines[channelID] == nil else { return false }
        state.channelBaselines[channelID] = value
        applyKeyframeState(state, to: target)
        return true
    }

    /// `seedAndKeyChannel` in the other store — the owner's *"the user modifies another slider while
    /// on B"*, where A already exists and must receive the value B is moving away from.
    @discardableResult
    func seedAndKeyTargetChannel(_ target: KeyframeTarget, channel: TargetChannel,
                                 oldValue: Double, newValue: Double, atFrame frame: Int) -> Bool {
        guard targetExists(target) else { return false }
        var state = keyframeState(of: target)
        let before = state
        let placed = keyframeFrames(of: target, in: state)
        state.channelTracks[channel.id] = AnimationCurve.seeded(state.channelTracks[channel.id],
                                                      keyframes: placed, frame: frame,
                                                      oldValue: channel.clamped(oldValue),
                                                      newValue: channel.clamped(newValue))
        state.channelBaselines.removeValue(forKey: channel.id)
        guard state != before else { return false }
        commitKeyframeState(state, from: before, to: target, label: channel.keyframeLabel)
        return true
    }

    /// `setEffectParameterKeys` in the other store: one key on each of several channels, one undo
    /// step, and the walk over `TargetChannel.all` rather than over `values` for that method's
    /// stated reason — an id the table does not carry is ignored rather than stored.
    @discardableResult
    func setTargetChannelKeys(_ target: KeyframeTarget, frame: Int, values: [String: Double]) -> Int {
        guard !values.isEmpty, targetExists(target) else { return 0 }
        let before = keyframeState(of: target)
        var state = before
        var changed = 0
        let primed = placedKeys(of: target, in: before).primed
        // The first channel this write actually touches names the step. With one channel in the
        // table that is always Opacity; the day there are two, a press that moves both is named
        // after the first in `TargetChannel.all` rather than after whichever the dictionary
        // iterated to first, which is the same determinism `Effect.parameters`' order buys.
        var label: HistoryActionLabel?

        for channel in TargetChannel.all {
            guard let value = values[channel.id] else { continue }
            let existing = state.channelTracks[channel.id]
            let curve = (existing ?? AnimationCurve()).keyed(channel.clamped(value), atFrame: frame,
                                                             holding: primed)
            guard curve != existing else { continue }
            state.channelTracks[channel.id] = curve
            if label == nil { label = channel.keyframeLabel }
            changed += 1
        }
        guard changed > 0, let label else { return 0 }

        commitKeyframeState(state, from: before, to: target, label: label)
        return changed
    }

    /// **Replaces one whole curve** — the graph editor's own write, reached from
    /// `writeGraphBandCurves` when the dragged node belongs to a target channel.
    ///
    /// It goes through `commitKeyframeState` rather than spelling `setEffectParameterTrack`'s
    /// hand-rolled mark arithmetic a third time. That funnel already applies §2.28's
    /// `marks(_:droppingKeyed:)` against the keys either side of the write, which is what makes a
    /// key dragged off a marked frame take the mark with it — the divergence the owner reported
    /// three times, and the one thing that must never be implemented twice.
    ///
    /// An empty curve is removal, exactly as it is for a grade's channel: a curve with no keys is a
    /// channel that exists, animates nothing, and shows up in a channel list.
    @discardableResult
    func setTargetChannelTrack(_ target: KeyframeTarget, channelID: String,
                               to curve: AnimationCurve?) -> Bool {
        guard targetExists(target), let channel = TargetChannel.named(channelID) else { return false }
        let before = keyframeState(of: target)
        var state = before
        if let curve, !curve.isEmpty { state.channelTracks[channelID] = curve }
        else { state.channelTracks.removeValue(forKey: channelID) }
        guard state != before else { return false }
        commitKeyframeState(state, from: before, to: target, label: channel.keyframeLabel)
        return true
    }

    /// `setEffectParameterCurves` in the other store — §5's recorder, which writes a *whole curve*
    /// per channel because a take is the animation rather than an adjustment to one.
    @discardableResult
    func setTargetChannelCurves(_ target: KeyframeTarget, curves: [String: AnimationCurve]) -> Int {
        guard !curves.isEmpty, targetExists(target) else { return 0 }
        let before = keyframeState(of: target)
        var state = before
        var changed = 0

        for channel in TargetChannel.all {
            guard let curve = curves[channel.id] else { continue }
            let after: AnimationCurve? = curve.isEmpty ? nil : curve
            guard after != state.channelTracks[channel.id] else { continue }
            if let after { state.channelTracks[channel.id] = after }
            else { state.channelTracks.removeValue(forKey: channel.id) }
            changed += 1
        }
        guard changed > 0 else { return 0 }

        commitKeyframeState(state, from: before, to: target, label: .recordAnimation)
        return changed
    }
}

// MARK: - A pose component's curve, written whole — TODO (139)

extension CanvasManager {

    /// **Replaces one pose component's whole curve** — the graph editor's write for a pose row, and
    /// `setTargetChannelTrack`'s shape for the third kind of channel the band draws.
    ///
    /// Since TODO (139) a pose row is a stored `AnimationCurve` rather than a reading of whole-pose
    /// keys, so every band gesture — drag, retime, marquee, handle, tap-to-add, the node menu's
    /// Delete and Reset Curve — produces exactly the whole-curve replacement this takes, and none of
    /// them needs a pose funnel of its own.
    ///
    /// **A cel channel's row is every cel's curve for that component, merged** onto the band's
    /// absolute frames (`TimelineGraphBand.poseChannels`), so the write splits it back: each cel that
    /// carries the channel takes the keys inside its own span, in its own frames. A key outside every
    /// such span is dropped — the band's `frameWindows` stop a dragged key leaving its cel, so only a
    /// tap-to-add on a block that does not carry the channel reaches that, and it adds nothing, as it
    /// always did.
    ///
    /// **Through `commitKeyframeState`**, the funnel every keyframe writer reaches, so §2.28's
    /// `marks(_:droppingKeyed:)` runs against the keys either side of the write — a pose key dragged
    /// off a primed frame takes the mark with it, as a grade's does — and the write is one undo step,
    /// or none inside a gesture bracket, which is what a drag's per-tick writes need.
    ///
    /// - Returns: whether the document changed.
    @discardableResult
    func setPoseChannelTrack(_ target: KeyframeTarget, parameterID: String,
                             to curve: AnimationCurve?) -> Bool {
        guard case .layer(let layerID) = target,
              let index = layers.firstIndex(where: { $0.id == layerID }),
              let (channel, component) = PoseChannelID.resolve(parameterID: parameterID)
        else { return false }
        var poses = KeyframePoseDelta()
        var posesBefore = KeyframePoseDelta()

        switch channel {
        case .container:
            guard let container = containerPose(of: target) else { return false }
            var now = container
            now.track.setCurve(curve, for: component)
            guard now != container else { return false }
            poses.container = now
            posesBefore.container = container
        case .cel(let id):
            for cel in layers[index].cels {
                guard let track = cel.transformTracks[id.id] else { continue }
                let span = cel.startFrame..<cel.endFrame
                let keys = (curve?.keys ?? []).filter { span.contains($0.frame) }.map { key -> AnimationCurve.Key in
                    var local = key
                    local.frame -= cel.startFrame
                    return local
                }
                var rewritten = track
                rewritten.setCurve(AnimationCurve(keys: keys, step: track.curve(component)?.step ?? curve?.step ?? 1),
                                   for: component)
                guard rewritten != track else { continue }
                let was = CelPoseState(tracks: cel.transformTracks, baselines: cel.pendingPoseBaselines)
                var now = was
                now.tracks[id.id] = rewritten.isEmpty ? nil : rewritten
                posesBefore.cels[cel.id] = was
                poses.cels[cel.id] = now
            }
            guard !poses.isEmpty else { return false }
        }
        let state = keyframeState(of: target)
        commitKeyframeState(state, from: state, to: target, label: .effectKeys,
                            poses: poses, posesBefore: posesBefore)
        return true
    }
}
