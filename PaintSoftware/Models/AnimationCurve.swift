import Foundation

/// The value curve behind one keyframed channel — KEYFRAMES.md §3.2, build-order stage 1.
///
/// An ordered list of keys, each carrying its own value, two bezier handles and a tangent mode, plus
/// a per-segment interpolation carried on the key that *begins* the segment (Blender's storage, and
/// what lets one hold sit between two eases), plus a `step` (§2.10) that holds the evaluated result
/// for a run of frames so ink on twos and a camera move on twos agree.
///
/// **This is deliberately not `SpacingCurve`, and `SpacingCurve` must not be widened into it.** That
/// one is a *time remap*: `eased(t)` returns a new `t` fed to lattice deformation, its input is
/// clamped to 0…1 (`InterpolationRecipe.swift`), monotonicity is enforced in two separate places on
/// purpose (`GuidePath.swift`) because a dipping curve runs an in-between backwards mid-scrub, and
/// both ends are pinned. A value channel wants none of those, and the last one is fatal: overshoot is
/// the entire reason a bezier graph editor exists, and reusing `SpacingCurve` excludes it structurally.
///
/// **Nor is it `MonotoneCubic` (`Effect.swift`).** That interpolant *derives* its tangents from secant
/// averages and then applies the Fritsch–Carlson limiter specifically to prevent overshoot — the exact
/// opposite of an authored-handle graph curve. It is the right tool for a tone curve and the wrong one
/// here. Only `.autoClamped` below is in that family, and it is one mode among five rather than the
/// only behaviour available.
///
/// ## The four decisions, made explicitly because each has a way of being decided by accident
///
/// 1. **The output is never clamped to any range.** Not to 0…1, not to the endpoints of a segment, not
///    to anything. An opacity channel that reads this curve is responsible for its own clamp at the
///    point of use. Overshoot is the feature — a value that swings past its target and settles back is
///    what makes a move read as weight rather than as a lerp — and a clamp here would remove it from
///    every channel at once with no way to opt back in. Pinned by
///    `testAFreeHandleOvershootIsNotClampedAway`.
///
/// 2. **Extrapolation before the first key and after the last is a constant hold.** Decided here on
///    its own merits, not inherited because the neighbouring interpolant does the same thing.
///    `MonotoneCubic.value(at:)` also holds flat outside its span — deliberately, in two documented
///    guards (`Effect.swift`), not by accident — but it holds flat for a *tone* curve, whose domain is
///    the 0…1 the artist can actually reach, and `CurveEditor` pins its endpoint x-coordinates to 0
///    and 1 so nothing is ever evaluated outside it. Neither of those is true of a channel, which is
///    asked for a value at every frame of a cel or a document whether a key is near it or not.
///    Here it is the rule in its own right: outside `keys.first!.frame ... keys.last!.frame` the curve is the
///    nearest key's value, exactly. Linear extrapolation was rejected because a channel is asked for
///    values across the whole cel or document span, and a tangent extended for two hundred frames
///    produces an opacity of -14 with nothing on screen to explain it. It is also why `.auto` and
///    `.autoClamped` give a flat handle at the first and last key: the curve then leaves and enters the
///    held region without a corner.
///
/// 3. **A bezier segment is always a function of time.** Handles are authored in (frame, value) space
///    and nothing stops the artist dragging one so far along the frame axis that the curve folds back
///    and one frame carries two values. The handles' **frame** components are therefore clamped into
///    the segment at evaluation — `outHandle` to `0...h` and `inHandle` to `-h...0`, where `h` is the
///    segment's length in frames. This is exactly the constraint CSS `cubic-bezier` puts on its x
///    coordinates, and it is sufficient rather than merely conservative: with both normalised x
///    controls in 0…1, the x-component's derivative is a quadratic Bézier with non-negative endpoint
///    coefficients that cannot dip below zero on 0…1, so x is non-decreasing and the inverse is
///    single-valued. The **value** components are not touched — that is decision 1.
///
///    The clamp is applied on the way *out*, at evaluation, not on the way *in*. The stored handle
///    keeps what the artist drew, so a graph editor can draw the handle where the finger left it while
///    the curve stays sane; `effectiveHandles(at:)` is what the editor should draw the *curve* from.
///
/// 4. **At most one key per frame; among keys sharing a frame the later one in the array wins.** The
///    document timeline is integer frames, so `CurveEditor`'s 0.001 epsilon has no analogue here — two
///    keys are either on the same frame or they are not. Normalisation happens at exactly two places,
///    `init(keys:step:)` and `init(from:)`, and `setKey(_:)` *replaces* rather than appends so the
///    invariant cannot be broken after construction. The sort is stable by original array index, which
///    is what makes "the later one" well defined; note that `MonotoneCubic`'s identical-sounding rule
///    leans on `Array.sorted` being stable, which Swift does not guarantee.
///
///    A zero-length segment is the thing this rule exists to prevent: it divides by zero in the bezier
///    parameterisation and has no defensible value at its own frame.
struct AnimationCurve: Codable, Equatable {

