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
/// on the render path. **The channel plumbing for each of those is one entry in `all` below and two
/// `HistoryActionLabel` cases** — no new store, no new union accessor, no new persistence field, no
/// new arm in the recorder, no new write funnel — because every one of those walks this table or the
/// dictionary it keys. What is *not* free is the feature's own work, and it should not be: the
/// property on both structs, the render path reading `resolvedValue(_:atFrame:)` for it, and
/// whatever control the artist edits it with calling `applyTargetChannelEdit` and `beginArmedTake`.
/// Being able to say which half is which was the test this design had to pass.
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
    ///
    /// **There is deliberately no `controlIdentifier` beside it**, which `EffectParameter` carries
    /// for a reason that does not apply here: that table drives twenty-five generated slider rows,
    /// so each has to name its own accessibility identifier. Each channel of *this* kind is edited
    /// from a bespoke control that already spells one (`layerPanel.row.<n>.opacity`), and a field
    /// nothing reads is a promise nothing keeps. Add it back the day a channel here has no surface
    /// of its own.
    let name: String

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

    /// The `String(format:)` a readout prints this with — `TimelineGraphBand.readout(value:format:)`
    /// applies it to the **stored** value, exactly as `EffectParameter.format` is applied to a
    /// radius in points.
    ///
    /// **So opacity's is `"%.2f"` and not `"%.0f%%"`, which is a trap rather than a preference.**
    /// The value is stored 0…1 and the formatter has no scale factor, so a percentage format would
    /// print a half-faded layer as `"0%"` — a readout that is wrong by a factor of a hundred at
    /// every value the artist can drag to. The slider in the layer panel is a `UISlider`, which
    /// derives its own percentage from its min and max and is unaffected.
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
        uiRange: 0...1,
        modelDomain: 0...1,
        format: "%.2f",
        editLabel: .opacity,
        keyframeLabel: .opacityKeyframes,
        layerPath: \Layer.opacity,
        folderPath: \LayerFolder.opacity)

    /// **An item's share of a Parallax transform layer's move** — TRANSFORM_LAYER.md §5.2, §2
    /// rulings 3–5, the second row of this table and the first to arrive after opacity proved the
    /// shape. Stored as a fraction (1 is 100%) for opacity's reason and read through
    /// `percentText` for the slider's readout.
    ///
    /// **`uiRange` is the slider's 0…100% and `modelDomain` is ten times either side of it**, which
    /// is the owner's *"slider from 0 to 100, but also can input negative values or higher"* stated
    /// as two ranges: the control offers the useful span and a typed number may leave it, a negative
    /// share moving the item the opposite way (`PoseInterpolation.blend` extrapolates). Ten turns is
    /// a bound on absurdity rather than on intent.
    ///
    /// **The stored home is `Layer.parallaxShare`, which is optional, through a non-optional view**
    /// (`parallaxShareValue`), because nil there means "the positional default" and a key path into
    /// an optional is not writable. `Layer.parallaxShare(atFrame:positionalDefault:)` is what the
    /// render reads; the funnel below this table sees only explicit numbers, because the panel
    /// materialises the default before it lets the artist drag (`setParallaxShare`).
    static let parallaxShare = TargetChannel(
        id: "parallaxShare",
        name: "Parallax",
        uiRange: 0...1,
        modelDomain: -10...10,
        format: "%.2f",
        editLabel: .parallaxShare,
        keyframeLabel: .parallaxShareKeyframes,
        layerPath: \Layer.parallaxShareValue,
        folderPath: \LayerFolder.parallaxShareValue)

    /// **How fast a Rotate transform layer turns, in degrees per frame** — TRANSFORM_LAYER.md §5.3
    /// and §2 ruling 6 (*per frame*, so a change of fps changes the wheel's speed on screen exactly
    /// as it changes every other animation's). The render integrates it from the block's first
    /// frame (`TransformLayerMode.integratedRotationDegrees`), so keying it 0 → 15 spins a wheel up
    /// and keying it to 0 stops the wheel where it is.
    ///
    /// `uiRange` is ±30°/frame — 15°/frame is one turn a second at 24 fps, so the slider spans two
    /// turns a second either way; `modelDomain` is a full turn a frame either way, which is where
    /// the picture stops being a spin at all.
    static let rotateSpeed = TargetChannel(
        id: "rotateSpeed",
        name: "Rotate Speed",
        uiRange: -30...30,
        modelDomain: -360...360,
        format: "%.1f",
        editLabel: .rotateSpeed,
        keyframeLabel: .rotateSpeedKeyframes,
        layerPath: \Layer.rotateSpeed,
        folderPath: \LayerFolder.rotateSpeed)

    /// **How far a Shake transform layer jolts sideways, in the box's own points** — TRANSFORM_LAYER.md
    /// §5.4 and §2 ruling 9, the owner's *"Shake x, shake y, rotate shake sliders would be preferred
    /// so that they can be keyframed"*. The render scales value noise in −1…1 by this, so it is an
    /// amplitude: 10 is a jolt of up to ten points either way. `uiRange` is 0…100 points, which is
    /// a hard shake at the owner's 2048-wide canvas; `modelDomain` is wide enough for any canvas
    /// and admits a negative amplitude, which is the same shake mirrored.
    static let shakeX = TargetChannel(
        id: "shakeX",
        name: "Shake X",
        uiRange: 0...100,
        modelDomain: -4096...4096,
        format: "%.0f",
        editLabel: .shakeX,
        keyframeLabel: .shakeXKeyframes,
        layerPath: \Layer.shakeX,
        folderPath: \LayerFolder.shakeX)

    /// `shakeX`'s vertical twin.
    static let shakeY = TargetChannel(
        id: "shakeY",
        name: "Shake Y",
        uiRange: 0...100,
        modelDomain: -4096...4096,
        format: "%.0f",
        editLabel: .shakeY,
        keyframeLabel: .shakeYKeyframes,
        layerPath: \Layer.shakeY,
        folderPath: \LayerFolder.shakeY)

    /// **How far a Shake transform layer rocks, in degrees about the box's centre** — the owner's
    /// *"rotate shake"*. `uiRange` is 0…30°, past which the picture reads as a spin rather than a
    /// rock; `modelDomain` is half a turn either way.
    static let shakeRotation = TargetChannel(
        id: "shakeRotation",
        name: "Rotate Shake",
        uiRange: 0...30,
        modelDomain: -180...180,
        format: "%.1f",
        editLabel: .shakeRotation,
        keyframeLabel: .shakeRotationKeyframes,
        layerPath: \Layer.shakeRotation,
        folderPath: \LayerFolder.shakeRotation)

    /// **Every channel of this kind, in a fixed order.** The order is the channel list's and the
    /// band's colour order, so it is decided here and nowhere else — `Effect.parameters`' contract
    /// one type over.
    static let all: [TargetChannel] = [.opacity, .parallaxShare, .rotateSpeed, .shakeX, .shakeY, .shakeRotation]

    /// The three rows a pose in Shake reads, in the order the panel lists them.
    static let shakeChannels: [TargetChannel] = [.shakeX, .shakeY, .shakeRotation]

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

    /// **Where `value` sits in `uiRange`, as a whole percent** — TODO (59), the owner 2026-09-10:
    /// *"adjusting opacity should display the % when you do."*
    ///
    /// **Not `format`, and the difference is the trap `format`'s own doc records.** That string is
    /// `"%.2f"` and is applied to the *stored* number, which for opacity is 0…1 — so a percentage
    /// spelled there would print a half-faded layer as `"0%"`, wrong by a factor of a hundred at
    /// every value an artist can drag to. The percentage is a different reading of the same number
    /// and gets its own function rather than a second format string that looks interchangeable with
    /// the first.
    ///
    /// **Off `uiRange` rather than multiplying by 100**, so this is the fraction of the control's own
    /// travel: that is what the artist is looking at when they drag a `UISlider` (which derives its
    /// own percentage from its min and max the same way), and it stays right for a future channel
    /// whose range is not 0…1. Clamped into `uiRange` first, because the value handed in is a
    /// slider's live position and the readout must never print 103%.
    func percentText(_ value: Double) -> String {
        let span = uiRange.upperBound - uiRange.lowerBound
        guard span > 0 else { return "0%" }
        let inside = min(max(value, uiRange.lowerBound), uiRange.upperBound)
        return "\(Int(((inside - uiRange.lowerBound) / span * 100).rounded()))%"
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

    /// **`parallaxShare` as the non-optional `Double` a `TargetChannel` key path has to address.**
    /// Writing makes the share explicit; reading a nil share answers 1 — a fallback the funnel is
    /// not meant to reach, because `CanvasManager.setParallaxShare` writes the positional default
    /// through before any edit can be routed, so a seeded keyframe A holds the number the artist
    /// was looking at rather than this constant. The render never reads this; it reads
    /// `parallaxShare(atFrame:positionalDefault:)`.
    var parallaxShareValue: Double {
        get { parallaxShare ?? 1 }
        set { parallaxShare = newValue }
    }

    /// **This item's share at `frame`**: the curve when there is one, the typed number when there is
    /// one, and otherwise the share its position in the stack gives it — TRANSFORM_LAYER.md §5.2's
    /// three-way precedence, which is `resolvedValue`'s two-way one with the positional default
    /// standing where a stored constant would.
    func parallaxShare(atFrame frame: Int, positionalDefault: Double) -> Double {
        if let curve = channelTracks[TargetChannel.parallaxShare.id], !curve.isEmpty {
            return TargetChannel.parallaxShare.clamped(curve.evaluate(at: Double(frame)))
        }
        return parallaxShare ?? positionalDefault
    }

    /// The turn rate at `frame`, degrees per frame — `resolvedValue` named, for `opacity(atFrame:)`'s
    /// reason: it is summed over every frame of a block and a key path in that loop reads worse than
    /// a word.
    func rotateSpeed(atFrame frame: Int) -> Double { resolvedValue(.rotateSpeed, atFrame: frame) }

    /// **Whether this container's pose moves what is beneath it at *any* frame** —
    /// `LayerPose.movesItsContents` widened to the mode, TRANSFORM_LAYER.md §5.3's *"a rotate layer
    /// with an untouched box and a non-zero speed moves everything beneath it, and that predicate is
    /// frame-invariant by contract"*. Reads the speed's *track*, not one frame: a speed keyed 0 → 15
    /// moves the stack at frame 8 and this must say so at frame 0, or `sandwichEngagesOnCanvas`
    /// would swap render paths mid-playback, which is the failure that predicate exists to refuse.
    ///
    /// Parallax needs no clause of its own: a share is a fraction of the authored pose, so with the
    /// authored pose at rest every item is at rest whatever its share, and with it moved at least
    /// the 100% item moves — `movesItsContents` on the pose already answers both.
    var containerPoseMovesContents: Bool {
        guard let pose = layerTransform else { return false }
        return Self.containerPoseMovesContents(pose, stored: { self[keyPath: $0.layerPath] }, tracks: channelTracks)
    }

    /// **The mode clause of `containerPoseMovesContents`, stated once for both homes.** The authored
    /// pose moving is enough in any mode; past that, Rotate moves if its speed is ever non-zero and
    /// Shake if any of its three amplitudes is — each read off the channel's *track* when it has
    /// one (any key off zero, or two keys whose handles could leave it) and off the stored base
    /// otherwise, so a channel keyed 0 → 15 answers yes at frame 0 as well. Move and Parallax add
    /// nothing: a share of a resting pose is rest.
    static func containerPoseMovesContents(_ pose: LayerPose, stored: (TargetChannel) -> Double,
                                           tracks: [String: AnimationCurve]) -> Bool {
        if pose.movesItsContents { return true }
        switch pose.mode {
        case .move, .parallax:
            return false
        case .rotate:
            return channelIsEverNonZero(.rotateSpeed, stored: stored(.rotateSpeed), tracks: tracks)
        case .shake:
            return TargetChannel.shakeChannels.contains {
                channelIsEverNonZero($0, stored: stored($0), tracks: tracks)
            }
        }
    }

    /// One channel's half of the clause above: with a curve the track decides, with none the stored
    /// base does.
    static func channelIsEverNonZero(_ channel: TargetChannel, stored: Double,
                                     tracks: [String: AnimationCurve]) -> Bool {
        if let curve = tracks[channel.id], !curve.isEmpty {
            return curve.isAnimated || curve.keys.contains { $0.value != 0 }
        }
        return stored != 0
    }
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

    /// `Layer.parallaxShareValue` on the folder — the same view, for the same key path.
    var parallaxShareValue: Double {
        get { parallaxShare ?? 1 }
        set { parallaxShare = newValue }
    }

    /// `Layer.parallaxShare(atFrame:positionalDefault:)` on the folder — this folder's share as one
    /// item beneath a parallax layer.
    func parallaxShare(atFrame frame: Int, positionalDefault: Double) -> Double {
        if let curve = channelTracks[TargetChannel.parallaxShare.id], !curve.isEmpty {
            return TargetChannel.parallaxShare.clamped(curve.evaluate(at: Double(frame)))
        }
        return parallaxShare ?? positionalDefault
    }

    /// The group's turn rate at `frame`, degrees per frame.
    func rotateSpeed(atFrame frame: Int) -> Double { resolvedValue(.rotateSpeed, atFrame: frame) }

    /// `Layer.containerPoseMovesContents` on the folder — the same predicate over `transform`.
    var containerPoseMovesContents: Bool {
        guard let pose = transform else { return false }
        return Layer.containerPoseMovesContents(pose, stored: { self[keyPath: $0.folderPath] }, tracks: channelTracks)
    }
}
