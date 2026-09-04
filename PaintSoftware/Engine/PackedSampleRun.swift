import CoreGraphics
import Foundation

// MARK: - Persisted sample coordinates (TODO item (8))

extension CodingUserInfoKey {
    /// The point stored samples are quantised about — see `PackedSampleRun`. Set on the `JSONEncoder`
    /// that writes a payload containing strokes; absent means the origin is the canvas origin, which
    /// is correct but wastes half the field (see `PackedSampleRun.init(_:about:)`).
    static let sampleQuantisationOrigin = CodingUserInfoKey(rawValue: "PaintSoftware.sampleQuantisationOrigin")!
}

/// A run of stroke samples as bytes — TODO item (8)'s compaction, and BRUSH.md §5.1's record.
///
/// ## The record is a channel set
///
/// A run begins with **one byte naming which channels it carries** (`SampleChannelSet`) and derives
/// `bytesPerSample` from that. A stroke that was never given a channel simply has the bit clear and
/// pays nothing for it — **no format version, no migration, no decode default** (BRUSH.md §5.5), and
/// adding the next channel is a case in `SampleChannel` and two arms in `StrokeSamples`, not a
/// second layout to keep alive beside this one.
///
/// The same byte carries `preciseCoordinates`, which used to be a `Precision` enum of its own:
/// widening x and y from `Int16` quarter-pixel to `Float32` is a channel-width choice wearing a
/// different hat, so it is a bit in the same header and `bytesPerSample` is one derivation rather
/// than two hand-written arms.
///
/// ## Quarter-pixel coordinates
///
/// x and y are `Int16` in quarter-pixel steps relative to `origin` — the owner's *"last two bits for
/// quarter pixel res"*, and it is `BrushStamper`'s sub-pixel dab placement that needs it.
///
/// **The quantisation happens once, not once a save.** MEASURED: 5,000 samples through a hundred
/// consecutive saves of an untouched project drift **0.0 pt**, and through six canvas-padding changes
/// — each of which moves every sample and re-encodes about a new centre — also **0.0 pt**. The
/// padding case is exact rather than lucky: `setCanvasPadding` grows the canvas by `2·delta` and
/// moves the content by `delta`, so the centre moves by `delta` too and the stored offset is
/// unchanged.
///
/// **Clamping, not wrapping** — the owner's ruling, and a prerequisite rather than polish: BUGS.md's
/// unclamped zoom lets a real drag store a coordinate ~1.6 million points out, 200x this field's
/// range. Unclamped, `Int16` truncation would teleport that ink to the opposite side of the canvas.
/// Saturating keeps the failure local, boring and — via `clampedCount` — audible.
///
/// The bounds are derived from `Int16` rather than restated, so **-8192.0 … +8191.75** is a
/// consequence of the field width in one place and not a number to keep in sync.
/// `CanvasGeometryLogicTests` guards the canvas half of the same discipline.
///
/// ## What it costs on the wire
///
/// MEASURED (scratch `swiftc -O`, 2026-08-27, 1,000 samples, `.sortedKeys`, compiled standalone,
/// against the five-byte record this stage widened): **7.10 bytes a sample on the wire** in
/// quarter-pixel mode — 5.00 of payload, 1.67 of base64 expansion, and the rest `JSONEncoder`
/// escaping base64's `/` as `\/`. **`Float32` coordinates are 12.18**, 9.00 of it payload: **1.72x**
/// the packed form, which is the number the Move bar's help line rounds to 1.7 and the price the
/// owner accepted for item (14). Against the **~77 bytes a sample** TODO.md measures in the owner's
/// own `Untitled.paintproj` that is **~11x**. The ratio is a property of the *coordinates*, not of
/// this code: it is however many digits `Double`'s shortest round-trip spelling needs, so the same
/// probe over shorter decimals measured 60.5 and 8.6x. The packed form is smaller at every length,
/// including a one-sample stroke (31 bytes against 69) — a flat `[Double]` was also measured, at
/// 56.3, and is not worth having. BRUSH.md §5.1's channels move the payload term and leave the
/// base64 and escaping ratios exactly where they are.
///
/// A base64url alphabet would recover the ~0.33 bytes lost to escaping and is deliberately not used:
/// it would cost `Data(base64Encoded:)`'s free validation on the decode side, and a non-standard
/// alphabet in a file somebody may one day read by hand is a poor trade for 4%.
///
/// **The origin is written into the payload, and that is the load-bearing decision here.** The
/// owner's ruling puts it at the centre of the *current* canvas, which is what buys the sign bit for
/// free and makes a 16383-point canvas addressable (`CanvasManager.maxCanvasExtent`). But an origin
/// that is *implied* by the reader's canvas size is an origin a caller can get wrong, and getting it
/// wrong shifts every coordinate in the file by half a canvas — silently, and reading as success,
/// which is this codebase's most expensive recurring bug. Writing it costs ~24 bytes a stroke against
/// the ~380 a stroke this saves, and in exchange **a payload cannot be decoded wrong**: `init(from:)`
/// needs no context at all. It also means a canvas resize is free to leave old cels alone.
///
/// ## `preciseCoordinates`
///
/// `Float32` x and y, and no clamp at all. TODO item (14): the quantisation grid is a fixed size in
/// canvas points, so a stroke the artist shrank before a save has fewer usable bits and comes back
/// coarse when they grow it again. MEASURED (200 samples about (1024, 512), worst sample, shrink
/// about the origin → store → regrow): quarter-pixel costs **0.33 pt at 50%, 1.75 pt at 10% and 8.57
/// pt at 2%**; `Float32` costs **3.3e-5, 3.9e-5 and 5.0e-5 pt** for the same three. The loss is one
/// per store, multiplied by any later scale-up, and it only shows after a reopen — rotation and
/// translation are already exact in both.
///
/// **It does not clamp, and that is a behavioural difference rather than a detail.** `Float32`
/// reaches ~3.4e38, so no coordinate a canvas can hold saturates and `clampedCount` is always 0 in
/// that mode. A precise stroke therefore *cannot* be flattened onto the storage boundary by BUGS.md's
/// unclamped zoom — where the quarter-pixel form saturates at ±8192 and says so, this one stores the
/// 1.6-million-point coordinate and hands it back. That is the intended trade: the artist asked for
/// their geometry kept exactly, and "exactly" includes geometry that is nowhere near the canvas.
struct PackedSampleRun {

