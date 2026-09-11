import CoreGraphics
import Foundation

/// **Which drawing inside a cel a pose channel moves** — KEYFRAMES.md §2.11's *"membership is a named
/// animation group"*, plus the case that needs no membership at all.
///
/// **Two cases, and the first is not a degenerate group.** `.cel` is the whole drawing, which is the
/// owner's own screenshake example (§1: *"they want screenshake, the user will press move on the
/// entire canvas and then record"*) and is what the Move tool already does with no selection —
/// LASSO_MOVE.md's *"Move with no selection still moves the whole cel, which is correct as it
/// stands"*. Expressing it as a group whose membership happened to be everything would put the same
/// fact in a field on every element, and it would go wrong the first time the artist drew a new
/// stroke: the new mark would be outside the group and would sit still while the drawing around it
/// moved. `.cel` means *whatever is on this cel*, evaluated per frame, and a stroke drawn afterwards
/// joins the move for free.
///
/// **Stored as a string, in the `effectTracks` idiom.** `"cel"` and `"group.<uuid>"`, so the track
/// dictionary is `[String: TransformTrack]` exactly as a grade's is `[String: AnimationCurve]` and
/// both are keyed containers on the wire. The prefix before the first dot is also the grouping key
/// `TimelineGraphChannelList.groupID(ofParameterID:)` already reads, so a transform channel lands in
/// the channel list's existing shape rather than needing a second one.
enum TransformChannelID: Hashable {

    /// Everything the cel holds, resolved at render time.
    case cel

    /// One `AnimationGroup`'s members — the elements carrying this `animationGroupID`.
    case group(UUID)

    var id: String {
        switch self {
        case .cel: return "cel"
        case .group(let uuid): return "group.\(uuid.uuidString)"
        }
    }

    /// The inverse, for reading a stored dictionary back. Nil for an id from a future version rather
    /// than a trap, so an unknown channel is ignored the way an inert effect track is
    /// (`Effect.resolved` walks the descriptors, never the dictionary).
    init?(id: String) {
        if id == "cel" { self = .cel; return }
        guard id.hasPrefix("group."), let uuid = UUID(uuidString: String(id.dropFirst(6))) else { return nil }
        self = .group(uuid)
    }
}

/// **One pose channel: where a drawing is, over the frames its cel spans** — KEYFRAMES.md build-order
/// stage 5, and §2.5's *"a transform key stores a pose"*.
///
/// ## Its time base is cel-local, and that is §3.1 rather than a convenience
///
/// Keys are numbered from the cel's own `startFrame`, so the channel rides the cel through move,
/// split, duplicate and paste for free — the same argument `motionGroupID`'s doc makes for a field
/// over a side table. A *layer* channel (an effect parameter, §2.4) is in absolute document frames
/// because its target has no cel to ride. There is no third notion. **And a key is never outside the
/// cel's span** (TODO 62): `cropped(toFrameCount:)` and `shifted(by:)` below are what a span change
/// applies, through `Cel.cropPoseKeysToSpan`.
///
/// ## Why the timing is an `AnimationCurve` over pose *indices* rather than a second interpolant
///
/// The keys hold poses, which cannot be lerped (`PoseInterpolation` is the whole of why), but the
/// *timing* between two poses is an ordinary scalar problem that `AnimationCurve` has already solved:
/// per-segment `constant` / `linear` / `bezier` carried on the key that begins the segment, five
/// tangent modes, unclamped overshoot, a constant hold outside the first and last key, and §2.10's
/// `step`. So `timing` is an `AnimationCurve` whose key values are `0, 1, 2, …` — the index of the
/// pose each key holds — and evaluating it at a frame gives a **fractional pose index**: the pair to
/// blend and how far between them.
///
/// **It is computed from `keys`, never stored beside them.** Two lists of the same length whose
/// entries correspond is a drift hazard the first time a writer touches one and not the other; this
/// is §2.28's "computed, never stored" applied one type down. The cost is rebuilding a small array
/// per evaluation, behind the `keys.count < 2` fast path that covers every static channel.
///
/// **Overshoot is a feature here and reads unusually.** A `.free` or `.auto` handle can carry the
/// index past its segment, and `PoseInterpolation.blend` extrapolates rather than clamping — so a
/// move can overshoot its mark and settle back, which is what makes it read as weight. `.autoClamped`
/// is the default and does not, exactly as it does not for a slider.
struct TransformTrack: Equatable {

    /// One authored pose at one cel-local frame, with the graph-editor vocabulary
    /// `AnimationCurve.Key` already carries so that a pose channel and a value channel are edited by
    /// one set of gestures rather than two.
    struct Key: Equatable {
        /// Cel-local. Integer for `AnimationCurve.Key.frame`'s reason: there is nothing an artist can
        /// do in the timeline to land one between two frames.
        var frame: Int
        var pose: PoseQuad
        var inHandle: AnimationCurve.Handle
        var outHandle: AnimationCurve.Handle
        var tangentMode: AnimationCurve.TangentMode
        /// The segment that *begins* here. Ignored on the last key, which begins nothing.
        var interpolation: AnimationCurve.Interpolation

