import CoreGraphics
import Foundation

// MARK: - Exact arithmetic on a source clock
//
// `SourceTime` is a normalised rational (`Engine/VectorLayer.swift`) and deliberately not `CMTime`,
// so the comparisons and differences VIDEO.md §4.3's map needs live here rather than in the model —
// the model file has no business importing CoreMedia and the map has no business rounding through
// `Double` when it does not have to.

extension SourceTime: Comparable {

    /// Int64 numerators times Int32 denominators fit Int128 exactly, including negative clocks.
    static func < (lhs: SourceTime, rhs: SourceTime) -> Bool {
        Int128(lhs.value) * Int128(rhs.timescale) < Int128(rhs.value) * Int128(lhs.timescale)
    }

    /// Subtract on the source clock before converting the length to seconds. Converting each
    /// absolute timestamp first would erase short crops near an extreme numerator.
    func secondsSince(_ other: SourceTime) -> Double {
        let numerator = Int128(value) * Int128(other.timescale)
            - Int128(other.value) * Int128(timescale)
        return Double(numerator) / Double(Int64(timescale) * Int64(other.timescale))
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
/// arm is a *speed*** — `documentFPS / sourceFPS`, see `frameForFrameSpeed`, where VIDEO.md's own
/// formula is corrected — which is why it is a setting of Adjust Speed rather than a mode of its
/// own: the two are one control and one of them has a name.
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
    /// Advance on the existing working clock. Crop/asset bounds are compared before narrowing
    /// the result, so an extreme finite offset can still resolve to its exact held endpoint.
    static func advancedSourceTime(sourceStart: SourceTime,
                                   elapsedDocumentFrames elapsed: Int,
                                   speed: Double, documentFPS: Int,
                                   minimum: SourceTime? = nil, maximum: SourceTime? = nil) -> SourceTime? {
        advancedSourceTime(sourceStart: sourceStart, elapsed: Int128(elapsed), speed: speed,
                           fps: documentFPS, minimum: minimum, maximum: maximum)
    }

    /// Nil start is the existing90kHz fallback when the LCM cannot be a SourceTime timescale.
    private static func clock(sourceStart: SourceTime, fps: Int) -> (start: Int128?, scale: Int32) {
        let sourceScale = Int128(sourceStart.timescale), rate = Int128(fps)
        let base = sourceScale / Int128(SourceTime.gcd(UInt128(sourceScale), UInt128(rate))) * rate
        guard base <= Int128(Int32.max) else { return (nil, 90_000) }
        var working = base
        for multiplier in [Int128(1000), 100, 10] where base * multiplier <= Int128(Int32.max) {
            working = base * multiplier
            break
        }
        return (Int128(sourceStart.value) * (working / sourceScale), Int32(working))
    }

    private static func rawTicks(sourceStart: SourceTime, elapsed: Int128, speed: Double, fps: Int,
                                 clock: (start: Int128?, scale: Int32)) -> Int128? {
        if let start = clock.start {
            // Preserve the fractional-speed evaluation order and once-per-frame rounding.
            guard let offset = Int128(exactly:
                (Double(elapsed) * speed * Double(clock.scale) / Double(fps)).rounded()) else { return nil }
            let sum = start.addingReportingOverflow(offset)
            return sum.overflow ? nil : sum.partialValue
        }
        let seconds = sourceStart.seconds + Double(elapsed) * speed / Double(fps)
        return Int128(exactly: (seconds * 90_000).rounded())
    }

    private static func precedes(_ ticks: Int128, scale: Int32, _ time: SourceTime) -> Bool {
        let left = ticks.multipliedReportingOverflow(by: Int128(time.timescale))
        // The other product is at most95 bits; an overflowing left product is beyond it by sign.
        if left.overflow { return ticks < 0 }
        return left.partialValue < Int128(time.value) * Int128(scale)
    }

    private static func advancedSourceTime(sourceStart: SourceTime, elapsed: Int128,
                                           speed: Double, fps: Int,
                                           minimum: SourceTime?, maximum: SourceTime?) -> SourceTime? {
        guard speed.isFinite, speed > 0, fps > 0 else { return nil }
        let clock = clock(sourceStart: sourceStart, fps: fps)
        guard let ticks = rawTicks(sourceStart: sourceStart, elapsed: elapsed, speed: speed, fps: fps, clock: clock) else {
            // An offset beyond Int128 cannot be cancelled by the at-most95-bit start. Its sign
            // proves the endpoint without storing a fabricated instant or saturated frame count.
            if elapsed > 0, let maximum { return maximum }
            if elapsed < 0, let minimum { return minimum }
            return nil
        }
        if let minimum, precedes(ticks, scale: clock.scale, minimum) { return minimum }
        if let maximum, !precedes(ticks, scale: clock.scale, maximum) { return maximum }
        let divisor = Int128(SourceTime.gcd(ticks.magnitude, UInt128(clock.scale)))
        guard let value = Int64(exactly: ticks / divisor),
              let scale = Int32(exactly: Int128(clock.scale) / divisor) else {
            // The exact origin remains representable even when the fallback's expanded ticks do not.
            return elapsed == 0 ? sourceStart : nil
        }
        return SourceTime(value: value, timescale: scale)
    }

    enum CodingError: Error { case unrepresentableTiming }

    /// Admit the existing nontrapping working-clock domain, plus offsets proved to be held at an
    /// endpoint. Generic element-loss decoding must not turn this current-data failure into no video.
    static func validate(sourceStart: SourceTime, sourceEnd: SourceTime,
                         speed: Double, documentFPS fps: Int) throws {
        guard frameCount(sourceStart: sourceStart, sourceEnd: sourceEnd,
                         speed: speed, documentFPS: fps) != nil else { throw CodingError.unrepresentableTiming }
        guard sourceStart < sourceEnd else { return }
        let clock = clock(sourceStart: sourceStart, fps: fps)
        if let first = rawTicks(sourceStart: sourceStart, elapsed: 1, speed: speed, fps: fps, clock: clock) {
            if !precedes(first, scale: clock.scale, sourceEnd) { return }
        } else {
            return // Every positive frame is beyond the crop; the exact endpoint is held.
        }
        // Every rounded working-clock tick strictly inside the crop must fit. This admits the
        // original nontrapping clock domain without scanning a possibly enormous frame sequence.
        func floor(_ numerator: Int128, _ denominator: Int128) -> Int128 {
            numerator / denominator - (numerator % denominator < 0 ? 1 : 0)
        }
        func ceil(_ numerator: Int128, _ denominator: Int128) -> Int128 {
            numerator / denominator + (numerator % denominator > 0 ? 1 : 0)
        }
        let firstInterior = floor(Int128(sourceStart.value) * Int128(clock.scale), Int128(sourceStart.timescale)) + 1
        let lastInterior = ceil(Int128(sourceEnd.value) * Int128(clock.scale), Int128(sourceEnd.timescale)) - 1
        if firstInterior > lastInterior { return }
        guard Int64(exactly: firstInterior) != nil, Int64(exactly: lastInterior) != nil else {
            throw CodingError.unrepresentableTiming
        }
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
        guard element.sourceStart < element.sourceEnd else { return element.sourceStart }
        guard let time = advancedSourceTime(sourceStart: element.sourceStart,
            elapsed: Int128(frame) - Int128(celStartFrame), speed: element.speed, fps: documentFPS,
            minimum: element.sourceStart, maximum: element.sourceEnd) else {
            preconditionFailure("Video timing must be admitted before rendering")
        }
        return time
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
    static func sourceFrameIndex(at time: SourceTime, sourceFPS: Double) -> Int? {
        guard sourceFPS.isFinite, sourceFPS > 0 else { return 0 }
        let value = (time.seconds * sourceFPS).rounded()
        if value <= 0 { return 0 }
        return Int(exactly: value)
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
                           speed: Double, documentFPS: Int, limit: Int? = nil) -> Int? {
        guard speed.isFinite, speed > 0, documentFPS > 0 else { return nil }
        let span = sourceEnd.secondsSince(sourceStart)
        guard span > 0 else { return 1 }
        let value = (span / speed * Double(documentFPS)).rounded()
        if let limit, value >= Double(max(limit, 1)) { return max(limit, 1) }
        if value < 1 { return 1 }
        return Int(exactly: value)
    }

    /// The same, read off an element.
    static func frameCount(of element: VectorVideoElement, documentFPS: Int) -> Int? {
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

/// **One video element's crop and speed, as a value** — the three fields VIDEO.md §2.2 and §2.5
/// write, snapshotted so a structure undo can put them back.
///
/// It exists because `CanvasManager.StructureSnapshot` copies `[Layer]` **by value** and `Cel.vector`
/// is a **class** reference, so a snapshot shares the live `VectorCanvas` and restoring it restores
/// a cel's `startFrame` and `frameCount` while leaving whatever the drag wrote inside that canvas
/// exactly where it was. Every other structural verb is safe from that because none of them mutates
/// a vector canvas in place — `splitCel` mints copies — and the crop is the first that does.
/// `Equatable` and not `Hashable`, because `SourceTime` is only the former: nothing keys a
/// dictionary on a crop, and conforming `SourceTime` to buy that would be a conformance with no
/// caller.
struct VideoCrop: Equatable {
    let start: SourceTime
    let end: SourceTime
    let speed: Double

    init(of element: VectorVideoElement) {
        start = element.sourceStart
        end = element.sourceEnd
        speed = element.speed
    }
}

/// Which end of the crop a block-edge drag holds still — VIDEO.md §2.2, *"adjusting the length of
/// the block from both ends will have the effect of cropping the video"*.
///
/// **Each arm anchors on the field its own verb never writes**, and that is what makes the crop
/// drift-free without a baseline. `resizeCelRightEdge` keeps `startFrame` fixed, so the head of the
/// crop cannot move and `sourceEnd` is a pure function of the block's new length;
/// `resizeCelLeftEdge` keeps `endFrame` fixed, so the tail cannot move and `sourceStart` is. Both
/// recompute from scratch on every `.changed` of a drag, so an out-and-back gesture lands exactly
/// where it began — which is the same drift those two verbs already solve for *neighbours* with
/// `gestureSnapshot`, solved here by arithmetic instead because the snapshot shares this canvas.
enum VideoCropAnchor {
    /// The head is fixed and the tail follows the block — a right-edge drag.
    case head
    /// The tail is fixed and the head follows the block — a left-edge drag, which crops the head.
    case tail
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
    let canvas: UUID
    let vectorVersion: Int
    let suppressed: [String]
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
        e.uuid(canvas)
        e.int(vectorVersion)
        e.array(suppressed) { e, id in e.string(id) }
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
