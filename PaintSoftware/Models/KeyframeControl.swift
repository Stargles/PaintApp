import CoreGraphics
import Foundation

/// **The keyframe button's arithmetic, and the routing of one settings-bar edit** — KEYFRAMES.md
/// §2.1 and §2.22, stage 3a.
///
/// **Why this is a type and not four `if`s inside `AnimationTimeline`.** `Views/AnimationTimeline.swift`,
/// `Views/EffectSection.swift` and `Views/DrawingView.swift` are **not compiled into the
/// `PaintSoftwareUITests` target** — a fast-tier test written against any of them is silently a pin
/// against nothing, which is what commit `6a396e1` was written to record. So every decision that can
/// be stated as a function of values rather than of views lives here, where a logic test can reach
/// it, and the views hold only the wiring that genuinely needs SwiftUI. `TimelineLayoutKey` is the
/// same split made for the same reason one file over.
enum KeyframeControl {

    /// **How long the hold is** (§2.1). Named here rather than typed into the view because §10 records
    /// that *"0.8 s matches nothing that ships"* — every other long press in the app is 0.5 s (row and
    /// block reorder) or 0.0 s (tool touch-down) — so the odd number wants somewhere to be explained.
    static let holdDuration: TimeInterval = 0.8

    /// **How far the finger may drift during that hold, in points — and it is 4 for one reason:
    /// `AnimationTimeline.resizeGesture` is a `DragGesture(minimumDistance: 6)` carried on the whole
    /// top bar, and this button sits inside it.**
    ///
    /// Set them so the two are disjoint by construction rather than by arbitration: any motion large
    /// enough to start a resize (> 6 pt) has already cancelled the hold (> 4 pt), and any hold that
    /// completes (≤ 4 pt) never reached the resize's threshold. Nothing has to decide which gesture
    /// wins, because they cannot both be live. The 4…6 pt band is a deliberate dead zone — a press
    /// that wanders that far does nothing at all, which is the right answer for a press that was
    /// neither a hold nor a drag.
    ///
    /// `UILongPressGestureRecognizer.allowableMovement` defaults to 10, which is *above* 6 and would
    /// have made a wandering hold both toggle the mode and resize the panel.
    static let holdAllowableMovement: CGFloat = 4

    /// **`AnimationTimeline.resizeGesture`'s `minimumDistance`, declared here rather than there so the
    /// relationship above can be pinned by a test.**
    ///
    /// `Views/AnimationTimeline.swift` is not compiled into `PaintSoftwareUITests`, so a test asserting
    /// `holdAllowableMovement < 6` against a 6 typed into that file would be comparing a constant to a
    /// literal copy of another constant — green forever, including on the day somebody raises the
    /// resize threshold. The timeline reads this, so there is one number and the test is about the
    /// relationship rather than about a coincidence.
    static let timelineResizeMinimumDistance: CGFloat = 6

    /// **What one settings-bar slider edit does to the document.**
    enum Write: Equatable {
        /// Writes the number onto the layer's *stored* effect. Today's behaviour, and still the
        /// behaviour for every channel nobody has animated.
        case storedValue
        /// Inserts or replaces a key at the playhead on the channel the slider names (§2.1).
        case key
    }

    /// The routing rule, in one place.
    ///
    /// **Three of the four arms are §2.1 read literally. The fourth is §2.23, ruled 2026-08-29**: a
    /// channel that *already* carries a curve keys on every edit, whether or not Animate mode is on,
    /// and Animate mode is only what creates the **first** curve on a channel that has none.
    ///
    /// The reasoning is the part worth keeping, because it is what stops someone undoing this. The
    /// settings bar shows the value **resolved at the playhead**, so a slider on an animated channel
    /// that wrote the stored base instead would move under the finger and spring straight back — the
    /// curve overwrites that base at every frame it is consulted at. That is a control that visibly
    /// does nothing, which is the failure §2.21 refuses for folder grades and the one the sandwich
    /// keys' own comments refuse for Render Resolution. It is also what every comparable application
    /// does: After Effects' stopwatch makes a property key on every subsequent change, and Animate
    /// mode is then exactly the bulk stopwatch.
    ///
    /// **There is deliberately no "can this target hold a track" argument.** There was one while
    /// §2.21's folder storage was still being built in parallel, and it existed so that wiring the
    /// folder arm in would be one call site rather than a hunt. Stage 2b landed, `KeyframeTarget` now
    /// has two cases that both store, and a parameter that is always true is a comment pretending to
    /// be a condition — which is exactly the state §2.21 refuses for the slider itself: *"the
    /// alternative costs a slider that silently refuses to key, which nothing reveals until the artist
    /// reaches for it."* A folder's slider and a layer's are now the same slider.
    static func write(isAnimateMode: Bool,
                      isScalarAnimatable: Bool,
                      channelIsAnimated: Bool) -> Write {
        guard isScalarAnimatable else { return .storedValue }
        return (isAnimateMode || channelIsAnimated) ? .key : .storedValue
    }

