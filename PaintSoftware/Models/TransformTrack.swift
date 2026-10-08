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

/// **One pose channel: where a drawing is, over the frames its cel spans** — one `AnimationCurve`
/// per component, each keyed independently of the others. TODO (139), the owner: *"The X and Y and
/// rotation etc components keys should be fully independent from each other."*
///
/// ## A key is a value on one component, and nothing else
///
/// Until TODO (139) a pose key was a whole `PoseQuad` — every component at once, on one shared timing
/// spine with one shared handle pair — so a sideways drag keyed the rotation too, a node dragged in
/// the graph editor dragged all six of its rows, and a Distort could not be drawn as curves at all.
/// Now each of `PoseComponents.Component`'s eight is an ordinary `AnimationCurve`, which is what the
/// grade's sliders have always been: crop, split, step, the graph band's gestures and its whole-curve
/// write funnel apply to a pose through the same code they apply to a grade. **A component with no
/// curve is not keyed**: it shows the channel's base — rest for a cel channel, whose base is the
/// geometry itself, and the container's stored pose for a transformation layer (`LayerPose`).
///
/// ## Its time base is cel-local, and that is §3.1 rather than a convenience
///
/// Keys are numbered from the cel's own `startFrame`, so the channel rides the cel through move,
/// split, duplicate and paste for free. A *layer* channel — the container's, and every grade's — is
/// in absolute document frames because its target has no cel to ride. **And a key is never outside
/// the cel's span** (TODO 62): `cropped(toFrameCount:)` and `shifted(by:)` are what a span change
/// applies, through `Cel.cropPoseKeysToSpan`.
///
/// ## The rest box
///
/// The components are read against `box` — X and Y are where its centre is shown, the two keystones
/// are in its units — so it is stored with the curves rather than with each key. It is latched when
/// the channel is first written and never moves: the map a pose describes is the same map from any
/// box, so a later write measured against a different box is decomposed against this one
/// (`PoseComponents.decompose(_:inBox:)`) and means the same thing.
struct TransformTrack: Equatable {

    /// The box the components are read against — canvas coordinates for a cel channel, the canvas
    /// frame for a container.
    var box: CGRect

    /// One curve per keyed component. **Never holds an empty curve**: `setCurve(_:for:)` removes one,
    /// for `setEffectParameterTrack`'s reason — a curve with no keys is a channel that exists,
    /// animates nothing, and shows up in a channel list.
    private(set) var curves: [PoseComponents.Component: AnimationCurve]

    init(box: CGRect, curves: [PoseComponents.Component: AnimationCurve] = [:]) {
        self.box = box
        self.curves = curves.filter { !$0.value.isEmpty }
    }

    /// No component carries a key.
    var isEmpty: Bool { curves.isEmpty }

    /// **Whether this channel is an *animation*** — some component's curve is one by the owner's
    /// definition (`AnimationCurve.isAnimated`: two or more keys, not all holding one value). The
    /// strict predicate, which the recorder's gate asks; routing asks the loose one, whether the
    /// channel has a curve at all, for `AnimationCurve.isAnimated`'s stated reason.
    var isAnimated: Bool { curves.values.contains { $0.isAnimated } }

    /// Every frame some component holds a key on, ascending and unique — what
    /// `CanvasManager.keyframeFrames(of:)` folds into §2.28's union, converted to absolute frames by
    /// its caller because only the caller knows the cel's `startFrame`.
    var keyedFrames: [Int] { Set(curves.values.flatMap { $0.keys.map(\.frame) }).sorted() }

    /// How many keys the channel holds across its components — what an undo estimate counts.
    var keyCount: Int { curves.values.reduce(0) { $0 + $1.keys.count } }

    func curve(_ component: PoseComponents.Component) -> AnimationCurve? { curves[component] }

    /// Replaces one component's curve. **Nil or empty removes it**, so the component falls back to
    /// the channel's base.
    mutating func setCurve(_ curve: AnimationCurve?, for component: PoseComponents.Component) {
        if let curve, !curve.isEmpty { curves[component] = curve } else { curves.removeValue(forKey: component) }
    }

    /// Drops every component's key on `frame`; a component left with no keys is removed.
    mutating func removeKeys(atFrame frame: Int) {
        for (component, curve) in curves where curve.key(atFrame: frame) != nil {
            var trimmed = curve
            trimmed.removeKey(atFrame: frame)
            setCurve(trimmed, for: component)
        }
    }