    // MARK: - Pieces

    /// How the segment *beginning* at a key is interpolated. Carried on the earlier key, which is what
    /// lets a hold sit between two eases without a second per-segment table to keep in step.
    enum Interpolation: String, Codable {
        /// Hold: the segment is the start key's value throughout, and steps at the next key.
        case constant
        case linear
        case bezier
    }

    /// Where a key's two handles come from. `.autoClamped` is the default for the reason it is
    /// Blender's: it is what stops a value that must not overshoot — an opacity, an intensity, a
    /// blur radius — from overshooting between two keys, without the artist having to notice.
    enum TangentMode: String, Codable {
        /// A smooth tangent through the key, taken from the secant between its two neighbours. Free to
        /// overshoot, which is sometimes exactly right and sometimes an opacity of 1.15.
        case auto
        /// `.auto`, with each handle's tip value clamped into the closed interval between this key's
        /// value and that neighbour's. See `effectiveHandles(at:)` for why that one clamp is enough to
        /// make the whole segment stay inside its endpoints.
        case autoClamped
        /// Handles point a third of the way at the adjacent keys, which makes the join read as a
        /// corner and the segments either side read as straight.
        case vector
        /// The two handles share one direction; each keeps its own length. Enforced here rather than
        /// only in the editor, so stored data cannot claim `.aligned` and evaluate as something else.
        case aligned
        /// Both handles exactly as authored.
        case free
    }

    /// One handle, as an offset from its key in (frame, value) space. `outHandle` points forward in
    /// time so its `deltaFrames` is normally positive; `inHandle` points backward so its is normally
    /// negative. Both are stored unclamped — see decision 3.
    struct Handle: Codable, Equatable {
        var deltaFrames: Double
        var deltaValue: Double

        init(deltaFrames: Double = 0, deltaValue: Double = 0) {
            self.deltaFrames = deltaFrames
            self.deltaValue = deltaValue
        }

        static let zero = Handle()

        var length: Double { (deltaFrames * deltaFrames + deltaValue * deltaValue).squareRoot() }

        /// The unit vector along this handle, or nil when it has no length to take a direction from.
        ///
        /// Frames and values are different units, so this direction is only meaningful in the curve's
        /// own space. That is inherent to a graph editor rather than a flaw in this type — Blender's
        /// aligned handles have the same property — but it does mean `.aligned` behaves differently
        /// for a channel whose values run 0…1 than for one whose values run 0…500.
        var unit: Handle? {
            let m = length
            guard m > 0 else { return nil }
            return Handle(deltaFrames: deltaFrames / m, deltaValue: deltaValue / m)
        }

        var negated: Handle { Handle(deltaFrames: -deltaFrames, deltaValue: -deltaValue) }
    }

    struct Key: Codable, Equatable {
        /// Integer, because every timeline in the document is. The *curve* is continuous; the keys are
        /// not, and there is nothing an artist can do in the timeline to land one between two frames.
        var frame: Int
        var value: Double
        var inHandle: Handle
        var outHandle: Handle
        var tangentMode: TangentMode
        /// The segment that *begins* here. Ignored on the last key, which begins nothing.
        var interpolation: Interpolation