    /// **Whether a plain tap has anything to do.**
    ///
    /// A tap drops a key at the playhead on every channel that already has a curve, holding its
    /// current value — the standard "hold this pose here" move. With no tracks anywhere on the target
    /// there is no channel to hold, so the tap is refused and the button is drawn dimmed rather than
    /// swallowing the press silently. The arm for *"nothing is animated yet → open the channel
    /// panel"* belongs to stage 3b, which is where the channel panel is built.
    static func tapCanKey(animatedChannelCount: Int) -> Bool { animatedChannelCount > 0 }

    /// **The button is dimmed exactly when its tap is refused — and it is never disabled.**
    ///
    /// The distinction is load-bearing and easy to get wrong in the tidier direction: a truly disabled
    /// control cannot be *held* either, and the hold is the only way into Animate mode. On a fresh
    /// document nothing is animated, so a disabled button would make the mode unreachable by the exact
    /// gesture that creates the first track. Dimmed says "the tap does nothing"; the press still lands.
    static func isDimmed(isAnimateMode: Bool, animatedChannelCount: Int) -> Bool {
        !isAnimateMode && !tapCanKey(animatedChannelCount: animatedChannelCount)
    }

    /// Filled while the mode is on, outline while it is off — the icon half of the two devices
    /// §2.1's tap/hold split needs to stay discoverable. The other half is `AnimateBar`.
    ///
    /// **This is not decoration.** The one previous tap-versus-hold split in this app
    /// (`Views/LayerPanel.swift`'s add-button `primaryAction`) was reverted by the owner as
    /// undiscoverable, so a mode that is on must be loud about it.
    static func symbolName(isAnimateMode: Bool) -> String {
        isAnimateMode ? "diamond.fill" : "diamond"
    }

    /// The button's accessibility value: the mode, then how many channels a tap would key.
    ///
    /// **An encoded value rather than three separate marker elements**, which is `CurveEditor`'s
    /// `Self.encode(points)` convention and `TimelineRowView`'s `"startFrame,frameCount"` one. It
    /// exists because a XCUITest cannot otherwise see either fact: SwiftUI publishes no tint and no
    /// symbol name, so "the button went blue" is not assertable and "the value says `on|0`" is.
    static func statusValue(isAnimateMode: Bool, animatedChannelCount: Int) -> String {
        "\(isAnimateMode ? "on" : "off")|\(animatedChannelCount)"
    }
}


