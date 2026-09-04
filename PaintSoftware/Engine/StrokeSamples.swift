import CoreGraphics
import Foundation

/// One per-point channel a stroke may carry beside its positions — BRUSH.md §5.1 and §5.5.
///
/// **The record is a channel set, not a fixed struct.** A run says which of these it holds and
/// derives its width from that, so a channel a stroke was never given costs it nothing: no format
/// version, no migration, no decode default. Adding the next one is a case here, two arms in
/// `StrokeSamples`' storage subscript, and nothing else — every generic operation in this file
/// iterates `allCases` rather than naming fields.
///
/// **Every channel has a neutral**, and that is what makes the funnel (`StrokeSensors`) total: a
/// finger reports no tilt and never will, and BRUSH.md §2.10's apply-to-existing verb can point any
/// stroke at a brush reading anything. The neutral is the value at which a modulation of that
/// channel contributes nothing — the Pencil held upright, pressed full, moving not at all — so a
/// brush reading a channel the stroke does not carry renders exactly as it would with that
/// modulation removed.
///
/// **Each is one byte, and the widths are settled** (BRUSH.md §5.1). The quantisation is stated once
/// here rather than at the packer, because the neutral has to survive it exactly: `quantised` of a
/// channel's `neutral` decodes back to `neutral` bit for bit in every case, which is what lets a run
/// that stores an all-neutral channel be dropped to an absent one with no change to a single pixel.
enum SampleChannel: UInt8, CaseIterable {
    /// `0…1`, as the hardware reports it. Neutral **1** — a finger, and `StrokeInput`'s own answer
    /// for a non-Pencil touch.
    case pressure
    /// Seconds since the previous stored point. Neutral **0**; see `StrokeSensors.velocity`, which
    /// reads the channel's *presence* rather than its neutral, because a Δt of zero is not a speed.
    case deltaTime
    /// Radians, `0…π/2`: 0 is the Pencil flat against the glass, π/2 perpendicular. Neutral **π/2**
    /// — upright, which is what `StrokeInput` answers for a finger.
    case tiltAltitude
    /// Radians, `0…2π`, wrapping — the compass direction the Pencil is leaned in, **in the samples'
    /// own space** (BRUSH.md §2.7). Neutral **0**.
    case tiltAzimuth

    /// The value the funnel answers where a stroke carries no data for this channel — BRUSH.md §5.5.
    var neutral: CGFloat {
        switch self {
        case .pressure: return 1
        case .deltaTime: return 0
        case .tiltAltitude: return .pi / 2
        case .tiltAzimuth: return 0
        }
    }

    /// This channel's bit in a run header.
    var bit: SampleChannelSet {
        SampleChannelSet(rawValue: 1 << (rawValue + SampleChannelSet.channelBitShift))
    }

    /// Whether the channel is an **angle in the samples' own coordinate space**, and so turns with
    /// them under an affine rather than riding through it unchanged.
    ///
    /// This is the one place the "a channel is just carried" rule has an exception, and it is not
    /// optional: azimuth is stored in the space the samples are in (BRUSH.md §2.7), so a lasso that
    /// rotates ink by 30° has rotated the nib with it. `StrokeSamples.transformed(by:)` is the one
    /// function that applies it.
    var isAngleInSampleSpace: Bool {
        switch self {
        case .tiltAzimuth: return true
        case .pressure, .deltaTime, .tiltAltitude: return false
        }
    }

    /// Whether the channel measures an **interval between two stored points** rather than a reading
    /// at one of them.
    ///
    /// Δt is the only one, and it behaves differently everywhere a sample is derived: a reading is
    /// interpolated between its neighbours, while an interval is *divided* between them. Inserting a
    /// point a third of the way along a segment gives that point a third of the segment's time and
    /// leaves two thirds for the point after it — which is what keeps a cut piece's velocities equal
    /// to the ones the uncut stroke had at the same places. `VectorSample.absorbing` and
    /// `afterInsertedPredecessor` are the two halves of that arithmetic.
    var isCumulative: Bool {
        switch self {
        case .deltaTime: return true
        case .pressure, .tiltAltitude, .tiltAzimuth: return false
        }
    }