    /// The coordinate step, in quarter-pixel mode. `preciseCoordinates` has no grid.
    static let quantum: CGFloat = 0.25
    /// What a coordinate may be, relative to `origin`, before it saturates — **in quarter-pixel
    /// mode**. `preciseCoordinates` has no such bound, which is exactly what it is for.
    static let representable: ClosedRange<CGFloat> =
        (CGFloat(Int16.min) * quantum)...(CGFloat(Int16.max) * quantum)

    /// The point coordinates are measured from, itself snapped to the quarter-pixel grid so that
    /// `decode` then `encode` lands on the same bytes exactly rather than nearly (see `samples`).
    let origin: CGPoint
    /// Which channels this run carries, plus `preciseCoordinates`. **One byte per run**, written as
    /// the first byte of the encoded blob so the run is self-describing.
    let channels: SampleChannelSet
    /// `channels.bytesPerSample` per sample, little-endian, **without** the header byte — `encode`
    /// prepends it and `init(from:)` strips it, so nothing in memory has to reason about an offset.
    let bytes: Data
    /// How many samples saturated on the way in. Zero for anything decoded — it describes *this
    /// quantisation*, not the document, which is why it is not part of the encoded form — and always
    /// zero under `preciseCoordinates`, which cannot saturate. The one caller that has somewhere to
    /// say it is `VectorStroke.encode(to:)`.
    let clampedCount: Int
    /// How many samples arrived with a coordinate that was not a number and were written at the
    /// origin instead. **Counted in both layouts, unlike `clampedCount`**, and that asymmetry is the
    /// point: a saturating coordinate is ink the storage range could not hold, which `Float32` does
    /// not have, but a NaN is a defect upstream in either mode and going quiet about it on precisely
    /// the strokes the artist asked to keep exactly would be the worst place in this file to be
    /// quiet. Like `clampedCount` it describes *this* packing and is not part of the encoded form.
    let nonFiniteCount: Int

    /// Whether x and y were stored at full precision — `VectorStroke.precise`, read back off the
    /// header rather than stored twice.
    var isPrecise: Bool { channels.contains(.preciseCoordinates) }