        init(frame: Int,
             pose: PoseQuad,
             inHandle: AnimationCurve.Handle = .zero,
             outHandle: AnimationCurve.Handle = .zero,
             tangentMode: AnimationCurve.TangentMode = .autoClamped,
             interpolation: AnimationCurve.Interpolation = .bezier) {
            self.frame = frame
            self.pose = pose
            self.inHandle = inHandle
            self.outHandle = outHandle
            self.tangentMode = tangentMode
            self.interpolation = interpolation
        }
    }

    /// Sorted by frame, one key per frame — `AnimationCurve`'s decision 4, restated here because the
    /// timing spine is built by index and a duplicate frame would make two indices name one moment.
    private(set) var keys: [Key]

    /// Evaluate, then hold the result for this many frames (§2.10). Anchored at frame 0 of this
    /// track's own — cel-local — base, `AnimationCurve.step`'s rule.
    var step: Int

    var isEmpty: Bool { keys.isEmpty }

    /// **Whether this channel is an *animation*** — the owner's definition applied to poses: two or
    /// more keys, and not every key holding the same pose. The strict predicate, as
    /// `AnimationCurve.isAnimated` is for a value channel, and it is what the channel list asks;
    /// routing asks the loose one (does it have a track at all). Do not merge them — a track whose
    /// two keys hold the same pose is still *in force*, and a Move routed to the geometry instead
    /// would be overwritten by the track at every frame.
    var isAnimated: Bool {
        guard let first = keys.first, keys.count > 1 else { return false }
        return keys.contains { $0.pose != first.pose }
    }

    init(keys: [Key] = [], step: Int = 1) {
        self.keys = Self.normalised(keys)
        self.step = step
    }

    // MARK: - Editing

    /// Inserts `key`, or replaces the one already on its frame.
    mutating func setKey(_ key: Key) {
        if let i = keys.firstIndex(where: { $0.frame == key.frame }) {
            keys[i] = key
        } else if let i = keys.firstIndex(where: { $0.frame > key.frame }) {
            keys.insert(key, at: i)
        } else {
            keys.append(key)
        }
    }

    mutating func removeKey(atFrame frame: Int) { keys.removeAll { $0.frame == frame } }

    func key(atFrame frame: Int) -> Key? { keys.first { $0.frame == frame } }

    /// Every frame this channel holds a key on — what `CanvasManager.keyframeFrames(of:)` folds into
    /// §2.28's union, converted to absolute frames by its caller because only the caller knows the
    /// cel's `startFrame`.
    var keyedFrames: [Int] { keys.map(\.frame) }

    /// **This channel cut in two at a cel-local frame** — KEYFRAMES.md §3.1's rule for `splitCel`:
    /// *"keys before the cut go left, keys after go right, and a key is inserted at the cut in both so
    /// the value is continuous across it."*
    ///
    /// `cut` is the first cel-local frame of the **right** half, so the left half spans `0..<cut` and
    /// a key of the right half at original frame `f` lands at `f - cut`.
    ///
    /// **The right half's inserted key is the pose this track already shows at `cut`; the left half's
    /// is the pose it shows at `cut - 1`, its own last frame.** Both are what make *"so the value is
    /// continuous"* true at every frame either half draws. The left one is needed at all because
    /// without it the left half's frames from its last real key onward would hold that key's pose
    /// flat (`AnimationCurve`'s decision 2 reaching here through `timing`) instead of continuing to
    /// travel, and the artist would watch a moving drawing stop dead before the cut.
    ///
    /// **It lands on `cut - 1` rather than on `cut`, and that is TODO (62).** Until 2026-09-11 the left
    /// half kept a key at `cut` — one frame *past* its own span — on the strength of §3.1's old resize
    /// rule that a key outside a span is held. The owner reversed that rule: a key beyond a cel's span
    /// is deleted, so a split may not mint one. A key on the last frame the half actually draws says
    /// the same thing about every frame the artist can see, and is inside the span, so the crop that
    /// follows a split (`Cel.cropPoseKeysToSpan`) finds nothing to remove on a track this produced.
    ///
    /// **What is lost is stated rather than hidden.** A segment that spans the cut is re-parameterised
    /// on both sides: `[k₀, cut - 1]` and `[cut, k₁]` each become a segment of their own, so the
    /// easing *within* that one span is not the easing it had. Every other frame's pose is unchanged,
    /// which is the strongest statement §3.1's rule admits — a single bezier cannot be two beziers.
    ///
    /// **A key that already sits exactly on the cut is carried across whole to the right half, not
    /// re-synthesised.** Its pose is what `pose(atCelLocalFrame: cut)` would answer anyway, but its
    /// handles and tangent mode are not recoverable from a pose, and a split is not an occasion to
    /// flatten an authored ease. The left half still needs its own key at `cut - 1` in that case, since
    /// the key on the cut is not one of its frames. A key already on `cut - 1` is likewise kept whole.
    ///
    /// Empty halves are never returned: an empty track cannot exist in `Cel.transformTracks`
    /// (`clearPoseKeys` removes a channel left with no keys), and a track with keys yields a key at
    /// each half's boundary whatever the keys are. `step` rides unchanged onto both, which does re-phase
    /// the right half — its frame 0 is the original `cut` and §2.10 anchors a step at frame 0 of the
    /// track's own base. Rescaling it instead would retime the animation, which is the thing §3.1
    /// refuses for the resize handles and refuses here for the same reason.
    func split(atCelLocalFrame cut: Int) -> (left: TransformTrack, right: TransformTrack) {
        guard let atCut = pose(atCelLocalFrame: cut),
              let beforeCut = pose(atCelLocalFrame: cut - 1) else { return (self, self) }
        // **The inserted keys inherit the interpolation of the segment they land in**, which matters on
        // the right half and only there: a key's `interpolation` describes the segment it *begins*, so
        // the right half's first segment would otherwise be `.bezier` — `Key`'s default — whatever the
        // artist authored. A `.constant` hold cut in two would start easing, and a `.linear` span
        // would gain a curve at the join. The left half's inserted key is its last and begins nothing,
        // and takes the same value so that the two halves read alike.
        let segment = keys.last { $0.frame <= cut }?.interpolation ?? .bezier
        var left = TransformTrack(keys: keys.filter { $0.frame < cut }, step: step)
        if key(atFrame: cut - 1) == nil {
            left.setKey(Key(frame: cut - 1, pose: beforeCut, interpolation: segment))
        }
        var right = TransformTrack(keys: keys.filter { $0.frame >= cut }.map {
            var moved = $0
            moved.frame -= cut
            return moved
        }, step: step)
        if key(atFrame: cut) == nil { right.setKey(Key(frame: 0, pose: atCut, interpolation: segment)) }
        return (left, right)
    }