    /// The channel's value at a point `t` of the way from one stored point to the next.
    ///
    /// Three rules, one per kind of quantity: an **interval** gets the elapsed fraction of itself, an
    /// **angle** takes the shortest arc so a run crossing 2π→0 does not sweep the nib the long way
    /// round, and everything else is linear.
    func interpolated(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        if isCumulative { return b * t }
        guard isAngleInSampleSpace else { return a + (b - a) * t }
        var delta = (b - a).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi } else if delta < -.pi { delta += 2 * .pi }
        return a + delta * t
    }

    /// `value` turned by `rotation` if this channel is an angle, unchanged otherwise.
    func rotated(_ value: CGFloat, by rotation: CGFloat) -> CGFloat {
        isAngleInSampleSpace ? SampleChannel.wrappedAngle(value + rotation) : value
    }

    /// `angle` folded into `0..<2π`, which is the range `quantised` and `value(of:)` speak.
    static func wrappedAngle(_ angle: CGFloat) -> CGFloat {
        guard angle.isFinite else { return 0 }
        let turn = 2 * CGFloat.pi
        let folded = angle.truncatingRemainder(dividingBy: turn)
        return folded < 0 ? folded + turn : folded
    }

    /// Δt's step, in seconds. **One half-millisecond, saturating at `255 * quantum` = 127.5 ms.**
    ///
    /// Both bounds are about velocity, which is what the channel exists for (BRUSH.md §2.8), and the
    /// error that matters is *relative*, because Δt is a divisor. At the Pencil's 240 Hz a raw gap is
    /// 4.17 ms — eight steps, 6% — and after `StrokePathFit` a stored gap is typically 40-50 ms,
    /// where it is 1%. Saturation means "slower than 7.8 Hz", i.e. the fit emitted no point for an
    /// eighth of a second, at which the pen is at the bottom of any velocity curve and the exact
    /// value cannot matter.
    static let deltaTimeQuantum: CGFloat = 0.0005

    /// `value` as the byte this channel stores. Clamping, except azimuth, which **wraps** — that is
    /// what an angle does, and it makes 0 and 2π the same byte rather than two.
    func quantised(_ value: CGFloat) -> UInt8 {
        guard value.isFinite else { return quantised(neutral) }
        switch self {
        case .pressure:
            return UInt8(min(max((value * 255).rounded(), 0), 255))
        case .deltaTime:
            let steps = (value / SampleChannel.deltaTimeQuantum).rounded()
            return UInt8(min(max(steps, 0), 255))
        case .tiltAltitude:
            let steps = (value / (.pi / 2) * 255).rounded()
            return UInt8(min(max(steps, 0), 255))
        case .tiltAzimuth:
            let steps = (SampleChannel.wrappedAngle(value) / (2 * .pi) * 256).rounded()
            return UInt8(truncatingIfNeeded: Int(steps))
        }
    }

    /// The value a stored byte means.
    func value(of byte: UInt8) -> CGFloat {
        switch self {
        case .pressure: return CGFloat(byte) / 255
        case .deltaTime: return CGFloat(byte) * SampleChannel.deltaTimeQuantum
        case .tiltAltitude: return CGFloat(byte) / 255 * (.pi / 2)
        case .tiltAzimuth: return CGFloat(byte) / 256 * (2 * .pi)
        }
    }
}

/// Which channels a run carries, plus the one bit that is not a channel — BRUSH.md §5.5.
///
/// **It absorbs the old `PackedSampleRun.Precision` flag**, which was "a channel-width choice wearing
/// a different hat": `preciseCoordinates` widens x and y from `Int16` quarter-pixel to `Float32`
/// exactly as a channel bit adds a byte, and `bytesPerSample` derives the record width from the whole
/// set rather than from an enum with two hand-written arms.
struct SampleChannelSet: OptionSet, Equatable, Hashable {
    let rawValue: UInt8
    init(rawValue: UInt8) { self.rawValue = rawValue }

    /// x and y are `Float32` rather than `Int16` quarter-pixel — TODO item (14)'s
    /// `VectorStroke.precise`. Bit 0, so the channel bits start one along.
    static let preciseCoordinates = SampleChannelSet(rawValue: 1 << 0)
    /// How far up the channel bits sit. One, for `preciseCoordinates` below them.
    static let channelBitShift: UInt8 = 1

    static let pressure = SampleChannel.pressure.bit
    static let deltaTime = SampleChannel.deltaTime.bit
    static let tiltAltitude = SampleChannel.tiltAltitude.bit
    static let tiltAzimuth = SampleChannel.tiltAzimuth.bit

    /// What a bare list of points carries: position and pressure, the record as it stood before this.
    /// The set every synthetic run in the app and the tests is built with.
    static let pressureOnly: SampleChannelSet = [.pressure]

