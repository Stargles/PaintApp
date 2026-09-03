import CoreGraphics
import Foundation

// MARK: - Exact arithmetic on a source clock
//
// `SourceTime` is a normalised rational (`Engine/VectorLayer.swift`) and deliberately not `CMTime`,
// so the comparisons and differences VIDEO.md §4.3's map needs live here rather than in the model —
// the model file has no business importing CoreMedia and the map has no business rounding through
// `Double` when it does not have to.

extension SourceTime: Comparable {

    /// Cross-multiplied rather than compared through `seconds`, so two instants a `Double` cannot
    /// tell apart are still ordered correctly. **Agrees with the synthesized `==`** because both
    /// operands are normalised at construction: `2/4` and `1/2` are one value with one spelling.
    ///
    /// The products are `Int64` and cannot overflow at any duration this app can hold — an hour at
    /// a 90 kHz clock is `3.24e8`, and the other factor is a timescale — but the overflow-reporting
    /// multiply is used anyway, falling back to `seconds`, because the alternative to a fallback is
    /// a trap on a file somebody handed us.
    static func < (lhs: SourceTime, rhs: SourceTime) -> Bool {
        let left = lhs.value.multipliedReportingOverflow(by: Int64(rhs.timescale))
        let right = rhs.value.multipliedReportingOverflow(by: Int64(lhs.timescale))
        guard !left.overflow, !right.overflow else { return lhs.seconds < rhs.seconds }
        return left.partialValue < right.partialValue
    }

    /// `self - other`, in seconds. Lossy on purpose and only used where a *length* is wanted — the
    /// block length in §4.3's inverse — never to derive an instant that is stored back.
    func secondsSince(_ other: SourceTime) -> Double { seconds - other.seconds }

    /// The instant clamped into `low...high`, or `low` when the pair is inverted (a crop whose end
    /// precedes its start is a damaged element, and holding its first frame is the visible answer).
    func clamped(from low: SourceTime, to high: SourceTime) -> SourceTime {
        guard low < high else { return low }
        if self < low { return low }
        if high < self { return high }
        return self
    }
}

// MARK: - VIDEO.md §4.3, the frame map

/// **The one function that turns a document frame into an instant on a video's own clock**, and its
/// inverse. VIDEO.md §4.3:
///
/// ```
/// documentFrame → sourceTime = sourceStart + (documentFrame − cel.startFrame) · speed / documentFPS
///                → nearest source frame at that time
/// ```
///
/// Everything §2.3 and §2.5 rule lives in here and nowhere else.
///
/// **§2.3's resampling *is* "nearest source frame at that time"** — there is no second mechanism for
/// it. A 30 fps clip in a 24 fps document is asked for the instant 1/24 s later on each document
/// frame and answers with whichever source frame is nearest, so it lasts the same number of seconds
/// it always did and shows 30 of its frames for every 24 the document draws. **§2.3's frame-for-frame
/// arm is `speed = sourceFPS / documentFPS`**, which is why it is a setting of Adjust Speed rather
/// than a mode of its own: the two are one control and one of them has a name.
///
/// **Pure, and every member is a free function over values** — no asset, no decoder, no document. It
/// is arithmetic, so it is tested as arithmetic.
enum VideoFrameMap {

    // MARK: Document frame → source time

    /// §4.3's forward map, **unclamped**: where on the source's clock the artist is looking.
    ///
    /// ## The working timescale, and why the speed-1 case is exact
    ///
    /// The offset is `elapsed · speed / documentFPS` seconds, and this returns a rational, so it
    /// needs a denominator that divides both terms: a multiple of `sourceStart.timescale`, so the
    /// start converts by an integer multiply, and of `documentFPS`, so one document frame is a whole
    /// number of ticks. Their **lowest common multiple** is the smallest such denominator and is
    /// what the map builds on. So at `speed == 1` — every import, and every clip nobody has
    /// retimed — the map is exact and there is nothing to round; a fractional speed rounds *once per
    /// frame* against the formula rather than accumulating, so a clip an hour long is no less
    /// accurate at its end than at its start. That is `VideoFrameWriter`'s `CMTime(value: index,
    /// timescale: fps)` property reached from the other direction.
    ///
    /// **The lcm alone is not fine enough, and that is not obvious until it bites.** `SourceTime`
    /// *normalises*, so a crop that starts at the head of the clip has timescale **1** — and the lcm
    /// is then just `documentFPS`, i.e. one tick per document frame, i.e. every fractional speed
    /// quantised to a whole document frame. §2.3's own frame-for-frame setting is exactly such a
    /// speed, and at that resolution it lands on `0, 1, 3, 3, 4, 5, 6, 8, 8, …` — repeating and
    /// skipping source frames, which is the opposite of what it is named for. So the lcm is scaled
    /// up by a thousand where that fits, which both makes the tick a microsecond or so **and** keeps
    /// every decimal speed an artist can type (0.5, 0.8, 1.25, 2) exact.
    ///
    /// The `Double` branch is unreachable from any asset — it needs an lcm above two billion — and
    /// exists because the alternative to a defined answer is an overflow trap on a number that
    /// arrived in a file.
    static func unclampedSourceTime(sourceStart: SourceTime,
                                    elapsedDocumentFrames elapsed: Int,
                                    speed: Double,
                                    documentFPS: Int) -> SourceTime {
        let fps = max(documentFPS, 1)
        let base = lcm(Int64(sourceStart.timescale), Int64(fps))
        guard base > 0, base <= Int64(Int32.max) else {
            let seconds = sourceStart.seconds + Double(elapsed) * speed / Double(fps)
            return SourceTime(value: Int64((seconds * 90_000).rounded()), timescale: 90_000)
        }
        var working = base
        for multiplier in [Int64(1000), 100, 10] where base * multiplier <= Int64(Int32.max) {
            working = base * multiplier
            break
        }
        let startTicks = sourceStart.value * (working / Int64(sourceStart.timescale))
        let offsetTicks = Int64((Double(elapsed) * speed * Double(working) / Double(fps)).rounded())
        return SourceTime(value: startTicks + offsetTicks, timescale: Int32(working))
    }