    // MARK: - Keeping keys inside the cel's span — TODO (62)

    /// Every key moved by `delta` cel-local frames. What a **left-edge** resize does to a track before
    /// cropping it: the cel's origin moves and its keys stay on the document frames they were on, so
    /// their cel-local numbers move the other way. A key that lands below 0 is then outside the span
    /// and `cropped(toFrameCount:)` removes it.
    ///
    /// `step` rides unchanged, which re-phases it exactly as `split` re-phases the right half's — and
    /// for the same reason: §2.10 anchors a step at frame 0 of the track's own base, and rescaling
    /// would retime the animation as a side effect of dragging a cel edge.
    func shifted(by delta: Int) -> TransformTrack {
        guard delta != 0 else { return self }
        return TransformTrack(keys: keys.map { key in
            var moved = key
            moved.frame += delta
            return moved
        }, step: step)
    }

    /// **The keys inside `0..<frameCount`, and the cel-local frames of the ones that were not** —
    /// TODO (62)'s rule, settled 2026-09-10 and revised 2026-09-11: *keys beyond a cel's span are
    /// deleted, and shortening a cel crops the keys past its new end* — but **before** a key past an
    /// edge is removed, a key is inserted at the new edge carrying the pose the track showed there,
    /// so the frames that remain keep the motion they had up to the new end instead of snapping to
    /// whichever key happened to still be inside. Nothing here rescales or clamps a key *onto* the
    /// edge — the survivors keep their own frames exactly — it is only the edge itself that gains a
    /// key when one did not already stand there.
    ///
    /// **Both edges, not only the end**, on the owner's ruling of 2026-09-11 — this file's reading of
    /// symmetry, not a separate ruling of its own; a key below 0 is as far outside the span as one at
    /// `frameCount`, and a left-edge resize (`shifted(by:)`) is what produces one. The new *first*
    /// frame (0) gets the same treatment as the new *last* frame (`frameCount - 1`).
    ///
    /// **The inserted key's pose comes from `self`, before anything is removed** — `pose(atCelLocalFrame:)`
    /// evaluated against the full, uncropped track, exactly as `split` samples `beforeCut` and `atCut`
    /// from the whole track before slicing it. Its interpolation is inherited from the segment that
    /// was carrying the edge, `split`'s same idea, so a `.constant` hold reads as a hold across the
    /// join and a `.linear` ramp does not gain a curve it wasn't authored with.
    ///
    /// **Only inserted when a key past that edge is actually being removed.** A crop that discards
    /// nothing changes nothing — the common case of a cel that already fits its span costs one
    /// `isEmpty` and two no-op `contains` checks. And nothing is inserted where a key already stands
    /// on the edge: the survivor there already says what the new edge shows, and re-minting it would
    /// only flatten a handle or a tangent mode it does not need to lose.
    func cropped(toFrameCount frameCount: Int) -> (kept: TransformTrack, discarded: [Int]) {
        let discardedBelow = keys.contains { $0.frame < 0 }
        let discardedAbove = keys.contains { $0.frame >= frameCount }
        guard discardedBelow || discardedAbove else { return (self, []) }

        var working = keys
        if discardedAbove, frameCount > 0, key(atFrame: frameCount - 1) == nil,
           let edgePose = pose(atCelLocalFrame: frameCount - 1) {
            // The last key still inside is ignored on the segment field of the key that begins
            // nothing (`Key.interpolation`'s own doc), so which segment this inherits from cannot
            // matter for the picture — carried for the same "reads alike" reason `split` gives.
            let segment = keys.last { $0.frame <= frameCount - 1 }?.interpolation ?? .bezier
            working.append(Key(frame: frameCount - 1, pose: edgePose, interpolation: segment))
        }
        if discardedBelow, key(atFrame: 0) == nil, let edgePose = pose(atCelLocalFrame: 0) {
            // Frame 0 begins the segment that follows it, and does matter: this inherits the
            // interpolation of whichever key was carrying frame 0 before the crop, so the new first
            // key continues the ease the removed one started rather than defaulting to `.bezier`.
            let segment = keys.last { $0.frame <= 0 }?.interpolation ?? .bezier
            working.append(Key(frame: 0, pose: edgePose, interpolation: segment))
        }

        let discarded = keys.filter { $0.frame < 0 || $0.frame >= frameCount }.map(\.frame)
        let kept = working.filter { $0.frame >= 0 && $0.frame < frameCount }
        return (TransformTrack(keys: kept, step: step), discarded)
    }