    /// Pack `samples` about `rawOrigin`.
    ///
    /// `rawOrigin` is snapped to the quarter-pixel grid first. That is not tidiness: it is what makes
    /// the format an exact fixed point. A decoded coordinate is `i * quantum + origin`; re-encoding it
    /// computes `((i * quantum + origin) - origin) / quantum`, and with both terms exact multiples of
    /// `quantum` and bounded by ~16k the subtraction is exact in `Double`, so `i` comes back
    /// bit-identical. An unsnapped origin would leave that one rounding away from stable.
    ///
    /// The snap costs `preciseCoordinates` nothing — it moves the origin by at most an eighth of a
    /// point and the offset absorbs it — and it keeps one origin convention across both layouts,
    /// which is what lets the bake re-quantise a precise run about the same point the encoder would
    /// have used.
    ///
    /// **Channels are written in `SampleChannel.allCases` order, one byte each, after the
    /// coordinates.** The order is the enum's rather than the set's iteration order, because a
    /// `Set`'s is not a promise and a record's is.
    init(_ samples: StrokeSamples, about rawOrigin: CGPoint, precise: Bool = false) {
        let origin = CGPoint(x: PackedSampleRun.snapped(rawOrigin.x),
                             y: PackedSampleRun.snapped(rawOrigin.y))
        var set = samples.channels
        if precise { set.insert(.preciseCoordinates) }
        let stored = set.channels
        var bytes = Data()
        bytes.reserveCapacity(samples.count * set.bytesPerSample)
        var clamped = 0
        var nonFinite = 0
        for index in samples.indices {
            let position = samples.positions[index]
            if !position.x.isFinite || !position.y.isFinite { nonFinite += 1 }
            if precise {
                PackedSampleRun.appendFloat(position.x - origin.x, to: &bytes)
                PackedSampleRun.appendFloat(position.y - origin.y, to: &bytes)
            } else {
                let (x, xClamped) = PackedSampleRun.quantise(position.x - origin.x)
                let (y, yClamped) = PackedSampleRun.quantise(position.y - origin.y)
                if xClamped || yClamped { clamped += 1 }
                let ux = UInt16(bitPattern: x), uy = UInt16(bitPattern: y)
                bytes.append(UInt8(truncatingIfNeeded: ux))
                bytes.append(UInt8(truncatingIfNeeded: ux >> 8))
                bytes.append(UInt8(truncatingIfNeeded: uy))
                bytes.append(UInt8(truncatingIfNeeded: uy >> 8))
            }
            for channel in stored { bytes.append(channel.quantised(samples.value(channel, at: index))) }
        }
        self.origin = origin
        self.channels = set
        self.bytes = bytes
        self.clampedCount = clamped
        self.nonFiniteCount = nonFinite
    }

    /// The samples this run holds, back in canvas points and as the struct-of-arrays the rest of the
    /// engine speaks. A channel the header does not name is not built at all — no array, no bytes,
    /// and `StrokeSamples.value` answers its neutral.
    var samples: StrokeSamples {
        let stride = channels.bytesPerSample
        let count = stride > 0 ? bytes.count / stride : 0
        let stored = channels.channels
        let precise = channels.contains(.preciseCoordinates)
        let coordinateBytes = precise ? MemoryLayout<Float32>.size * 2 : MemoryLayout<Int16>.size * 2
        var positions: [CGPoint] = []
        positions.reserveCapacity(count)
        var values = [[CGFloat]](repeating: [], count: stored.count)
        for i in values.indices { values[i].reserveCapacity(count) }
        bytes.withUnsafeBytes { raw in
            var i = 0
            while i + stride <= raw.count {
                let dx: CGFloat, dy: CGFloat
                if precise {
                    dx = CGFloat(PackedSampleRun.float(from: raw, at: i))
                    dy = CGFloat(PackedSampleRun.float(from: raw, at: i + MemoryLayout<Float32>.size))
                } else {
                    let x = Int16(bitPattern: UInt16(raw[i]) | (UInt16(raw[i + 1]) << 8))
                    let y = Int16(bitPattern: UInt16(raw[i + 2]) | (UInt16(raw[i + 3]) << 8))
                    dx = CGFloat(x) * PackedSampleRun.quantum
                    dy = CGFloat(y) * PackedSampleRun.quantum
                }
                positions.append(CGPoint(x: dx + origin.x, y: dy + origin.y))
                for (slot, channel) in stored.enumerated() {
                    values[slot].append(channel.value(of: raw[i + coordinateBytes + slot]))
                }
                i += stride
            }
        }
        var result = StrokeSamples(points: positions)
        for (slot, channel) in stored.enumerated() { result.setChannel(channel, to: values[slot]) }
        return result
    }