    // MARK: - Writing what a gesture changed — TODO (139)

    /// **Writes `new` at `frame` on every component where it differs from `old`, and on no other** —
    /// the ruling: *"only the keys of things that changed are added"*. Returns the components written.
    ///
    /// A component that already has a curve takes a key at `frame` — the auto-key arm, one component
    /// at a time. **One that has none is seeded** (`AnimationCurve.seeded`): `old` onto the nearest
    /// keyframe below and above `frame`, `new` on `frame`, so the frames either side keep showing the
    /// value they showed. That is what a whole-pose key did for that component implicitly — every
    /// earlier key carried it — and what *"if you prime this in two frames and then change something,
    /// then it should put down two keys like the behaviour today, but only the things that changed"*
    /// asks for on the primed pair.
    ///
    /// `new` is unwrapped onto `old`'s turn first, so a drawing turned through ±180° is keyed the
    /// short way round rather than spun back.
    ///
    /// - Parameter keyframes: the target's keyframes in this track's own frame base, ascending —
    ///   restricted by the caller to the frames a key of this channel may sit on (a cel's span).
    @discardableResult
    mutating func key(_ new: PoseComponents.Values, over old: PoseComponents.Values,
                      atFrame frame: Int, keyframes: [Int]) -> [PoseComponents.Component] {
        let new = new.unwrappingRotation(near: old.rotation)
        let changed = old.components(differingFrom: new)
        for component in changed {
            if var curve = curves[component] {
                curve.setKey(AnimationCurve.Key(frame: frame, value: new[component]))
                curves[component] = curve
            } else {
                curves[component] = AnimationCurve.seeded(nil, keyframes: keyframes, frame: frame,
                                                          oldValue: old[component],
                                                          newValue: new[component])
            }
        }
        return changed
    }

    /// **Every keyed component takes a key on `frame` holding the value it shows there** —
    /// `addKeyframe`'s step 3, §2.24's surviving half: placing a mark must not let an animated
    /// component drift straight through it. A component with no curve takes nothing — it shows the
    /// base at every frame, and a key would only pin what is already there.
    mutating func holdKeys(atFrame frame: Int) {
        for (component, curve) in curves {
            var held = curve
            held.setKey(AnimationCurve.Key(frame: frame, value: curve.evaluate(at: Double(frame))))
            curves[component] = held
        }
    }

    // MARK: - Riding the cel's span — KEYFRAMES.md §3.1 and TODO (62)

    /// **This channel cut in two at a cel-local frame** — `AnimationCurve.split(atFrame:)` per
    /// component, which carries §3.1's rule and its costs. The box rides onto both halves.
    func split(atCelLocalFrame cut: Int) -> (left: TransformTrack, right: TransformTrack) {
        var left = TransformTrack(box: box)
        var right = TransformTrack(box: box)
        for (component, curve) in curves {
            let halves = curve.split(atFrame: cut)
            left.setCurve(halves.left, for: component)
            right.setCurve(halves.right, for: component)
        }
        return (left, right)
    }

    /// Every component's keys moved by `delta` cel-local frames — what a left-edge resize does
    /// before cropping (`AnimationCurve.shifted(by:)`).
    func shifted(by delta: Int) -> TransformTrack {
        guard delta != 0 else { return self }
        return TransformTrack(box: box, curves: curves.mapValues { $0.shifted(by: delta) })
    }

    /// **Every component cropped to `0..<frameCount`, and the frames each one lost** —
    /// `AnimationCurve.cropped(toFrameCount:)` per component, edge keys and all.
    func cropped(toFrameCount frameCount: Int)
        -> (kept: TransformTrack, discarded: [PoseComponents.Component: [Int]]) {
        var kept = TransformTrack(box: box)
        var discarded: [PoseComponents.Component: [Int]] = [:]
        for (component, curve) in curves {
            let result = curve.cropped(toFrameCount: frameCount)
            kept.setCurve(result.kept, for: component)
            if !result.discarded.isEmpty { discarded[component] = result.discarded }
        }
        return (kept, discarded)
    }