    private static func normalised(_ input: [Key]) -> [Key] {
        guard input.count > 1 else { return input }
        let sorted = input.enumerated()
            .sorted { $0.element.frame == $1.element.frame ? $0.offset < $1.offset
                                                           : $0.element.frame < $1.element.frame }
            .map(\.element)
        var out: [Key] = []
        out.reserveCapacity(sorted.count)
        for key in sorted {
            if out.last?.frame == key.frame { out[out.count - 1] = key } else { out.append(key) }
        }
        return out
    }

    // MARK: - Evaluation

    /// The timing spine: `AnimationCurve` over pose indices. Computed, never stored — see the type's
    /// own header for why.
    var timing: AnimationCurve {
        AnimationCurve(keys: keys.enumerated().map { index, key in
            AnimationCurve.Key(frame: key.frame, value: Double(index),
                               inHandle: key.inHandle, outHandle: key.outHandle,
                               tangentMode: key.tangentMode, interpolation: key.interpolation)
        }, step: step)
    }

    /// **The pose this channel shows at a cel-local frame**, or nil when it holds no keys.
    ///
    /// One key is a constant hold at that pose, which is `AnimationCurve`'s decision 2 arriving here
    /// for free rather than as a special case. Outside the first and last key the same rule holds the
    /// end poses, so a drawing moved by a track stays where the last key put it rather than drifting
    /// off the end of a linear extrapolation.
    func pose(atCelLocalFrame frame: Int) -> PoseQuad? { pose(atCelLocalTime: Double(frame)) }

    /// The continuous form, for a graph editor that scrubs along the curve rather than along the
    /// frame ruler — `AnimationCurve.evaluate(at:)`'s own argument for taking a `Double`.
    func pose(atCelLocalTime time: Double) -> PoseQuad? {
        guard let first = keys.first else { return nil }
        guard keys.count > 1 else { return first.pose }

        let index = timing.evaluate(at: time)
        // The segment, clamped to a real pair. The *fraction* is deliberately left unclamped inside
        // it: an overshooting handle is meant to carry the blend past its key, and
        // `PoseInterpolation.blend` extrapolates correctly for it.
        let lower = min(max(Int(index.rounded(.down)), 0), keys.count - 2)
        let t = CGFloat(index - Double(lower))
        return PoseInterpolation.blend(keys[lower].pose, keys[lower + 1].pose, t: t)
    }

    /// The map a renderer carries ink through at a cel-local frame, or nil when this channel shows
    /// the drawing where it rests.
    ///
    /// **Nil for a resting pose is load-bearing rather than an optimisation.** It is what decides
    /// whether the cel has a derivation at that frame at all, and a derivation costs a canvas-sized
    /// render and a second entry in two caches (§4.5). A track whose keys all hold the rest pose —
    /// which is exactly what §2.27's seeding writes before the artist has moved anything — must
    /// therefore cost the document nothing.
    ///
    /// **A `PoseMap` rather than a `CGAffineTransform`, which is KEYFRAMES.md §8 stage 5b** — the
    /// first of this file's two render reads. It used to answer a keystone with its linearisation at
    /// the box centre: MEASURED 218% wrong in local scale and
    /// 164 px out at the far corner of a 400x300 box pulled to a 120 pt top edge. A `PoseMap` is the
    /// affine when the pose is one — bit for bit, so every stage-5 document is the document it was —
    /// and the homography when it is not.
    func mapping(atCelLocalFrame frame: Int) -> PoseMap? {
        guard let pose = pose(atCelLocalFrame: frame), !pose.isIdentity,
              let map = pose.map, !map.isIdentity
        else { return nil }
        return map
    }