    /// `value` narrowed to `Float32` and appended little-endian. A non-finite coordinate is a defect
    /// upstream and lands at the origin, exactly as `quantise` puts it there. It is not counted as
    /// *clamped* — `clampedCount` means "ink flattened onto the storage boundary" and this layout has
    /// no boundary — but it is counted, in `nonFiniteCount`, which the caller logs separately for
    /// exactly that reason.
    private static func appendFloat(_ value: CGFloat, to bytes: inout Data) {
        let narrowed = value.isFinite ? Float32(value) : 0
        withUnsafeBytes(of: narrowed.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
    }

    private static func float(from raw: UnsafeRawBufferPointer, at index: Int) -> Float32 {
        var pattern: UInt32 = 0
        for byte in 0..<MemoryLayout<Float32>.size {
            pattern |= UInt32(raw[index + byte]) << (8 * byte)
        }
        return Float32(bitPattern: UInt32(littleEndian: pattern))
    }

    private static func snapped(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return (value / quantum).rounded() * quantum
    }

    /// `delta` in quarter-pixel steps, saturating rather than wrapping, and saying which it did.
    /// A non-finite coordinate is a defect upstream; it lands at the origin and is counted, because a
    /// decoder that traps on bad input is worse than one that says so.
    private static func quantise(_ delta: CGFloat) -> (Int16, Bool) {
        let steps = (delta / quantum).rounded()
        guard steps.isFinite else { return (0, true) }
        if steps >= CGFloat(Int16.max) { return (Int16.max, steps > CGFloat(Int16.max)) }
        if steps <= CGFloat(Int16.min) { return (Int16.min, steps < CGFloat(Int16.min)) }
        return (Int16(steps), false)
    }

    /// The decoding half, for a blob that already has its header stripped.
    private init(origin: CGPoint, channels: SampleChannelSet, bytes: Data) {
        self.origin = origin
        self.channels = channels
        self.bytes = bytes
        self.clampedCount = 0
        self.nonFiniteCount = 0
    }
}

/// Two keys, always: `o` is the quantisation origin as `[x, y]` in canvas points, and `d` is the
/// base64 of **the channel-set byte followed by the samples**. Short because this is the compaction
/// feature and the tax is per stroke; `o` is spelled out as plain numbers rather than folded into the
/// blob because it is the one field that decides whether every coordinate in the blob is right, and
/// it should be readable by eye.
///
/// **The header is inside the blob rather than a key of its own**, which is what makes "one byte per
/// run" (BRUSH.md §5.5) literally true — a JSON key costs six characters before its value — and what
/// makes a run self-describing: the bytes and the layout they are in cannot be separated.
///
/// **Every malformed shape throws, none traps** — the argument `Lattice`'s persistence extension
/// makes, and the reason `VectorCanvasData`'s per-element decode can classify a damaged file at all.
/// The blob's length is checked against *the declared set's* record width, so a precise blob
/// truncated to a quarter-pixel multiple is still caught.
extension PackedSampleRun: Codable {

    private enum CodingKeys: String, CodingKey { case o, d }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let o = try c.decode([Double].self, forKey: .o)
        guard o.count == 2 else {
            throw DecodingError.dataCorruptedError(forKey: .o, in: c,
                debugDescription: "a quantisation origin is two numbers, got \(o.count)")
        }
        let encoded = try c.decode(String.self, forKey: .d)
        guard let blob = Data(base64Encoded: encoded) else {
            throw DecodingError.dataCorruptedError(forKey: .d, in: c,
                debugDescription: "sample run is not base64")
        }
        guard let header = blob.first else {
            throw DecodingError.dataCorruptedError(forKey: .d, in: c,
                debugDescription: "sample run carries no channel-set byte")
        }
        let channels = SampleChannelSet(rawValue: header)
        guard channels.isSubset(of: .known) else {
            throw DecodingError.dataCorruptedError(forKey: .d, in: c,
                debugDescription: "sample run channel set \(header) names a channel this build does not have")
        }
        let payload = Data(blob.dropFirst())
        guard payload.count % channels.bytesPerSample == 0 else {
            throw DecodingError.dataCorruptedError(forKey: .d, in: c,
                debugDescription: "sample run is \(payload.count) bytes, not a multiple of \(channels.bytesPerSample)")
        }
        self.init(origin: CGPoint(x: o[0], y: o[1]), channels: channels, bytes: payload)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode([Double(origin.x), Double(origin.y)], forKey: .o)
        var blob = Data([channels.rawValue])
        blob.append(bytes)
        try c.encode(blob.base64EncodedString(), forKey: .d)
    }
}

extension VectorSample {

    /// `samples` packed about whatever origin `encoder` was given. **No origin means the canvas
    /// origin**, which encodes correctly for any canvas up to half the field and is what every test
    /// that round-trips a stroke through a bare `JSONEncoder()` gets. It is a smaller addressable
    /// range, never a wrong coordinate: the origin used is written into the payload either way.
    ///
    /// `precise` is the *only* channel by which item (14)'s mode reaches the file. There is no
    /// separate persisted key for it: the run's own header says which layout it is in, and a stroke
    /// derives its flag back from that on decode. Storing it twice would be storing a copy that can
    /// go stale, which is the argument `Lattice`'s persistence doc makes about derivable data.
    static func packed(_ samples: StrokeSamples, for encoder: Encoder,
                       precise: Bool = false) -> PackedSampleRun {
        PackedSampleRun(samples, about: encoder.userInfo[.sampleQuantisationOrigin] as? CGPoint ?? .zero,
                        precise: precise)
    }

    /// The samples at `key`, **and whether they were stored at full precision** — the derivation that
    /// keeps `VectorStroke.precise` off the wire.
    static func decodeRun<K: CodingKey>(from container: KeyedDecodingContainer<K>,
                                        forKey key: K) throws -> (samples: StrokeSamples, precise: Bool) {
        let run = try container.decode(PackedSampleRun.self, forKey: key)
        return (run.samples, run.isPrecise)
    }
}