    /// What the digitiser gives, and so what a drawn stroke starts with — every channel. A stroke
    /// that turns out to carry nothing but neutrals in one of them loses it at `compacted()`, which
    /// is how a finger stroke ends up 6 bytes a point rather than 8.
    static let captured: SampleChannelSet = [.pressure, .deltaTime, .tiltAltitude, .tiltAzimuth]

    /// Every bit this build defines. A header naming anything outside it is a file written by a
    /// build that knew a channel this one does not, and the decoder refuses it rather than reading
    /// the bytes after it at the wrong stride — the malformed-input discipline `PackedSampleRun`'s
    /// coder has always had.
    static let known: SampleChannelSet =
        SampleChannel.allCases.reduce(into: SampleChannelSet.preciseCoordinates) { $0.insert($1.bit) }

    /// The channels this set names, in `SampleChannel.allCases` order — the order the packer writes
    /// them in, so the two cannot disagree about which byte is which.
    var channels: [SampleChannel] { SampleChannel.allCases.filter { contains($0.bit) } }

    func contains(_ channel: SampleChannel) -> Bool { contains(channel.bit) }

    /// The record width, derived from the set rather than restated. Four bytes of position (two
    /// `Int16`) or eight (two `Float32`), plus one per channel.
    var bytesPerSample: Int {
        (contains(.preciseCoordinates) ? MemoryLayout<Float32>.size * 2 : MemoryLayout<Int16>.size * 2)
            + channels.count
    }
}

/// One sample of a stroke, as a value — the point-at-a-time view of `StrokeSamples`.
///
/// **Every channel has a field here even though the run decides which are stored**, and that
/// asymmetry is deliberate. A sample's field is `SampleChannel.neutral` where the run carries
/// nothing, so a value that has left its run is still a complete, honest reading and the geometry
/// layer's slicing, interpolating and bisecting carry every channel through without knowing any
/// channel exists. What §5.5 rules out is *storing* the record this way, and it is not stored this
/// way: `StrokeSamples` holds parallel arrays and an absent channel is an empty one.
struct VectorSample: Equatable {
    var x: CGFloat
    var y: CGFloat
    /// `0…1`. See `SampleChannel.pressure`.
    var pressure: CGFloat = SampleChannel.pressure.neutral
    /// Seconds since the previous stored point. See `SampleChannel.deltaTime`.
    var deltaTime: CGFloat = SampleChannel.deltaTime.neutral
    /// Radians `0…π/2`, π/2 upright. See `SampleChannel.tiltAltitude`.
    var tiltAltitude: CGFloat = SampleChannel.tiltAltitude.neutral
    /// Radians `0…2π` in the samples' own space. See `SampleChannel.tiltAzimuth`.
    var tiltAzimuth: CGFloat = SampleChannel.tiltAzimuth.neutral

    var point: CGPoint { CGPoint(x: x, y: y) }

    init(x: CGFloat, y: CGFloat, pressure: CGFloat = SampleChannel.pressure.neutral,
         deltaTime: CGFloat = SampleChannel.deltaTime.neutral,
         tiltAltitude: CGFloat = SampleChannel.tiltAltitude.neutral,
         tiltAzimuth: CGFloat = SampleChannel.tiltAzimuth.neutral) {
        self.x = x
        self.y = y
        self.pressure = pressure
        self.deltaTime = deltaTime
        self.tiltAltitude = tiltAltitude
        self.tiltAzimuth = tiltAzimuth
    }

    init(point: CGPoint, pressure: CGFloat = SampleChannel.pressure.neutral) {
        self.init(x: point.x, y: point.y, pressure: pressure)
    }

    /// Channel access by name-of-channel rather than name-of-field. **The one place the channels are
    /// enumerated per sample**, so `lerp` and every other per-sample operation is generic over the
    /// set and adding a channel does not sweep the geometry layer.
    subscript(channel: SampleChannel) -> CGFloat {
        get {
            switch channel {
            case .pressure: return pressure
            case .deltaTime: return deltaTime
            case .tiltAltitude: return tiltAltitude
            case .tiltAzimuth: return tiltAzimuth
            }
        }
        set {
            switch channel {
            case .pressure: pressure = newValue
            case .deltaTime: deltaTime = newValue
            case .tiltAltitude: tiltAltitude = newValue
            case .tiltAzimuth: tiltAzimuth = newValue
            }
        }
    }