    /// **The same two evaluations, spelled for a track whose base is not a cel's.**
    ///
    /// §3.1 gives a layer- or folder-scoped channel **absolute document frames**, because its target
    /// has no cel to ride — so the frame handed in is the playhead's own number and there is no
    /// `startFrame` to subtract. The arithmetic is identical and these delegate; what differs is the
    /// argument label, and that is the whole reason they exist. A label reading `atCelLocalFrame:` on
    /// a channel that has no cel is a lie a later reader corrects by subtracting a `startFrame` that
    /// is not there.
    func pose(atDocumentFrame frame: Int) -> PoseQuad? { pose(atCelLocalFrame: frame) }

    func mapping(atDocumentFrame frame: Int) -> PoseMap? { mapping(atCelLocalFrame: frame) }
}

// MARK: - What a span change discarded (TODO 62)

/// **The pose keys a change to a cel's span threw away** — TODO (62)'s *"it says what it discarded"*,
/// in the form the notice and the tests read.
///
/// The owner chose the crop with its objection in front of them (*"you'd lengthen the cel again and
/// find the animation gone"*), and this type is the mitigation they asked for instead of the bare
/// rule: a crop is not allowed to happen in silence. Every verb that shortens a span returns one of
/// these, `CanvasManager.noteKeyframeCrop` carries it to the banner once the undo step that owns the
/// crop is on the stack, and the banner names the count and the frames.
///
/// **Frames are absolute document frames**, not cel-local ones, because the artist reads the ruler.
/// A key at cel-local 9 on a block starting at frame 20 is "the keyframe at 29" to them, and that is
/// what the sentence says.
struct KeyframeCrop: Equatable {

    /// Channel id (`TransformChannelID.id`) → the absolute frames of the keys removed, ascending.
    private(set) var discarded: [String: [Int]] = [:]

    var isEmpty: Bool { discarded.isEmpty }

    /// How many keys went, across every channel.
    var count: Int { discarded.values.reduce(0) { $0 + $1.count } }

    /// Every frame a key was removed from, across channels, ascending and unique — two channels
    /// keyed on one frame lose two keys and name one frame.
    var frames: [Int] { Set(discarded.values.joined()).sorted() }

    mutating func record(channel: String, frames: [Int]) {
        guard !frames.isEmpty else { return }
        discarded[channel, default: []] = ((discarded[channel] ?? []) + frames).sorted()
    }

    /// Folds another crop into this one — `splitCel` crops two halves and reports once.
    mutating func merge(_ other: KeyframeCrop) {
        for (channel, frames) in other.discarded { record(channel: channel, frames: frames) }
    }
}

extension Cel {

    /// **Removes every pose key outside this cel's span, from every channel, and says what went** —
    /// the one crop, which every verb that can leave a key outside a span calls (TODO 62).
    ///
    /// A key is outside when its cel-local frame is below 0 or at or past `frameCount`. A channel left
    /// with no keys is removed rather than stored empty, which is `removeTransformPoseKey`'s rule on
    /// the same payload: an empty `TransformTrack` in the dictionary is a channel the graph editor
    /// would list and draw as a flat, unkeyed line.
    ///
    /// **`pendingPoseBaselines` is left alone.** A held pose is not a key and has no frame — it is
    /// §2.27's *"the previous value is held"*, waiting for the next keyframe mark to commit it — so
    /// there is nothing about it that can be outside a span.
    ///
    /// - Parameter delta: how far to move every key's cel-local frame **first**. A left-edge resize
    ///   moves the cel's origin by `newStart - oldStart` and the keys stay on the document frames
    ///   they were on, so the caller passes `oldStart - newStart`; every other caller passes nothing.
    /// - Returns: what was removed, in absolute frames. Empty for the overwhelmingly common case of a
    ///   cel with no channels, which costs one `isEmpty`.
    @discardableResult
    mutating func cropPoseKeysToSpan(shiftingKeysBy delta: Int = 0) -> KeyframeCrop {
        var crop = KeyframeCrop()
        guard !transformTracks.isEmpty else { return crop }
        for (id, track) in transformTracks {
            let (kept, discarded) = track.shifted(by: delta).cropped(toFrameCount: frameCount)
            crop.record(channel: id, frames: discarded.map { startFrame + $0 })
            if kept.isEmpty {
                transformTracks.removeValue(forKey: id)
            } else if kept != track {
                transformTracks[id] = kept
            }
        }
        return crop
    }
}

// MARK: - The container pose (§2.3, §4.4)