/// **Which grade a keyframe write is aimed at.**
///
/// Two homes, because there are exactly two places an `Effect` lives — `Layer.effect` and
/// `LayerFolder.effect` — and §2.21 rules that they animate identically. Before stage 2b landed, the
/// folder half had no storage and this was a `Bool` argument on `KeyframeControl.write` meaning
/// "can this target hold a track at all"; that argument is gone, because a `Bool` that is always true
/// is a comment pretending to be a parameter.
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

    /// **The target the keyframe button writes onto: the current layer.**
    ///
    /// §2.22 puts the button in the timeline's control strip, and the timeline's own notion of "the
    /// thing you are working on" is `currentLayerIndex` — the highlighted row, three inches to the
    /// left of the button. §2.4 then makes the address exact: effect keys live *on the layer*, in
    /// absolute document frames, so there is no cel to disambiguate and the playhead supplies the rest.
    ///
    /// **A folder is a perfectly good `KeyframeTarget` and still is not this one.** Its grade animates
    /// (§2.21) and Animate mode keys it through the settings bar like any layer's; what it does not
    /// have is a timeline row for the button to be *next to*, so "the folder the button means" has no
    /// answer. Reaching a folder's channels from a list rather than from the strip is stage 3b.
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

    /// The target's own name, for `AnimateBar` to say what it is about to write onto.
    func displayName(of target: KeyframeTarget) -> String {
        switch target {
        case .layer(let id): return layers.first { $0.id == id }?.name ?? "Layer"
        case .folder(let id): return folders.first { $0.id == id }?.name ?? "Group"
        }
    }

    private func effectTracks(of target: KeyframeTarget) -> [String: AnimationCurve] {
        switch target {
        case .layer(let id): return layers.first { $0.id == id }?.effectTracks ?? [:]
        case .folder(let id): return folders.first { $0.id == id }?.effectTracks ?? [:]
        }
    }

    /// **The ids of this target's effect channels that already carry a curve**, in the descriptor
    /// table's order — which is what a tap keys and what the button counts.
    ///
    /// **The `effectTracks.isEmpty` guard is not merely an optimisation**, for `Effect.resolved`'s
    /// reason one file over: `Effect.parameters` rebuilds up to thirty-three closures on every call,
    /// and this is read from `AnimationTimeline`'s body, which SwiftUI re-evaluates on every
    /// `CanvasManager` publish — several times a scrub tick. The overwhelming majority of documents
    /// have no track at all, and for those this is one dictionary `isEmpty` and a return.
    func animatedEffectChannelIDs(of target: KeyframeTarget) -> [String] {
        let tracks = effectTracks(of: target)
        guard !tracks.isEmpty, let effect = storedEffect(of: target) else { return [] }
        return effect.parameters.compactMap { parameter in
            guard parameter.isScalarAnimatable,
                  let curve = tracks[parameter.id], !curve.isEmpty
            else { return nil }
            return parameter.id
        }
    }

    /// **The tap** (§2.1): a key at the playhead on every already-animated channel, holding the value
    /// that channel resolves to there.
    ///
    /// The value comes from reading the **resolved** effect rather than from the stored one, which is
    /// the difference between "hold what is on screen" and "hold what was typed before anything was
    /// animated". At a frame between two keys those are different numbers and only the first is the
    /// move the artist is making.
    ///
    /// - Returns: how many channels were keyed. Zero means the tap was refused, which is the state
    ///   `KeyframeControl.isDimmed` draws.
    @discardableResult
    func keyAnimatedChannelsAtPlayhead(_ target: KeyframeTarget) -> Int {
        guard let resolved = resolvedEffect(of: target, atFrame: currentFrame) else { return 0 }

        var values: [String: Double] = [:]
        for id in animatedEffectChannelIDs(of: target) {
            guard let parameter = resolved.parameters.first(where: { $0.id == id }),
                  let value = parameter.read(resolved) else { continue }
            values[id] = value
        }
        return setEffectParameterKeys(target, frame: currentFrame, values: values)
    }

    /// **Inserts or replaces one key on each of several channels of one target, as one undo step** —
    /// the write `setEffectParameterTrack` was missing, and the one Animate mode leans on.
    ///
    /// **Why not `setEffectParameterTrack` in a loop.** Two reasons, and the second is the one that
    /// bites. It is a *whole-curve* replace, so a caller would have to read, mutate and hand back the
    /// curve at each of `n` channels — fine. But it records **one undo step per call**, so a single
    /// tap on the keyframe button would cost the artist one press of Undo per animated channel to take
    /// back. `bakePreciseStrokes` states the rule this follows: collect the edits, mutate, register
    /// **one** `recordUndo` over all of them, *"rather than registering per cel, which would cost the
    /// artist one press per cel to take back a single menu tap."*
    ///
    /// **Deliberately not routed through `withStructureUndo`**, for `setEffectParameterTrack`'s reason
    /// verbatim: that bracket snapshots `layers`, `folders`, `viewPresets`, `motionGroups` and
    /// `guideStrokes` twice at a declared cost of 4096, which is the right price for a discrete
    /// structural pick and the wrong one for a channel edit made on every tick of a slider drag.
    ///
    /// **The walk is over `parameters`, never over `values`**, which is `Effect.resolved`'s rule and
    /// buys the same three things: an id this effect does not have is ignored rather than stored, the
    /// order is the table's and therefore deterministic, and the `isScalarAnimatable` refusal lives in
    /// exactly one place — a track that would store and render nothing cannot be created here any more
    /// than it can at either `setEffectParameterTrack`.
    ///
    /// **Records nothing while an enclosing bracket is open**, again matching those two: a slider drag
    /// opens a structure gesture, that gesture has already snapshotted `layers` *and* `folders`, so a
    /// step here would split one drag into two. The enclosing `commitStructureGesture` supplies the
    /// label — see `DrawingView`, which passes `.effectKeyframes` when the drag wrote keys and
    /// `.valueLayerEffect` when it wrote a value.
    ///
    /// - Returns: how many channels actually changed. A key identical to one already on that frame is
    ///   not a change and is not counted, so a second tap on an unmoved playhead records no undo step.
    @discardableResult
    func setEffectParameterKeys(_ target: KeyframeTarget, frame: Int,
                                values: [String: Double]) -> Int {
        guard !values.isEmpty, let effect = storedEffect(of: target) else { return 0 }

        let tracks = effectTracks(of: target)
        var before: [String: AnimationCurve] = [:]
        var after: [String: AnimationCurve] = [:]
        /// Channels that had no curve at all before this write, so undo must *remove* them rather than
        /// restore an empty one — a stored empty curve is a channel that exists, animates nothing and
        /// would show up in a channel list, which is the state both `setEffectParameterTrack`
        /// overloads map to nil.
        var newChannels: Set<String> = []

        for parameter in effect.parameters {
            guard parameter.isScalarAnimatable, let value = values[parameter.id] else { continue }
            let existing = tracks[parameter.id]
            var curve = existing ?? AnimationCurve()
            curve.setKey(AnimationCurve.Key(frame: frame, value: value))
            guard curve != existing else { continue }
            if let existing { before[parameter.id] = existing } else { newChannels.insert(parameter.id) }
            after[parameter.id] = curve
        }
        guard !after.isEmpty else { return 0 }

        // Every document edit is a canvas edit: a pending shape/fill/text transient bakes first, as its
        // own earlier step. Re-entrant-safe, so calling it inside a bracket that already did is free.
        beginCanvasEdit()
        applyEffectTracks(after, removing: [], to: target)

        guard structureUndoDepth == 0, gestureSnapshot == nil else { return after.count }
        let cost = Self.keyUndoCost(before) + Self.keyUndoCost(after)
        recordUndo(label: .effectKeyframes, cost: cost,
                   undo: { [weak self] in
                       self?.applyEffectTracks(before, removing: newChannels, to: target)
                   }, redo: { [weak self] in
                       self?.applyEffectTracks(after, removing: [], to: target)
                   })
        return after.count
    }

    /// The one mutation both directions of the undo above go through. **The target is re-resolved on
    /// every call rather than captured as a position**, which is what `KeyframeTarget`'s all-ids shape
    /// buys: a restack between the edit and the undo moves an index and cannot move an id, and a
    /// folder deleted and restored is a different slot in `folders` under the same id.
    private func applyEffectTracks(_ curves: [String: AnimationCurve],
                                   removing: Set<String>, to target: KeyframeTarget) {
        switch target {
        case .layer(let id):
            guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
            for (key, curve) in curves { layers[index].effectTracks[key] = curve }
            for key in removing { layers[index].effectTracks.removeValue(forKey: key) }
        case .folder(let id):
            guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
            for (key, curve) in curves { folders[index].effectTracks[key] = curve }
            for key in removing { folders[index].effectTracks.removeValue(forKey: key) }
        }
    }

    /// `CanvasManager.trackUndoCost` summed over a set of curves — the same 64 + 96·keys estimate, and
    /// the same point about it: what matters is that it is *small*, so a session that keyframes heavily
    /// costs the history what a couple of structural edits do rather than what one whole-cel snapshot
    /// does.
    private static func keyUndoCost(_ curves: [String: AnimationCurve]) -> Int {
        curves.values.reduce(0) { $0 + 64 + 96 * $1.keys.count }
    }
}