    /// Position and every channel between `from` and `to`, each by its own rule — see
    /// `SampleChannel.interpolated`. `StrokeGeometry.lerp` is this; the cut boundary a split
    /// interpolates, the points `subdivided` inserts and the crossing a lasso bisects all land here,
    /// which is why none of them has to know that tilt exists.
    static func lerp(_ from: VectorSample, _ to: VectorSample, _ t: CGFloat) -> VectorSample {
        var result = VectorSample(x: from.x + (to.x - from.x) * t,
                                  y: from.y + (to.y - from.y) * t)
        for channel in SampleChannel.allCases {
            result[channel] = channel.interpolated(from[channel], to[channel], t)
        }
        return result
    }

    /// `self`, less the part of its **interval** channels that `predecessor` has already accounted
    /// for — the second half of `SampleChannel.isCumulative`'s arithmetic.
    ///
    /// A sample that has gained a new neighbour part-way through its own interval owes that
    /// neighbour the time that elapsed before it. Without this a cut piece's first full segment
    /// keeps the whole segment's duration against a fraction of its length, and reads as slower than
    /// the stroke ever was. Floored at zero, because a caller that hands over a predecessor from a
    /// different segment is wrong rather than negative.
    func afterInsertedPredecessor(_ predecessor: VectorSample) -> VectorSample {
        var result = self
        for channel in SampleChannel.allCases where channel.isCumulative {
            result[channel] = max(result[channel] - predecessor[channel], 0)
        }
        return result
    }

    /// `self` with the **interval** channels of every sample in `dropped` added to its own.
    ///
    /// The other direction: `StrokePathFit` keeps one sample out of several, and the time the ones it
    /// dropped took did not stop passing. Without this the stored Δt would be the interval between
    /// two *input* samples rather than between two stored points, so a refitted stroke's velocities
    /// would be its digitiser's rate rather than the artist's hand.
    func absorbing<S: Sequence>(_ dropped: S) -> VectorSample where S.Element == VectorSample {
        var result = self
        for sample in dropped {
            for channel in SampleChannel.allCases where channel.isCumulative {
                result[channel] += sample[channel]
            }
        }
        return result
    }
}

/// A run of samples this file's geometry can read: any `Int`-indexed random-access collection of
/// `VectorSample`, so one signature serves both a `StrokeSamples` and a bare `[VectorSample]`.
///
/// It exists so the *readers* — bounds, capsule chains, coverage, tangents, the spatial index, the
/// eraser's sweeps — need no conversion at their call sites and no allocation to be handed a stroke's
/// own storage. It deliberately does **not** vend the channel set: a producer that emits a new run
/// has to be told which channels the result carries, and making that a required argument rather than
/// a defaulted one is what stops the next channel being dropped silently.
protocol SampleRun: RandomAccessCollection where Element == VectorSample, Index == Int {}

extension Array: SampleRun where Element == VectorSample {}

/// **The stroke's samples, struct-of-arrays** — BRUSH.md §5.5.
///
/// Parallel arrays, one per channel, and *an absent channel is an empty array and costs nothing*.
/// Adding the next channel adds an array here rather than widening the record every stroke pays for,
/// and `channels` — the same `SampleChannelSet` the packer writes as one byte per run — is the single
/// statement of which arrays are real.
///
/// **Every operation that produces a new run is generic over the set.** `transformed(by:)`,
/// `appending`, `replacingPositions` and the initialisers all walk `channels` rather than naming
/// fields, which is the property this type exists for: the sites that used to rebuild a stroke as
/// `VectorSample(x:, y:, pressure:)` — a positional transform, an interpolation warp, a cut piece —
/// carried exactly the fields their author remembered, and would have dropped tilt on the day it
/// arrived. There are none of those left; there is one `transformed(by:)`.
///
/// The single exception to "a channel is carried" is `SampleChannel.isAngleInSampleSpace`, which
/// `transformed(by:)` turns with the ink. See there.
struct StrokeSamples: Equatable {
    /// One per sample. The only array that is never absent.
    private(set) var positions: [CGPoint]
    private(set) var pressures: [CGFloat] = []
    private(set) var deltaTimes: [CGFloat] = []
    private(set) var tiltAltitudes: [CGFloat] = []
    private(set) var tiltAzimuths: [CGFloat] = []
    /// Which of the arrays above are populated. Never carries `preciseCoordinates` — that bit is a
    /// property of how a run is *stored*, and lives on `VectorStroke.precise` in memory.
    private(set) var channels: SampleChannelSet

    // MARK: - Construction

    init(channels: SampleChannelSet = .pressureOnly) {
        positions = []
        self.channels = channels.subtracting(.preciseCoordinates)
    }