/// **The pose a *container* shows everything inside it at** — KEYFRAMES.md §2.3's transformation
/// layer and §4.4, plus §2.21's folder twin of the same thing.
///
/// ## What it is, and what it is not
///
/// §2.3: *"A transformation layer re-poses the vector objects below it, rather than resampling the
/// composited pixels below it. The owner wants crisp lines, not a bitmap magnify."* So this is not a
/// blend mode and cannot be — §4.4 says all 25 modes are per-channel colour functions over two
/// same-size, same-position images, with no positional argument anywhere in either backend. It is
/// applied where the ink is **stamped**, not where the pixels are composited.
///
/// **Its two homes are the two homes `Effect` already has**, and that symmetry is §2.21's ruling
/// rather than a convenience: `Layer.transform` is the transformation *layer*, which poses
/// everything beneath it inside its own container, and `LayerFolder.transform` poses the folder's
/// own contents. `Layer.layerEffect` / `LayerFolder.effect` is the exact precedent, one field over,
/// and the reasoning §2.21 gives for refusing to let the two differ applies word for word.
///
/// ## Two fields, because a channel needs a base and a pose channel's base is not the geometry
///
/// `CanvasManager.CelPoseState` notes that a *cel* channel needs no stored base — a Move with no
/// keyframes bakes into `VectorCanvas.elements` and the pose describing where that geometry sits
/// relative to itself is the identity. **A container channel has no geometry to bake into**: a
/// transform layer holds no pixels and a folder holds only children, so the pose the artist set with
/// nothing keyed has to be stored, exactly as `Layer.effect` stores the number a slider writes. That
/// is `pose` below; `track` is what animates it.
///
/// **The track is nested rather than a sibling field**, which is the one place this departs from
/// `effect`/`effectTracks`. There the rule *"this layer's tracks are exactly the ones its current
/// effect can drive"* has to be enforced by four writers calling `Effect.tracksAddressed(by:from:)`,
/// because a grade can change shape underneath its channels. A pose channel cannot: there is exactly
/// one of it, it addresses the container itself, and its shape never varies. Nesting makes "a channel
/// never outlives the thing it addresses" structural instead of a rule somebody has to remember.
struct LayerPose: Equatable {

    /// Where the container puts its contents when nothing is keyed — §2.5's stored base, and the
    /// pose a future Move-on-a-transform-layer writes.
    var pose: PoseQuad

    /// The keyframe channel, in **absolute document frames** (§3.1, and see `LayerFolder.effectTracks`
    /// for why a folder's argument for absolute time is stronger than a layer's rather than weaker).
    /// Empty on a container the artist has posed but not animated.
    var track: TransformTrack

    /// **The pose this container was showing before the artist moved it between two keyframe marks**
    /// — §2.27's *"the previous value is held"*, in the container channel's own currency, and nil on
    /// a container with nothing held.
    ///
    /// **A field here rather than an entry in `Layer.pendingBaselines`**, which is where a *grade's*
    /// held values live. That dictionary is `[String: Double]` keyed by `EffectParameter.id`, and a
    /// pose is neither a `Double` nor addressed by a parameter id; widening it would make every
    /// effect writer that walks it (`Effect.channelEntriesAddressed(by:from:)` prunes it against the
    /// grade's descriptors) either see an entry it cannot name or throw one away it should not. It
    /// is nested beside the track for `LayerPose`'s own stated reason — there is exactly one
    /// container channel and its shape never varies, so "a baseline never outlives the thing it
    /// addresses" stays structural.
    ///
    /// **Persisted, and that is §2.27's own ruling rather than a convenience**: the gap between
    /// keyframe A and keyframe B can span a save, and losing the held pose across a reopen makes
    /// placing B write two identical keys and produce no animation — a wrong result with nothing on
    /// screen to explain it.
    var baseline: PoseQuad? = nil

    /// **What this container does with the pose above** — TRANSFORM_LAYER.md §5's modes. `.move`
    /// applies it; `.parallax` hands each item beneath its own share of it; `.rotate` pre-composes a
    /// turn about the box's centre whose angle grows with the frame. The mode qualifies the pose and
    /// is stored beside it for `track`'s reason: there is exactly one container channel, so "a mode
    /// never outlives the pose it qualifies" stays structural.
    ///
    /// **The three writers of the pose leave it alone**: `showContainerPoseLive`, `commitContainerPose`
    /// and the keyframe arms all copy a `LayerPose` and change `pose`, `track` or `baseline`, so the
    /// mode rides through a Move made in any mode — which is §6's factorisation, *"the pose is
    /// `authored(f) ∘ mode(f)`, and the writers key `authored`"*.
    ///
    /// Defaults to `.move`, and decodes to it when absent, which is what every document written
    /// before 2026-09-11 says and what every pose nobody has switched says — one meaning.
    var mode: TransformLayerMode = .move

    /// **The shake's seed** — TRANSFORM_LAYER.md §5.4, §2 ruling 9: *"the same every time you play …
    /// with a 'new shake' button"*. Minted when the pose is switched into Shake and re-rolled by the
    /// panel's button (one undo step); every noise sample is a pure function of it, so a saved
    /// document shakes exactly as it did. **Not keyable and not a `TargetChannel` row** (§3.3's
    /// closing line) — it is a name for a pattern, not a quantity to animate — so it lives here
    /// beside the mode rather than on the two homes. Zero is "never minted", which a pose in any
    /// other mode carries and which encodes as absent.
    var shakeSeed: UInt64 = 0