    /// **Every component cropped to a transformation layer's blocks** —
    /// `AnimationCurve.croppedToBlocks(_:insertBelow:insertAbove:)` per component, for a container's
    /// own channel, which keys in absolute document frames.
    func croppedToBlocks(_ coverage: [Range<Int>], insertBelow: Int? = nil, insertAbove: Int? = nil)
        -> (kept: TransformTrack, discarded: [PoseComponents.Component: [Int]]) {
        var kept = TransformTrack(box: box)
        var discarded: [PoseComponents.Component: [Int]] = [:]
        for (component, curve) in curves {
            let result = curve.croppedToBlocks(coverage, insertBelow: insertBelow, insertAbove: insertAbove)
            kept.setCurve(result.kept, for: component)
            if !result.discarded.isEmpty { discarded[component] = result.discarded }
        }
        return (kept, discarded)
    }

    // MARK: - Evaluation

    /// The values a resting pose holds against this channel's box — a cel channel's base, since its
    /// stored base is the geometry itself (`CanvasManager.CelPoseState`).
    var restValues: PoseComponents.Values { .resting(in: box) }

    /// **The eight values this channel shows at `time`** — each keyed component evaluated
    /// (`AnimationCurve.evaluate(at:)`, step and constant hold included), every other one `base`'s.
    func values(atTime time: Double, base: PoseComponents.Values) -> PoseComponents.Values {
        var values = base
        for (component, curve) in curves { values[component] = curve.evaluate(at: time) }
        return values
    }

    /// **The map a renderer carries ink through at a cel-local frame, or nil when this channel shows
    /// the drawing where it rests.**
    ///
    /// **Nil for a resting pose is load-bearing rather than an optimisation.** It is what decides
    /// whether the cel has a derivation at that frame at all, and a derivation costs a canvas-sized
    /// render and a second entry in two caches (§4.5). A channel whose keys all hold rest values —
    /// which is exactly what a seed writes before the artist has moved anything — must therefore cost
    /// the document nothing. "Rest" is `Values.isResting(in:)`: the same per-component tolerance that
    /// decides what a commit keys, so there is one threshold and not two.
    func mapping(atCelLocalFrame frame: Int) -> PoseMap? {
        guard !curves.isEmpty else { return nil }
        let values = values(atTime: Double(frame), base: restValues)
        guard !values.isResting(in: box), let map = PoseComponents.map(values, box: box), !map.isIdentity
        else { return nil }
        return map
    }
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
/// A key at cel-local 9 on a block starting at frame 20 is "the key at 29" to them, and that is what
/// the sentence says.
struct KeyframeCrop: Equatable {

    /// Channel id → the absolute frames of the keys removed, ascending. **A pose component is a
    /// channel of its own** (`"cel.x"`, `"transform.rotation"`), since TODO (139) made each one an
    /// independent curve: a crop that took X and Y at one frame took two keys.
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