    /// Lowest common multiple, over magnitudes so nothing traps. Zero in, zero out.
    private static func lcm(_ a: Int64, _ b: Int64) -> Int64 {
        guard a > 0, b > 0 else { return 0 }
        var x = a, y = b
        while y != 0 { (x, y) = (y, x % y) }
        let (product, overflow) = (a / x).multipliedReportingOverflow(by: b)
        return overflow ? 0 : product
    }

    /// §4.3's forward map for one element, **clamped into its own crop**.
    ///
    /// The clamp is what a block longer than its footage shows: the last frame of the crop, held.
    /// That state is reachable (a right-edge drag outward past the end, §2.4's "up to the full
    /// duration", and a speed change that shortens the footage before §2.5 has rewritten the block)
    /// and holding is the only answer that is not a blank frame in the middle of a shot.
    static func sourceTime(of element: VectorVideoElement,
                           atDocumentFrame frame: Int,
                           celStartFrame: Int,
                           documentFPS: Int) -> SourceTime {
        let raw = unclampedSourceTime(sourceStart: element.sourceStart,
                                      elapsedDocumentFrames: frame - celStartFrame,
                                      speed: element.speed,
                                      documentFPS: documentFPS)
        return raw.clamped(from: element.sourceStart, to: element.sourceEnd)
    }

    // MARK: Source time → source frame

    /// **"Nearest source frame at that time"**, given the source's own nominal rate.
    ///
    /// This is the naming half of §4.3 rather than the decoding half: `VideoFrameReader` picks the
    /// frame nearest an instant by the *presentation timestamps the file actually carries*, which is
    /// right for variable-rate footage where a nominal rate is a lie. The two agree on everything
    /// constant-rate, and this one exists so a test can say *which* frame a document frame asks for
    /// without opening a decoder.
    ///
    /// Clamped at zero, and 0 for a rate that is not a rate.
    static func sourceFrameIndex(at time: SourceTime, sourceFPS: Double) -> Int {
        guard sourceFPS > 0 else { return 0 }
        return max(0, Int((time.seconds * sourceFPS).rounded()))
    }

    /// **§2.3's frame-for-frame setting**, as the speed it is: every source frame shown, one per
    /// document frame.
    ///
    /// **`documentFPS / sourceFPS`, and VIDEO.md §4.3 has this the other way up.** That line says
    /// *"§2.3's frame-for-frame arm is `speed = sourceFPS / documentFPS`"*, and its own formula on
    /// the line above refutes it: `sourceTime = … + elapsed · speed / documentFPS`, so one document
    /// frame advances the source by `speed / documentFPS` seconds, and showing exactly one source
    /// frame per document frame means that quantity is `1 / sourceFPS`. Hence `speed = documentFPS /
    /// sourceFPS`. **§4.3's own inverse corroborates it**: the block length is `(sourceEnd −
    /// sourceStart) / speed · documentFPS`, which at this value is `span · sourceFPS` — the number of
    /// source frames, exactly as frame-for-frame should give — where the inverted value produces
    /// `span · documentFPS² / sourceFPS`, a number with no meaning.
    ///
    /// Concretely: 30 fps footage in a 24 fps document plays frame-for-frame at **0.8**, i.e. slowed
    /// down, taking 30 document frames rather than 24 — which is what "every source frame shown"
    /// costs and is the reason §2.3 makes real-time the default and this the setting.
    static func frameForFrameSpeed(sourceFPS: Double, documentFPS: Int) -> Double {
        guard sourceFPS > 0 else { return 1 }
        return Double(max(documentFPS, 1)) / sourceFPS
    }

    // MARK: The inverse — §2.5

