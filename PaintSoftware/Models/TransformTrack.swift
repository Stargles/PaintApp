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
/// because its target has no cel to ride. There is no third notion.
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

    /// **This channel cut in two at a cel-local frame** — KEYFRAMES.md §3.1's rule for `splitCel`,
    /// verbatim: *"keys before the cut go left, keys after go right, and a key is inserted at the cut
    /// in both so the value is continuous across it."*
    ///
    /// `cut` is the first cel-local frame of the **right** half, so the left half spans `0..<cut` and
    /// a key of the right half at original frame `f` lands at `f - cut`.
    ///
    /// **The inserted key is the pose this track already shows at `cut`**, which is what makes the
    /// rule's *"so the value is continuous"* true rather than approximate. It is also why the left
    /// half keeps a key one frame past its own last frame: without it, the left half's frames from its
    /// last real key onward would hold that key's pose flat (`AnimationCurve`'s decision 2 reaching
    /// here through `timing`) instead of continuing to travel, and the artist would watch a moving
    /// drawing stop dead at the cut. §3.1's own resize rule — *"a key pushed outside the new span is
    /// held, not deleted, so shrinking and re-growing a cel is lossless"* — is the precedent for
    /// storing it there.
    ///
    /// **What is lost is stated rather than hidden.** A segment that spans the cut is re-parameterised
    /// on both sides: `[k₀, cut]` and `[cut, k₁]` each become a segment of their own, so the easing
    /// *within* that one span is not the easing it had. Every other frame's pose is unchanged, which is
    /// the strongest statement §3.1's rule admits — a single bezier cannot be two beziers.
    ///
    /// **A key that already sits exactly on the cut is carried across whole, not re-synthesised.** Its
    /// pose is what `pose(atCelLocalFrame: cut)` would answer anyway, but its handles and tangent mode
    /// are not recoverable from a pose, and a split is not an occasion to flatten an authored ease.
    ///
    /// Empty halves are never returned: an empty track cannot exist in `Cel.transformTracks`
    /// (`clearPoseKeys` removes a channel left with no keys), and a track with keys yields a key at the
    /// cut on both sides whatever the keys are. `step` rides unchanged onto both, which does re-phase
    /// the right half — its frame 0 is the original `cut` and §2.10 anchors a step at frame 0 of the
    /// track's own base. Rescaling it instead would retime the animation, which is the thing §3.1
    /// refuses for the resize handles and refuses here for the same reason.
    func split(atCelLocalFrame cut: Int) -> (left: TransformTrack, right: TransformTrack) {
        guard let atCut = pose(atCelLocalFrame: cut) else { return (self, self) }
        let onCut = key(atFrame: cut)
        // **The inserted key inherits the interpolation of the segment it lands in**, which matters on
        // the right half and only there: a key's `interpolation` describes the segment it *begins*, so
        // the right half's first segment would otherwise be `.bezier` — `Key`'s default — whatever the
        // artist authored. A `.constant` hold cut in two would start easing, and a `.linear` span
        // would gain a curve at the join.
        let segment = keys.last { $0.frame <= cut }?.interpolation ?? .bezier
        var left = TransformTrack(keys: keys.filter { $0.frame <= cut }, step: step)
        if onCut == nil { left.setKey(Key(frame: cut, pose: atCut, interpolation: segment)) }
        var right = TransformTrack(keys: keys.filter { $0.frame >= cut }.map {
            var moved = $0
            moved.frame -= cut
            return moved
        }, step: step)
        if onCut == nil { right.setKey(Key(frame: 0, pose: atCut, interpolation: segment)) }
        return (left, right)
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

    /// The affine a renderer maps ink through at a cel-local frame, or nil when this channel shows
    /// the drawing where it rests.
    ///
    /// **Nil for a resting pose is load-bearing rather than an optimisation.** It is what decides
    /// whether the cel has a derivation at that frame at all, and a derivation costs a canvas-sized
    /// render and a second entry in two caches (§4.5). A track whose keys all hold the rest pose —
    /// which is exactly what §2.27's seeding writes before the artist has moved anything — must
    /// therefore cost the document nothing.
    func mapping(atCelLocalFrame frame: Int) -> CGAffineTransform? {
        guard let pose = pose(atCelLocalFrame: frame), !pose.isIdentity,
              let transform = pose.affineOrLinearised, !transform.isIdentity
        else { return nil }
        return transform
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

/// **What `<celID>_anim.json` holds** — KEYFRAMES.md §3.5's track sidecar, named from
/// `CelManifest.animationFileName`.
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