    /// `samples` as a run carrying exactly `channels`. **`channels` has no default**, and that is the
    /// guard rail: every construction site says out loud which channels its result holds, so a new
    /// channel cannot be lost by a site that predates it.
    init<S: Sequence>(_ samples: S, channels: SampleChannelSet) where S.Element == VectorSample {
        self.init(channels: channels)
        for sample in samples { append(sample) }
    }

    /// Positions only, with every channel at its neutral and none stored. The shape a synthetic run
    /// takes — a collapsed shape, an eraser's own walk, a test fixture.
    init(points: [CGPoint]) {
        positions = points
        channels = []
    }

    /// Room for `n` samples in every array this run holds. One call rather than five, so a caller
    /// building a long run does not have to know which channels exist.
    mutating func reserveCapacity(_ n: Int) {
        positions.reserveCapacity(n)
        for channel in channels.channels { self[storage: channel].reserveCapacity(n) }
    }

    mutating func append(_ sample: VectorSample) {
        positions.append(sample.point)
        for channel in channels.channels { self[storage: channel].append(sample[channel]) }
    }

    /// The array behind one channel. Private, and the **only** place the four stored properties are
    /// named together — everything public loops over `channels` and comes through here.
    private subscript(storage channel: SampleChannel) -> [CGFloat] {
        get {
            switch channel {
            case .pressure: return pressures
            case .deltaTime: return deltaTimes
            case .tiltAltitude: return tiltAltitudes
            case .tiltAzimuth: return tiltAzimuths
            }
        }
        set {
            switch channel {
            case .pressure: pressures = newValue
            case .deltaTime: deltaTimes = newValue
            case .tiltAltitude: tiltAltitudes = newValue
            case .tiltAzimuth: tiltAzimuths = newValue
            }
        }
    }

    // MARK: - Reading

    /// One channel's value at `index`, or the channel's **neutral** where this run does not carry it
    /// — BRUSH.md §5.5's defined answer, and the one `StrokeSensors` is built on.
    func value(_ channel: SampleChannel, at index: Int) -> CGFloat {
        guard channels.contains(channel) else { return channel.neutral }
        let stored = self[storage: channel]
        guard index >= 0, index < stored.count else { return channel.neutral }
        return stored[index]
    }

    /// Whether this run has real data for `channel`, as opposed to answering its neutral. The
    /// question `StrokeSensors.velocity` has to ask, because a stored Δt of zero and no Δt at all are
    /// different facts about a stroke.
    func carries(_ channel: SampleChannel) -> Bool { channels.contains(channel) }

    /// The channel arrays this run holds, in `SampleChannel.allCases` order — what the packer walks.
    var storedChannels: [SampleChannel] { channels.channels }

    func storedValues(_ channel: SampleChannel) -> [CGFloat] { self[storage: channel] }

    // MARK: - Producing

    /// Every position mapped through `t`, and every **angle** channel turned by the rotation `t`
    /// carries. Non-angle channels ride through untouched.
    ///
    /// The rotation is the affine's **polar** one, `atan2(b - c, a + d)` — the rotation closest to the
    /// matrix, which is the same choice `BrushStamper.DabPose` makes for an image dab's turn and for
    /// the same reason: the angle of the mapped x-axis agrees on every rotation and fails on every
    /// shear.
    ///
    /// This is the one function the layer-space conversion of BRUSH.md §2.7 needs. Capture already
    /// hands azimuth over in the canvas's space, because `StrokeInput` reads position and azimuth
    /// from the *same* view and `UITouch.azimuthAngle(in:)` expresses the angle in that view's
    /// coordinate system; what capture cannot know is the vector layer's own transform, the lasso's,
    /// or a canvas resize's, and every one of those arrives here.
    func transformed(by t: CGAffineTransform) -> StrokeSamples {
        let rotation = t.polarRotation
        var result = self
        result.positions = positions.map { $0.applying(t) }
        guard rotation != 0 else { return result }
        for channel in channels.channels where channel.isAngleInSampleSpace {
            result[storage: channel] = self[storage: channel].map { channel.rotated($0, by: rotation) }
        }
        return result
    }

