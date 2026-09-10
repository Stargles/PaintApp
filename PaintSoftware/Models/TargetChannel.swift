import Foundation

/// **One scalar a layer or a folder owns *itself*, outside any grade** — KEYFRAMES.md TODO (21)'s
/// second channel *kind*, and the shape every later non-pose channel takes.
///
/// **Why this type exists at all.** Every channel the graph editor carried before this was one of
/// two things: an `EffectParameter` (a number inside `Layer.effect` / `LayerFolder.effect`,
/// addressed by `"<case>.<field>"`) or a pose (`TransformTrack`, six curves of a quad). Layer
/// opacity is neither. It is a plain `Double` stored on the layer, read by the compositor on every
/// frame whether or not the layer grades anything, and there is nothing to hang an `EffectParameter`
/// off — that struct's `read`/`write` are `(Effect) -> Double?` and `(Effect, Double) -> Effect`,
/// so a layer with no grade has no operands for them.
///
/// **The family this opens, and it is the reason to spend a table on one row.** A folder's opacity
/// is *this same channel* on the other `KeyframeTarget` — one descriptor, two key paths, no second
/// case (§2.21's ruling for grades, which said a folder's effect animates exactly as a layer's,
/// reached one field over). A blend amount and an effect's overall strength are the same shape
/// again: a `Double` on `Layer` and on `LayerFolder`, keyed in absolute document frames, resolved
/// on the render path. Each of those costs **one entry in `all` below** and nothing else — no new
/// store, no new union, no new persistence field, no new arm in the recorder — which is the test
/// this design had to pass.
///
/// **Ids are bare and undotted, and that is a namespace partition rather than a style.** Every
/// `EffectParameter.id` is `"<case>.<field>"` and therefore contains a dot; every id here does not.
/// So `TargetChannel.named(_:)` and `EffectParameter` can never claim the same string, a saved
/// document can be read back into the right store by inspection, and `PoseChannelID.isPose` — which
/// is a third, dotted namespace — is unaffected. `isTargetChannel(parameterID:)` is the predicate,
/// stated once here so no caller writes `!contains(".")` by hand.
struct TargetChannel: Identifiable {

    /// **The persisted address, and the one field here that must never change** —
    /// `EffectParameter.id`'s rule verbatim, for the same reason: a saved document carries this
    /// string, so it has to survive a Swift rename of the property it addresses.
    ///
    /// Bare and undotted (see the type's note). The *same* id addresses the layer's property and the
    /// folder's, because they are the same channel on two homes.
    let id: String

    /// The artist-facing label. What the graph editor's channel list draws for this row.
    let name: String

    /// The suffix of the control's accessibility identifier, so a test can name the surface this
    /// channel is edited from. Separate from `id` for `EffectParameter.controlIdentifier`'s reason:
    /// one is what a document stores and the other is what an XCUITest taps, and neither may be
    /// changed to make it match the other.
    let controlIdentifier: String

    /// What the control offers, and the range the band draws its Y axis over.
    let uiRange: ClosedRange<Double>

    /// Every value the model accepts and renders distinctly. **Narrower than `uiRange` is impossible
    /// and equal is normal** — opacity's two are both `0...1`, because alpha outside that renders
    /// nothing new: a compositor multiplying by 1.4 clamps in the shader and one multiplying by -0.2
    /// produces the same picture as 0. That is the difference from an effect parameter, where
    /// `modelDomain` is usually *wider* and overshoot is the thing a bezier graph editor exists to
    /// give you. `resolvedValue(atFrame:)` clamps into this, so an overshooting handle on an opacity
    /// curve produces a hold at the end of the range rather than an out-of-gamut alpha reaching Core
    /// Animation.
    let modelDomain: ClosedRange<Double>

    /// The `String(format:)` a readout prints this with.
    let format: String

    /// The undo step an ordinary edit of this value records — "change opacity". Carried on the
    /// descriptor rather than hard-coded at the write site so a second channel gets its own name for
    /// free; a shared label would make an artist who dragged a blend amount read "undo change
    /// opacity", which is the exact lie `HistoryActionLabel`'s own notes are written against.
    let editLabel: HistoryActionLabel

    /// The undo step a *keyframe* write on this channel records — "edit opacity keyframes". Apart
    /// from `editLabel` for `.effectKeyframes`' stated reason: the value is the thing the artist
    /// picked and the curve is the animation on it, and they are different things to want back.
    let keyframeLabel: HistoryActionLabel