    /// Records what one pose channel's crop discarded, one channel per component.
    mutating func record(poseChannel id: String, discarded: [PoseComponents.Component: [Int]],
                         offsetBy offset: Int = 0) {
        for (component, frames) in discarded {
            record(channel: id + "." + component.rawValue, frames: frames.map { $0 + offset })
        }
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
    /// with no keys is removed rather than stored empty: an empty `TransformTrack` in the dictionary
    /// is a channel that animates nothing and still routes a Move as though it did.
    ///
    /// **`pendingPoseBaselines` is left alone.** A held pose is not a key and has no frame — it is
    /// §2.27's *"the previous value is held"*, waiting for the next Add Keys to commit it — so there
    /// is nothing about it that can be outside a span.
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
            crop.record(poseChannel: id, discarded: discarded, offsetBy: startFrame)
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
/// layer and §4.4.
///
/// ## What it is, and what it is not
///
/// §2.3: *"A transformation layer re-poses the vector objects below it, rather than resampling the
/// composited pixels below it. The owner wants crisp lines, not a bitmap magnify."* So this is not a
/// blend mode and cannot be — §4.4 says all 25 modes are per-channel colour functions over two
/// same-size, same-position images, with no positional argument anywhere in either backend. It is
/// applied where the ink is **stamped**, not where the pixels are composited.
///
/// **Its one home is `Layer.transform`**, the transformation *layer*, which poses everything beneath
/// it inside its own container. A folder held a twin of it (§2.21's argument, applied to the pose)
/// until TODO (71), when the owner asked for a folder's Move to be the Move tool over its contents
/// rather than a container behaviour; a transformation layer at the top of a folder is that twin
/// now.
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

    /// The channel's curves, in **absolute document frames** (§3.1). Empty on a container the artist
    /// has posed but not animated. **A component it does not key shows `pose`'s value for that
    /// component** — so turning a container whose X is animated leaves X on its curve and the turn in
    /// the base, exactly as a grade's unkeyed parameter shows the stored effect.
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

    /// - Parameter track: the channel's curves; an empty one on `pose`'s own box when omitted.
    init(pose: PoseQuad, track: TransformTrack? = nil, baseline: PoseQuad? = nil,
         mode: TransformLayerMode = .move, shakeSeed: UInt64 = 0, shakePeriod: Int = 1,
         repeatPeriod: Int = 0) {
        self.pose = pose
        self.track = track ?? TransformTrack(box: pose.box)
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

    /// §2.26's stricter predicate, for the channel list: some component is an animation.
    var isAnimated: Bool { track.isAnimated }

    /// **The stored base, as the eight values the track's unkeyed components show** — read against
    /// the track's box, which a container shares with its base.
    var baseValues: PoseComponents.Values {
        PoseComponents.decompose(pose, inBox: track.box) ?? track.restValues
    }

    /// The eight values the container shows at one document frame — each keyed component's curve,
    /// every other component the base's.
    func resolvedValues(atFrame frame: Int) -> PoseComponents.Values {
        track.values(atTime: Double(frame), base: baseValues)
    }

    /// The pose at one document frame — **the stored base itself when nothing is keyed**, and
    /// otherwise the keyed components over the base's. The same precedence
    /// `Layer.layerEffect(atFrame:)` has, one component at a time.
    func resolvedPose(atFrame frame: Int) -> PoseQuad {
        guard !track.isEmpty else { return pose }
        return PoseComponents.recompose(resolvedValues(atFrame: frame), box: track.box) ?? pose
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
        guard !track.isEmpty else {
            guard !pose.isIdentity, let map = pose.map, !map.isIdentity else { return nil }
            return map
        }
        let values = resolvedValues(atFrame: frame)
        guard !values.isResting(in: track.box), let map = PoseComponents.map(values, box: track.box),
              !map.isIdentity else { return nil }
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
    /// **It follows `resolvedValues`' precedence component by component**, with `isResting(in:)`'s
    /// tolerance: a keyed component moves the contents when any of its keys leaves rest, an unkeyed
    /// one when the base does. The one direction it is deliberately loose in is the segment between
    /// two keys — two resting keys interpolate to rest under every tangent mode but an overshooting
    /// `.free` handle, which is exact for every curve the app writes.
    var movesItsContents: Bool {
        guard !track.isEmpty else { return !pose.isIdentity }
        let rest = track.restValues
        let base = baseValues
        func leavesRest(_ value: Double, _ component: PoseComponents.Component) -> Bool {
            abs(value - rest[component]) > component.flatTolerance
        }
        return PoseComponents.Component.allCases.contains { component in
            guard let curve = track.curve(component) else { return leavesRest(base[component], component) }
            return curve.keys.contains { leavesRest($0.value, component) }
        }
    }
}

extension LayerPose: Codable {

    private enum CodingKeys: String, CodingKey { case pose, track, baseline, mode, shakeSeed, shakePeriod, repeatPeriod }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pose = try c.decode(PoseQuad.self, forKey: .pose)
        track = try c.decodeIfPresent(TransformTrack.self, forKey: .track) ?? TransformTrack(box: pose.box)
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

/// Field-presence versioning, the idiom every persisted field in this tree follows. **The curves are
/// keyed by component name** (`PoseComponents.Component.rawValue`), so the file reads as the graph
/// editor does — one entry per curve — and a component this build does not know is ignored rather
/// than failing the document. A track written before TODO (139), which stored whole-pose keys under
/// `keys`, carries neither field and opens empty: no document so far has to survive (TODO.md's
/// standing permission), so there is no second decoder for it.
extension TransformTrack: Codable {

    private enum CodingKeys: String, CodingKey { case box, curves }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        box = try c.decodeIfPresent(CGRect.self, forKey: .box) ?? .zero
        let named = try c.decodeIfPresent([String: AnimationCurve].self, forKey: .curves) ?? [:]
        var curves: [PoseComponents.Component: AnimationCurve] = [:]
        for (name, curve) in named {
            guard let component = PoseComponents.Component(rawValue: name), !curve.isEmpty else { continue }
            curves[component] = curve
        }
        self.curves = curves
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(box, forKey: .box)
        try c.encode(Dictionary(uniqueKeysWithValues: curves.map { ($0.key.rawValue, $0.value) }),
                     forKey: .curves)
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