        init(frame: Int,
             value: Double,
             inHandle: Handle = .zero,
             outHandle: Handle = .zero,
             tangentMode: TangentMode = .autoClamped,
             interpolation: Interpolation = .bezier) {
            self.frame = frame
            self.value = value
            self.inHandle = inHandle
            self.outHandle = outHandle
            self.tangentMode = tangentMode
            self.interpolation = interpolation
        }

        // Field-presence versioning, the idiom every persisted field in this tree follows: a file
        // written before a field existed decodes to the default rather than failing.
        private enum CodingKeys: String, CodingKey {
            case frame, value, inHandle, outHandle, tangentMode, interpolation
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            frame = try c.decode(Int.self, forKey: .frame)
            value = try c.decode(Double.self, forKey: .value)
            inHandle = try c.decodeIfPresent(Handle.self, forKey: .inHandle) ?? .zero
            outHandle = try c.decodeIfPresent(Handle.self, forKey: .outHandle) ?? .zero
            tangentMode = try c.decodeIfPresent(TangentMode.self, forKey: .tangentMode) ?? .autoClamped
            interpolation = try c.decodeIfPresent(Interpolation.self, forKey: .interpolation) ?? .bezier
        }
    }

    // MARK: - State

    /// Sorted by frame, one key per frame. `private(set)` because that invariant is decision 4 and
    /// `setKey(_:)` / `removeKey(atFrame:)` are the only things that may touch it.
    private(set) var keys: [Key]

    /// Evaluate, then hold the result for this many frames — 1 is every frame, 2 is on twos (§2.10).
    ///
    /// The run is anchored at frame **0 of this curve's own time base**, not at the first key.
    /// Anchoring at the first key would mean two channels both set to twos step on opposite frames
    /// whenever their first keys differ in parity, which is the one thing "on twos" is supposed to
    /// prevent. Values below 1 are treated as 1.
    var step: Int

    var isEmpty: Bool { keys.isEmpty }

    init(keys: [Key] = [], step: Int = 1) {
        self.keys = Self.normalised(keys)
        self.step = step
    }

    // MARK: - Editing

    /// Inserts `key`, or replaces the one already on its frame. Never produces a duplicate frame.
    mutating func setKey(_ key: Key) {
        if let i = keys.firstIndex(where: { $0.frame == key.frame }) {
            keys[i] = key
        } else if let i = keys.firstIndex(where: { $0.frame > key.frame }) {
            keys.insert(key, at: i)
        } else {
            keys.append(key)
        }
    }

    mutating func removeKey(atFrame frame: Int) {
        keys.removeAll { $0.frame == frame }
    }

    func key(atFrame frame: Int) -> Key? { keys.first { $0.frame == frame } }

    /// Decision 4, applied at the two places a `keys` array can enter the type.
    private static func normalised(_ input: [Key]) -> [Key] {
        guard input.count > 1 else { return input }
        // Stable by original index, so "the later one wins" means the later one in the caller's array
        // rather than whatever an unstable sort happened to leave last.
        let sorted = input.enumerated()
            .sorted { $0.element.frame == $1.element.frame ? $0.offset < $1.offset : $0.element.frame < $1.element.frame }
            .map(\.element)
        var out: [Key] = []
        out.reserveCapacity(sorted.count)
        for key in sorted {
            if out.last?.frame == key.frame { out[out.count - 1] = key } else { out.append(key) }
        }
        return out
    }

    // MARK: - Evaluation