    /// **§4.3's inverse: how long the block is.** `(sourceEnd − sourceStart) / speed · documentFPS`.
    ///
    /// This is what Adjust Speed writes into `Cel.frameCount` (§2.5, stage 6) and what an import
    /// would want if §2.4 did not clip it to the scene first. At least one frame, because a cel of
    /// no frames is not a cel; rounded rather than truncated, so a clip that is 2.5 document frames
    /// long occupies 3 and shows its tail rather than losing it.
    static func frameCount(sourceStart: SourceTime, sourceEnd: SourceTime,
                           speed: Double, documentFPS: Int) -> Int {
        let span = sourceEnd.secondsSince(sourceStart)
        guard span > 0, speed > 0 else { return 1 }
        return max(1, Int((span / speed * Double(max(documentFPS, 1))).rounded()))
    }

    /// The same, read off an element.
    static func frameCount(of element: VectorVideoElement, documentFPS: Int) -> Int {
        frameCount(sourceStart: element.sourceStart, sourceEnd: element.sourceEnd,
                   speed: element.speed, documentFPS: documentFPS)
    }
}

// MARK: - What a video cel shows, as a value

/// **Which instant of which asset one video element shows at one document frame** — the product of
/// the map above, and the component VIDEO.md §5 says `FrameBakeKey` is owed.
///
/// The asset is named by its **file name inside the package** rather than by `assetURL`, for the
/// reason `VectorVideoElement` gives about that field: the package moves, so an absolute path is
/// only true of the load that produced it, and a bake key built from one would miss on every reopen
/// for pixels that have not changed.
struct VideoCut: Hashable {
    let assetFileName: String
    let value: Int64
    let timescale: Int32

    init(assetFileName: String, at time: SourceTime) {
        self.assetFileName = assetFileName
        value = time.value
        timescale = time.timescale
    }

    var sourceTime: SourceTime { SourceTime(value: value, timescale: timescale) }
}

/// The identity of one **video** frame — `DerivedCelContent.identity` for a cel holding a video, and
/// the first type in this app to conform to `BakeKeyEncodable`.
///
/// ## Why this is not `PosedCelIdentity` with a field bolted on
///
/// It carries every field that one does, because a video cel can be posed like any other, plus
/// `cuts`. It is a separate type because `AnyHashable` compares unequal across types, so a posed cel
/// and a posed cel holding a video can never collide on one cache entry however similar their other
/// fields look — the same argument `PosedCelIdentity` and `InterpolatedCelIdentity` already make
/// against each other.
///
/// ## `cuts` is the component, and it is the one no compiler protects
///
/// `FrameBakeKey`'s header gives three rules, and rule 1 — no `default:` anywhere — turns a new enum
/// *case* into a compile error. **A new stored property is not a compile error anywhere**, which is
/// exactly the shape of this field: without it every document frame of a video block encodes
/// identically, the store resolves the whole block to one file, and the first frame's picture is
/// served for all of them with no error at any level. `LayerContentVersion.pose` is the same trap
/// found from the keyframe door; this is it found from the video door.
///
/// **A video is also the first content in this document that varies across the frames one cel
/// spans**, so it is the first thing to put a frame-varying component into a key RENDER.md §3.3
/// deliberately leaves `frame` out of. It does so through the *derivation's* identity rather than by
/// adding `frame` to the key, which is what keeps every ordinary hold at one file on disk.
struct VideoCelIdentity: Hashable, BakeKeyEncodable {
    let celID: UUID
    let canvas: ObjectIdentifier
    let vectorVersion: Int
    let suppressed: [String]
    let carried: [CGFloat]
    let maps: [String: [CGFloat]]
    let inherited: [CGFloat]?
    /// One per video element the cel draws, **sorted by element id** so the display list's order
    /// cannot reach the digest through the back door of an unordered walk.
    let cuts: [String: VideoCut]
    let canvasWidth: Int
    let canvasHeight: Int

    /// **Field by field, with a tag per boundary** — `FrameBakeKey`'s rules 2 and 3 applied to a
    /// type that file cannot switch over. Conforming is what takes this identity off
    /// `BakeKeyEncoder.derived`'s reflective fallback, which walks `String(reflecting:)` and prints
    /// a dictionary in per-process hash order.
    func encodeForBakeKey(into e: inout BakeKeyEncoder) {
        e.uuid(celID)
        e.objectID(canvas)
        e.int(vectorVersion)
        e.array(suppressed) { e, id in e.string(id) }
        e.array(carried) { e, value in e.cgFloat(value) }
        e.array(maps.keys.sorted()) { e, key in
            e.string(key)
            e.array(maps[key] ?? []) { e, value in e.cgFloat(value) }
        }
        e.optional(inherited) { e, values in e.array(values) { e, value in e.cgFloat(value) } }
        // **The component.** Delete these four lines and every frame of a video block is one digest;
        // `VideoFrameMapLogicTests.testTwoFramesOfOneVideoBlockAreTwoDigests` is the pin, and its
        // twin next door proves an ordinary hold is still one file.
        e.array(cuts.keys.sorted()) { e, id in
            e.string(id)
            guard let cut = cuts[id] else { return e.tag(0) }
            e.tag(1)
            e.string(cut.assetFileName)
            e.u64(UInt64(bitPattern: cut.value))
            e.u32(UInt32(bitPattern: cut.timescale))
        }
        e.int(canvasWidth)
        e.int(canvasHeight)
    }
}