    /// **The typed address on each of the two homes.** `Layer` and `LayerFolder` are different
    /// structs with the same property, so the channel carries one key path into each rather than a
    /// closure pair — which is what makes "a folder's opacity is the same channel" true in the type
    /// system instead of by two parallel `switch`es that can drift.
    let layerPath: WritableKeyPath<Layer, Double>
    let folderPath: WritableKeyPath<LayerFolder, Double>

    /// **Layer and folder opacity** — the owner's ask of 2026-09-09, *"layer opacity should also be
    /// able to be keyframed"*.
    static let opacity = TargetChannel(
        id: "opacity",
        name: "Opacity",
        controlIdentifier: "opacity",
        uiRange: 0...1,
        modelDomain: 0...1,
        format: "%.0f%%",
        editLabel: .opacity,
        keyframeLabel: .opacityKeyframes,
        layerPath: \Layer.opacity,
        folderPath: \LayerFolder.opacity)

    /// **Every channel of this kind, in a fixed order.** The order is the channel list's and the
    /// band's colour order, so it is decided here and nowhere else — `Effect.parameters`' contract
    /// one type over.
    static let all: [TargetChannel] = [.opacity]

    /// The channel one id names, or nil. The lookup every writer guards on, so an id that is not a
    /// channel of this kind is refused in one place rather than at each write.
    static func named(_ id: String) -> TargetChannel? {
        all.first { $0.id == id }
    }

    /// **Whether an id addresses a channel of this kind at all** — the namespace test, stated once.
    ///
    /// It is `named(_:) != nil` rather than "has no dot", deliberately: a *typo* is not a target
    /// channel, and a router that treated every undotted string as one would send an unknown id to
    /// this store instead of refusing it. The dot rule is what guarantees the two namespaces cannot
    /// collide; membership of `all` is what decides where a write goes.
    static func isTargetChannel(parameterID: String) -> Bool { named(parameterID) != nil }

    /// `value` brought inside `modelDomain`. The one place the clamp lives, so the two homes cannot
    /// clamp differently.
    func clamped(_ value: Double) -> Double {
        min(max(value, modelDomain.lowerBound), modelDomain.upperBound)
    }
}

extension TargetChannel: Equatable {
    /// By id, which is the identity — two descriptors with one id would be a programming error the
    /// table above cannot express, and comparing key paths and labels buys nothing.
    static func == (lhs: TargetChannel, rhs: TargetChannel) -> Bool { lhs.id == rhs.id }
}

// MARK: - Resolution

extension Layer {

    /// **This channel's value at one frame** — the stored number with its curve evaluated over it,
    /// clamped into the channel's model domain.
    ///
    /// `Layer.layerEffect(atFrame:)`'s twin, and the same seam cut in the same place for the same
    /// reason: the compositor receives a number, never a track, so nothing downstream of
    /// `renderNodes(inContainer:atFrame:)` learns that opacity can be animated.
    ///
    /// **No curve is not the same as a flat curve, and the `guard` is what keeps them apart.** A
    /// layer nobody has animated returns the stored value untouched — byte-identical to what every
    /// caller read before this feature existed — so a document with no `channelTracks` cannot move.
    func resolvedValue(_ channel: TargetChannel, atFrame frame: Int) -> Double {
        guard !channelTracks.isEmpty, let curve = channelTracks[channel.id], !curve.isEmpty
        else { return self[keyPath: channel.layerPath] }
        // `evaluate` holds flat outside the outermost keys (`AnimationCurve` decision 2), exactly as
        // `Effect.resolved(atFrame:through:)` relies on: a frame before the first key or after the
        // last is that key's value, which is what makes a layer channel safe to ask at *any*
        // document frame, including ones this layer has no cel on.
        return channel.clamped(curve.evaluate(at: Double(frame)))
    }

    /// **The opacity the compositor should use at `frame`** — `resolvedValue` named, because opacity
    /// is read on four paths and a key path at each of them reads worse than a word.
    func opacity(atFrame frame: Int) -> Double { resolvedValue(.opacity, atFrame: frame) }
}

extension LayerFolder {

    /// `Layer.resolvedValue(_:atFrame:)` on the other home — §2.21's rule for grades, reached by the
    /// channel that arrived after it.
    func resolvedValue(_ channel: TargetChannel, atFrame frame: Int) -> Double {
        guard !channelTracks.isEmpty, let curve = channelTracks[channel.id], !curve.isEmpty
        else { return self[keyPath: channel.folderPath] }
        return channel.clamped(curve.evaluate(at: Double(frame)))
    }

    /// The group's opacity at `frame`.
    func opacity(atFrame frame: Int) -> Double { resolvedValue(.opacity, atFrame: frame) }
}