    /// The curve at `time`, in this curve's own frame base — cel-local for an object channel, absolute
    /// document frames for a layer channel (§3.1).
    ///
    /// **`time` is a `Double` even though every timeline in the document is integer-only today.** The
    /// playhead truncates to `Int` at `activeCelIndex(inLayer:atFrame:)` and everywhere downstream, so
    /// every caller this feature ships with will hand over a whole number. A curve is continuous
    /// regardless, and the graph editor of §2.17 scrubs *along the curve* rather than along the frame
    /// ruler, so it will want the value at 7.4. Taking `Int` now would make that a signature change to
    /// a method with a call site per channel per frame.
    ///
    /// An empty curve returns 0. There is no better total answer, and it is why `isEmpty` is public: a
    /// channel with no keys is not animated at all, and the caller is meant to use its static value
    /// rather than this.
    func evaluate(at time: Double) -> Double {
        guard let first = keys.first, let last = keys.last else { return 0 }

        let t = stepped(time)

        // Decision 2: constant on both sides. Also the whole of the single-key case.
        if t <= Double(first.frame) { return first.value }
        if t >= Double(last.frame) { return last.value }

        var lo = 0, hi = keys.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if Double(keys[mid].frame) <= t { lo = mid } else { hi = mid }
        }
        return value(inSegmentStartingAt: lo, at: t)
    }

    /// `time` quantised onto this curve's step. Identity when `step <= 1` — which matters: rounding
    /// down at step 1 would silently truncate the sub-frame time the signature exists to accept.
    func stepped(_ time: Double) -> Double {
        guard step > 1 else { return time }
        let s = Double(step)
        return (time / s).rounded(.down) * s
    }

    private func value(inSegmentStartingAt i: Int, at t: Double) -> Double {
        let a = keys[i], b = keys[i + 1]
        let h = Double(b.frame - a.frame)
        guard h > 0 else { return b.value }        // unreachable while decision 4 holds

        switch a.interpolation {
        case .constant:
            return a.value
        case .linear:
            return a.value + (b.value - a.value) * ((t - Double(a.frame)) / h)
        case .bezier:
            let out = effectiveHandles(at: i).outHandle
            let into = effectiveHandles(at: i + 1).inHandle

            // Decision 3: the frame components are clamped into the segment, the value components are
            // not. `x1` and `x2` are those clamps expressed in the unit square.
            let x1 = min(max(out.deltaFrames / h, 0), 1)
            let x2 = min(max(1 + into.deltaFrames / h, 0), 1)
            let u = min(max((t - Double(a.frame)) / h, 0), 1)
            let s = Self.bezierParameter(forX: u, x1: x1, x2: x2)

            return Self.cubic(s, a.value, a.value + out.deltaValue, b.value + into.deltaValue, b.value)
        }
    }

    // MARK: - Handles

    /// The handles the curve is actually drawn from at `index`.
    ///
    /// For `.auto`, `.autoClamped` and `.vector` the stored handles are ignored entirely — those modes
    /// *derive* their handles from the neighbouring keys, and deriving on read rather than writing
    /// them back means they cannot go stale when a neighbour moves. `.aligned` reads the stored
    /// lengths but imposes a shared direction. Only `.free` returns what is stored.
    ///
    /// **Why `.autoClamped`'s one clamp is enough.** Clamping each handle tip into the interval between
    /// its own key's value and the adjacent key's value puts all four of a segment's value control
    /// points inside `min(a, b) ... max(a, b)`; a cubic Bézier is a convex combination of its control
    /// points, so the whole segment is inside that interval too. There is no second limiter and no
    /// special case for a local extremum — at an extremum both neighbours sit on the same side, the
    /// tip clamps back onto the key's own value, and the handle comes out flat by itself.
    func effectiveHandles(at index: Int) -> (inHandle: Handle, outHandle: Handle) {
        let key = keys[index]
        let prev = index > 0 ? keys[index - 1] : nil
        let next = index < keys.count - 1 ? keys[index + 1] : nil

        switch key.tangentMode {
        case .free:
            return (key.inHandle, key.outHandle)

        case .aligned:
            return Self.aligned(key)

        case .vector:
            let out = next.map { Handle(deltaFrames: Double($0.frame - key.frame) / 3,
                                        deltaValue: ($0.value - key.value) / 3) } ?? .zero
            let into = prev.map { Handle(deltaFrames: -Double(key.frame - $0.frame) / 3,
                                         deltaValue: -(key.value - $0.value) / 3) } ?? .zero
            return (into, out)

        case .auto, .autoClamped:
            // Flat at the ends, which is decision 2's other half: the curve then meets the held region
            // without a corner.
            var slope = 0.0
            if let p = prev, let n = next, n.frame != p.frame {
                slope = (n.value - p.value) / Double(n.frame - p.frame)
            }
            var out = Handle(deltaFrames: next.map { Double($0.frame - key.frame) / 3 } ?? 0)
            out.deltaValue = slope * out.deltaFrames
            var into = Handle(deltaFrames: prev.map { -Double(key.frame - $0.frame) / 3 } ?? 0)
            into.deltaValue = slope * into.deltaFrames

            if key.tangentMode == .autoClamped {
                if let n = next { out.deltaValue = Self.clampedTip(key.value, out.deltaValue, toward: n.value) }
                if let p = prev { into.deltaValue = Self.clampedTip(key.value, into.deltaValue, toward: p.value) }
            }
            return (into, out)
        }
    }

    /// `delta` shortened until `base + delta` lies between `base` and `neighbour`.
    private static func clampedTip(_ base: Double, _ delta: Double, toward neighbour: Double) -> Double {
        let lo = min(base, neighbour), hi = max(base, neighbour)
        return min(max(base + delta, lo), hi) - base
    }

    /// One direction for both handles, each keeping its own length.
    ///
    /// The shared direction is the mean of the out handle's direction and the *reverse* of the in
    /// handle's, so it is symmetric and is the identity on data that is already aligned. A degenerate
    /// pair — either handle with no length, or two exactly opposed unit vectors that cancel — has no
    /// direction to agree on, and the stored handles are returned unchanged rather than snapped to an
    /// arbitrary axis.
    private static func aligned(_ key: Key) -> (inHandle: Handle, outHandle: Handle) {
        guard let o = key.outHandle.unit, let i = key.inHandle.negated.unit else {
            return (key.inHandle, key.outHandle)
        }
        let sum = Handle(deltaFrames: o.deltaFrames + i.deltaFrames, deltaValue: o.deltaValue + i.deltaValue)
        guard let d = sum.unit else { return (key.inHandle, key.outHandle) }
        let inLength = key.inHandle.length, outLength = key.outHandle.length
        return (Handle(deltaFrames: -d.deltaFrames * inLength, deltaValue: -d.deltaValue * inLength),
                Handle(deltaFrames: d.deltaFrames * outLength, deltaValue: d.deltaValue * outLength))
    }

    // MARK: - Bezier arithmetic

    static func cubic(_ s: Double, _ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double) -> Double {
        let r = 1 - s
        return r * r * r * p0 + 3 * r * r * s * p1 + 3 * r * s * s * p2 + s * s * s * p3
    }

    /// The curve parameter at which the segment reaches normalised time `x`.
    ///
    /// Newton first because it converges in two or three steps for the handle shapes an artist
    /// actually draws, then bisection — which cannot fail, because decision 3's clamp guarantees the
    /// x-component is non-decreasing on 0…1. Not fileprivate: `AnimationCurveLogicTests` inverts it
    /// directly to assert single-valuedness, which is the property decision 3 is about.
    static func bezierParameter(forX x: Double, x1: Double, x2: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }

        var s = x
        for _ in 0..<8 {
            let error = cubic(s, 0, x1, x2, 1) - x
            if abs(error) < 1e-12 { return s }
            let r = 1 - s
            let slope = 3 * (r * r * x1 + 2 * r * s * (x2 - x1) + s * s * (1 - x2))
            if abs(slope) < 1e-9 { break }
            let next = s - error / slope
            if next < 0 || next > 1 || next.isNaN { break }
            s = next
        }

        var lo = 0.0, hi = 1.0
        s = x
        for _ in 0..<64 {
            let at = cubic(s, 0, x1, x2, 1)
            if abs(at - x) < 1e-13 { return s }
            if at < x { lo = s } else { hi = s }
            s = (lo + hi) / 2
        }
        return s
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case keys, step }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keys = Self.normalised(try c.decodeIfPresent([Key].self, forKey: .keys) ?? [])
        step = try c.decodeIfPresent(Int.self, forKey: .step) ?? 1
    }
}