    /// Every position replaced by `map`, every channel carried through unchanged, and every **angle**
    /// channel turned by `angleRotation`.
    ///
    /// `angleRotation` has no default on purpose. A map that is not an affine — an interpolation
    /// lattice warp, a liquify — has no single rotation, and a caller passing zero is saying "this
    /// map does not turn the ink, or nothing reads the angle yet", which is a claim someone should
    /// have to write down.
    func replacingPositions(_ map: (CGPoint) -> CGPoint, angleRotation: CGFloat) -> StrokeSamples {
        var result = self
        result.positions = positions.map(map)
        guard angleRotation != 0 else { return result }
        for channel in channels.channels where channel.isAngleInSampleSpace {
            result[storage: channel] = self[storage: channel].map { channel.rotated($0, by: angleRotation) }
        }
        return result
    }

    /// This run with `samples` in place of its points, keeping the channel set. The shape a cut, a
    /// split or a re-fit takes: the values come back through `VectorSample`, which carries every
    /// channel, and the *set* comes from the run they were cut out of.
    func replacingSamples<S: Sequence>(_ samples: S) -> StrokeSamples where S.Element == VectorSample {
        StrokeSamples(samples, channels: channels)
    }

    /// **Drops every channel whose stored bytes are all the neutral's**, because a channel that says
    /// nothing but "neutral" is indistinguishable from one that is absent — the funnel answers the
    /// same value either way — and the absent one costs no bytes.
    ///
    /// Applied once, where a stroke is committed. It is what makes the common case cheap without a
    /// per-brush capture decision: a **finger** reports π/2 and 0 for tilt and 1 for pressure, so a
    /// finger-drawn stroke stores six bytes a point rather than eight, and a stroke drawn at a
    /// constant full press stores five.
    ///
    /// Compared **after quantisation**, so a reading that will store as the neutral's byte counts as
    /// neutral. Anything else would keep a channel alive for a difference the format cannot hold.
    func compacted() -> StrokeSamples {
        var result = self
        for channel in channels.channels {
            let neutralByte = channel.quantised(channel.neutral)
            let stored = self[storage: channel]
            if stored.allSatisfy({ channel.quantised($0) == neutralByte }) {
                result.channels.subtract(channel.bit)
                result[storage: channel] = []
            }
        }
        return result
    }

    /// This run with `channel` added, filled from `values`. Used by the packer's inverse and by
    /// capture; `values` must be one per sample.
    mutating func setChannel(_ channel: SampleChannel, to values: [CGFloat]) {
        precondition(values.count == positions.count,
                     "a channel array is one value per sample, got \(values.count) for \(positions.count)")
        channels.insert(channel.bit)
        self[storage: channel] = values
    }

}

extension StrokeSamples: RandomAccessCollection {
    var startIndex: Int { 0 }
    var endIndex: Int { positions.count }

    /// The sample at `index`, with a neutral for every channel this run does not carry. Reads the
    /// arrays directly rather than looping the channel set: this is the hot accessor, hit once per
    /// point by every polyline consumer in the engine.
    subscript(index: Int) -> VectorSample {
        VectorSample(x: positions[index].x, y: positions[index].y,
                     pressure: pressures.isEmpty ? SampleChannel.pressure.neutral : pressures[index],
                     deltaTime: deltaTimes.isEmpty ? SampleChannel.deltaTime.neutral : deltaTimes[index],
                     tiltAltitude: tiltAltitudes.isEmpty ? SampleChannel.tiltAltitude.neutral
                                                         : tiltAltitudes[index],
                     tiltAzimuth: tiltAzimuths.isEmpty ? SampleChannel.tiltAzimuth.neutral
                                                       : tiltAzimuths[index])
    }
}

extension StrokeSamples: SampleRun {}

extension StrokeSamples: ExpressibleByArrayLiteral {
    /// A literal run of samples carries position and pressure — `SampleChannelSet.pressureOnly`. Any
    /// run that carries more is built by naming its set.
    init(arrayLiteral elements: VectorSample...) {
        self.init(elements, channels: .pressureOnly)
    }
}

extension CGAffineTransform {
    /// **The rotation closest to this transform** — the polar factor's angle, `atan2(b - c, a + d)`.
    ///
    /// Zero for a pure translation or a uniform scale, which is why neither turns anything that reads
    /// it. The obvious alternative, the angle of the mapped x-axis (`atan2(b, a)`), agrees on every
    /// rotation and fails on every shear.
    ///
    /// **One definition, two readers**: `StrokeSamples.transformed(by:)` turns an angle channel by it
    /// (BRUSH.md §2.7) and `BrushStamper.DabPose` turns an image dab by it (§3.5). It lives here, at
    /// the level with no renderer in it, so the dependency runs upward; `DabPose.polarRotation`
    /// carries the argument for *why a dab wants this one*.
    var polarRotation: CGFloat { atan2(b - c, a + d) }
}