    /// **Frames per beat of the shake** — ruling 10's one *speed* control, *"a new position every
    /// frame, or a smoother wobble"*: 1 is a jolt every frame, larger eases between beats. Not
    /// keyable at first (§5.4: a varying period needs phase integration, exactly rotate's argument),
    /// so it sits here with the seed. Encoded only when it is not 1.
    var shakePeriod: Int = 1

    /// **The loop's length in frames, for a pose in Repeat** — TRANSFORM_LAYER.md §5.5, §2 ruling 11:
    /// *"you type the loop's length, pre-filled from where the drawings beneath end"*. A number on the
    /// layer and never inferred at render time, because a background running the whole scene beneath
    /// the walk would otherwise silently stop the walk looping. Zero is "never set" — a pose in any
    /// other mode carries it and it encodes as absent — and loops nothing; `setTransformLayerMode`
    /// fills it in on the way into Repeat. Not keyable, so it sits here with the shake's seed.
    var repeatPeriod: Int = 0

    init(pose: PoseQuad, track: TransformTrack = TransformTrack(), baseline: PoseQuad? = nil,
         mode: TransformLayerMode = .move, shakeSeed: UInt64 = 0, shakePeriod: Int = 1,
         repeatPeriod: Int = 0) {
        self.pose = pose
        self.track = track
        self.baseline = baseline
        self.mode = mode
        self.shakeSeed = shakeSeed
        self.shakePeriod = shakePeriod
        self.repeatPeriod = repeatPeriod
    }

    /// **Whether this pose loops the frames beneath it at all** — in Repeat with a period set. The
    /// one predicate the render walk, the edit redirect and the timeline's ghosts read, so the three
    /// cannot disagree about which layers loop.
    var repeats: Bool { mode == .repeat && repeatPeriod >= 1 }

    /// A container that shows its contents exactly where they are — what a freshly created
    /// transformation layer holds, and the value §2.5's *"a state of the unmoved item at keyframe A"*
    /// means one level out.
    init(restingIn box: CGRect) { self.init(pose: PoseQuad(restingIn: box)) }

    /// §2.26's stricter predicate, for the channel list: two or more keys not all holding one pose.
    var isAnimated: Bool { track.isAnimated }

    /// The pose at one document frame — **the track when it holds keys, the stored base otherwise.**
    ///
    /// The same precedence `Layer.layerEffect(atFrame:)` has: a channel that exists is what the
    /// render reads, and the stored value is what a channel-free container shows at every frame.
    func resolvedPose(atFrame frame: Int) -> PoseQuad {
        track.pose(atDocumentFrame: frame) ?? pose
    }

    /// **The map this container carries its contents through at `frame`, or nil when it shows them
    /// where they are.**
    ///
    /// Nil for a resting pose is load-bearing rather than an optimisation, for
    /// `TransformTrack.mapping(atCelLocalFrame:)`'s reason reached one level out: it is what decides
    /// whether the leaves underneath have a derivation at all, and a derivation costs a canvas-sized
    /// render plus an entry in each of three caches (§4.5). A transformation layer the artist has
    /// added and not yet moved must therefore cost the document nothing.
    ///
    /// **This is the second of stage 5b's two render reads**, and widening it is what let
    /// `distortUnavailableReason` stop refusing a container float: the sentence it said named this
    /// accessor's linearisation as the reason, so the refusal ended when the linearisation did.
    func mapping(atFrame frame: Int) -> PoseMap? {
        let resolved = resolvedPose(atFrame: frame)
        guard !resolved.isIdentity, let map = resolved.map, !map.isIdentity else { return nil }
        return map
    }

    /// **Whether this container moves its contents at *any* frame** — `mapping(atFrame:)` asked
    /// without a frame, which is what a decision that must not flip mid-playback has to ask.
    ///
    /// `CanvasManager.sandwichEngagesOnCanvas` is the caller and the frame-invariance is its whole
    /// requirement: a predicate that answered per frame would swap the live canvas between Core
    /// Animation's flat hosts and the compositor as the playhead crossed the frame where a move
    /// starts, which is the failure `RenderNode.needsCompositorOnCanvas` refuses one line up when it
    /// declines to consult visibility.
    ///
    /// **It follows `resolvedPose`'s precedence exactly rather than testing both halves**, so a
    /// container whose stored base is posed but whose track holds only resting keys answers false —
    /// which is what it renders as. The one direction it is deliberately loose in is the segment
    /// between two keys: two resting keys cannot interpolate to anything but rest, so testing the
    /// keys is exact for every curve `TransformTrack` can hold.
    var movesItsContents: Bool {
        guard !track.isEmpty else { return !pose.isIdentity }
        return track.keys.contains { !$0.pose.isIdentity }
    }
}

extension LayerPose: Codable {

    private enum CodingKeys: String, CodingKey { case pose, track, baseline, mode, shakeSeed, shakePeriod, repeatPeriod }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pose = try c.decode(PoseQuad.self, forKey: .pose)
        track = try c.decodeIfPresent(TransformTrack.self, forKey: .track) ?? TransformTrack()
        baseline = try c.decodeIfPresent(PoseQuad.self, forKey: .baseline)
        // Absent is Move — every document written before the modes existed, and every pose nobody
        // has switched. `decodeIfPresent` rather than a tolerant `try?`: a mode string this build
        // does not know is a newer build's document, and TRANSFORM_LAYER.md §3.2 already accepts
        // that an older build cannot open one; silently reading Shake as Move would be a wrong
        // picture with nothing on screen to say so.
        mode = try c.decodeIfPresent(TransformLayerMode.self, forKey: .mode) ?? .move
        // Absent is "never minted" and "one beat a frame" — what every pose written before stage 4
        // says, and what every pose that has never been in Shake says.
        shakeSeed = try c.decodeIfPresent(UInt64.self, forKey: .shakeSeed) ?? 0
        shakePeriod = try c.decodeIfPresent(Int.self, forKey: .shakePeriod) ?? 1
        repeatPeriod = try c.decodeIfPresent(Int.self, forKey: .repeatPeriod) ?? 0
    }

    /// Hand-written so that `mode` is **written only when it is not Move** — §3.5's field-presence
    /// idiom: a document whose transform layers are all in Move stays byte-for-byte the manifest it
    /// was, and an older build reading one that carries the key ignores it and shows the pose
    /// un-moded, which is the graceful half.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pose, forKey: .pose)
        try c.encode(track, forKey: .track)
        try c.encodeIfPresent(baseline, forKey: .baseline)
        if mode != .move { try c.encode(mode, forKey: .mode) }
        if shakeSeed != 0 { try c.encode(shakeSeed, forKey: .shakeSeed) }
        if shakePeriod != 1 { try c.encode(shakePeriod, forKey: .shakePeriod) }
        if repeatPeriod != 0 { try c.encode(repeatPeriod, forKey: .repeatPeriod) }
    }
}

// MARK: - Codable

/// Field-presence versioning, the idiom every persisted field in this tree follows: a track written
/// before a field existed decodes to the default rather than failing.
extension TransformTrack: Codable {

    private enum CodingKeys: String, CodingKey { case keys, step }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keys = Self.normalised(try c.decodeIfPresent([Key].self, forKey: .keys) ?? [])
        step = try c.decodeIfPresent(Int.self, forKey: .step) ?? 1
    }
}

extension TransformTrack.Key: Codable {

    private enum CodingKeys: String, CodingKey {
        case frame, pose, inHandle, outHandle, tangentMode, interpolation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frame = try c.decode(Int.self, forKey: .frame)
        pose = try c.decode(PoseQuad.self, forKey: .pose)
        inHandle = try c.decodeIfPresent(AnimationCurve.Handle.self, forKey: .inHandle) ?? .zero
        outHandle = try c.decodeIfPresent(AnimationCurve.Handle.self, forKey: .outHandle) ?? .zero
        tangentMode = try c.decodeIfPresent(AnimationCurve.TangentMode.self, forKey: .tangentMode)
            ?? .autoClamped
        interpolation = try c.decodeIfPresent(AnimationCurve.Interpolation.self, forKey: .interpolation)
            ?? .bezier
    }
}

// MARK: - The cel's animation sidecar

/// **What `drawings/<celID>-animation.json` holds** — KEYFRAMES.md §3.5's track sidecar, named
/// from `CelManifest.animationFileName`. It was `images/<celID>_anim.json` until TODO (57) part 1
/// moved the per-cel JSON out from under the pixels; a package written before that still names it
/// bare, and `ProjectPackageLayout.existingURL` resolves either.
///
/// **Its own file rather than inline in `manifest.json`**, exactly as `interpolationFileName` works
/// and for the reason that one states: the manifest is read in full for every gallery tile, and a
/// pose channel is unbounded — §5's recorder turns a three-second shake into dozens of keys, and
/// there is a channel per animation group.
///
/// **A struct rather than two loose dictionaries**, so the field-presence idiom has somewhere to
/// live: a sidecar written before `baselines` existed decodes to an empty one rather than failing,
/// and the cel then loads with its animation and no held pose, which is the correct reading of a
/// file that predates the field.
struct CelAnimationData: Codable {
    var tracks: [String: TransformTrack]
    var baselines: [String: PoseQuad]

    init(tracks: [String: TransformTrack] = [:], baselines: [String: PoseQuad] = [:]) {
        self.tracks = tracks
        self.baselines = baselines
    }

    private enum CodingKeys: String, CodingKey { case tracks, baselines }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tracks = try c.decodeIfPresent([String: TransformTrack].self, forKey: .tracks) ?? [:]
        baselines = try c.decodeIfPresent([String: PoseQuad].self, forKey: .baselines) ?? [:]
    }
}
