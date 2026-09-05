import CoreGraphics
import Foundation

/// A sensor a brush parameter can be driven by — BRUSH.md §2.8 and §6's inputs.
///
/// Four of them read a stored channel (`backingChannel`) and three are derived from the walk itself.
/// The difference matters in exactly one place: a stroke can be missing a *channel*, and then the
/// funnel answers the input's `neutral`. Nothing can be missing a geometry.
enum BrushInput: Hashable {
    /// How hard the pen was pressed, `0…1`. Neutral **1** — full press, which is what a finger
    /// reports and the reading at which a preset's `size ← pressure` row reaches full width.
    case pressure
    /// How far the Pencil is leaned over, `0` upright to `1` flat against the glass. Neutral **0**.
    case tiltAngle
    /// Which way it is leaned, as a fraction of a turn `0..<1`, in the samples' own space. Neutral
    /// **0**.
    case tiltDirection
    /// The direction the stroke is travelling at this dab, as a fraction of a turn `0..<1` — the
    /// brief's *"rotation of your brush follows your brush's painting direction"*.
    case direction
    /// Distance along the stroke from the **nearer end**, `0` at either tip to `1` at the middle.
    /// Neutral **1**, which is the answer where the walk cannot know how long the stroke is.
    case taper
    /// Speed at this dab in **brush widths per second**, normalised against
    /// `StrokeSensors.referenceSpeed` and clamped to `0…1`. Neutral **0**.
    ///
    /// Brush widths rather than canvas points for §4.1's reason: it is the unit that makes a uniform
    /// scale of a stroke change nothing, and spacing and λ are already measured in it.
    case velocity
    /// A per-dab draw from the stroke's own random field, `0..<1` — BRUSH.md §4, §2.17 and §2.28.
    /// Never missing: it is a hash of the seed and the arc length, so there is nothing to store and
    /// nothing to be absent.
    ///
    /// **The `BrushRandomiser` is everything authored about the draw** — λ, and §2.28's octave count
    /// and falloff. The channel beside it is *derived* from where this input sits (§6.2) and is
    /// rewritten by `BrushModulations` on construction and on decode.
    ///
    /// **This one case is both of §2.28's random shapes**, and that is why there is no separate
    /// randomiser module: a chain whose *input* is `.random` is a pure wobble, and a
    /// `BrushModule.scale(.random(…))` inside a chain is a randomiser attenuating what came before
    /// it. One case, one payload, one evaluator.
    case random(DabRandom.Channel, BrushRandomiser)

    /// The stored channel this input reads, or nil if it is derived from the walk.
    var backingChannel: SampleChannel? {
        switch self {
        case .pressure: return .pressure
        case .tiltAngle: return .tiltAltitude
        case .tiltDirection: return .tiltAzimuth
        case .velocity: return .deltaTime
        case .direction, .taper, .random: return nil
        }
    }

    /// **BRUSH.md §5.5's defined neutral** — what the funnel answers when the stroke carries no data
    /// for this input, and so the value at which a modulation of it must contribute nothing.
    ///
    /// It is not a legacy concern: a **finger** reports no tilt and never will, and §2.10's
    /// apply-to-existing verb can point any stroke at a brush reading anything.
    var neutral: CGFloat {
        switch self {
        case .pressure: return 1
        case .tiltAngle: return 0
        case .tiltDirection: return 0
        case .direction: return 0
        case .taper: return 1
        case .velocity: return 0
        case .random: return 0
        }
    }
}

extension BrushInput: Codable {
    private enum CodingKeys: String, CodingKey { case kind, wavelength, octaves, falloff }
    private enum Kind: String, Codable {
        case pressure, tiltAngle, tiltDirection, direction, taper, velocity, random
    }

    /// **Written out rather than synthesized, and the channel is deliberately off the wire.**
    ///
    /// A synthesized codec for an enum with a payload spells it `_0`, which is a compiler artifact in
    /// a file an artist's brushes live in. And `random`'s channel is *derived* from where its row sits
    /// (`BrushModulations`), so writing it down would create a second, authoritative-looking copy of a
    /// fact the matrix owns — the exact shape of the `BrushShape` + `customTextureFileName` pair §12
    /// stage 5 deleted. Only λ, the authored half, is stored.
    ///
    /// **§2.28's octaves are written only when there are any.** A single-octave randomiser is what
    /// every `random` input carried before the chain existed, and it writes exactly the two keys it
    /// wrote then — so the wire cost of the feature is zero for a brush that does not use it.
    ///
    /// Strict on an unrecognised `kind`, per §2.14: the documents on the device are expendable, so
    /// there is no earlier spelling to accept and an unknown sensor is a corrupt brush rather than an
    /// old one.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pressure: try c.encode(Kind.pressure, forKey: .kind)
        case .tiltAngle: try c.encode(Kind.tiltAngle, forKey: .kind)
        case .tiltDirection: try c.encode(Kind.tiltDirection, forKey: .kind)
        case .direction: try c.encode(Kind.direction, forKey: .kind)
        case .taper: try c.encode(Kind.taper, forKey: .kind)
        case .velocity: try c.encode(Kind.velocity, forKey: .kind)
        case .random(_, let randomiser):
            try c.encode(Kind.random, forKey: .kind)
            try c.encode(randomiser.wavelength, forKey: .wavelength)
            if !randomiser.isSingleOctave {
                try c.encode(randomiser.octaves, forKey: .octaves)
                try c.encode(randomiser.falloff, forKey: .falloff)
            }
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .pressure: self = .pressure
        case .tiltAngle: self = .tiltAngle
        case .tiltDirection: self = .tiltDirection
        case .direction: self = .direction
        case .taper: self = .taper
        case .velocity: self = .velocity
        case .random:
            // The channel is re-derived by `BrushModulations`; anything here would be overwritten.
            self = .random(.scatterAngle, BrushRandomiser(
                wavelength: try c.decode(CGFloat.self, forKey: .wavelength),
                octaves: try c.decodeIfPresent(Int.self, forKey: .octaves) ?? 1,
                falloff: try c.decodeIfPresent(Double.self, forKey: .falloff)
                    ?? BrushRandomiser.defaultFalloff))
        }
    }
}

/// Where on a stroke one dab sits, in **both** coordinates the walk produces.
///
/// BRUSH.md §5.5 spells the funnel `value(of:atArcLength:)`, and one coordinate is not enough: the
/// per-point channels are attached to *points* and interpolate by parameter, while §4.1 rules that
/// the random field is addressed by *arc length in brush widths*. The walk has both for free — it
/// steps the parameter and accumulates the arc length in the same loop — so carrying both is strictly
/// better than inverting one into the other, which would cost an arc-length table and would have to
/// be bit-exact to keep `RasterVectorParityLogicTests` at zero tolerance.
struct DabSite: Equatable {
    /// Index-plus-fraction into the stored points — `StrokeGeometry`'s parametric domain.
    var parameter: CGFloat
    /// Arc length from the stroke's first dab, in brush widths — `DabRandom`'s coordinate.
    var arcWidths: CGFloat
}

/// **The one place a sensor is resolved** — BRUSH.md §5.5's evaluation funnel.
///
/// Every brush parameter that is driven by something asks here, so a new sensor is one case in one
/// switch rather than a thread through every parameter, and — the part that is not merely tidy — the
/// answer for a stroke that carries no data for the channel asked for is *defined* rather than
/// whatever a field happened to default to.
///
/// **The guarantee is a rendering one**: a brush reading a channel the stroke does not carry renders
/// identically to the same brush with that modulation removed. That is why the neutrals are what they
/// are — `pressure` 1 rather than 0, `taper` 1 rather than 0 — and it is pinned rather than asserted,
/// in `SampleRecordLogicTests`.
struct StrokeSensors {
    /// The stroke's own samples. `StrokeSamples.value(_:at:)` answers a channel's neutral where the
    /// run does not carry it, which is where the whole of §5.5 lands.
    let samples: StrokeSamples
    /// The curve the walk follows — BRUSH.md §3.4. `direction` reads it rather than a chord, because
    /// at the fit's knot spacing a chord direction is a step function of the parameter and a
    /// direction-follow built on one would rotate in visible jumps.
    let path: StrokePath
    /// The stroke's random field — `VectorStroke.dabRandom` for stored geometry, the seed minted at
    /// pen-down for live drawing.
    let random: DabRandom
    /// The brush's diameter in canvas points, for `velocity`'s widths-per-second. Zero falls back to
    /// points, exactly as `BrushStamper`'s arc-length step does for a zero-width brush.
    let brushSize: CGFloat
    /// The whole stroke's arc length in brush widths, where the walk knows it.
    ///
    /// **Nil is the honest answer for the live raster tier**, which stamps as the pen moves and
    /// genuinely cannot know how long the stroke will be; `taper` answers its neutral there. That
    /// asymmetry is real and is written down in BRUSH.md §13 rather than papered over, because a
    /// taper modulation would otherwise render differently live and on replay — which is exactly the
    /// class of divergence `RasterVectorParityLogicTests` exists to catch.
    let totalArcWidths: CGFloat?

    /// Widths per second that reads as full speed. A 20 pt brush at 40 widths/s is 800 pt/s, which is
    /// a brisk flick; anything faster clamps. Documented and fixed rather than tuned per brush,
    /// because §6 gives every modulation its own curve and a second scale factor here would be two
    /// ways to say one thing.
    static let referenceSpeed: CGFloat = 40

    init(samples: StrokeSamples, path: StrokePath, random: DabRandom,
         brushSize: CGFloat, totalArcWidths: CGFloat? = nil) {
        self.samples = samples
        self.path = path
        self.random = random
        self.brushSize = brushSize
        self.totalArcWidths = totalArcWidths
    }

    /// The value of `input` at `site`, or its **neutral** where this stroke carries no data for it.
    ///
    /// **The neutral is not restated here.** Three of the four channel-backed inputs reach it by
    /// reading the channel — `StrokeSamples.value(_:at:)` answers `SampleChannel.neutral` for a run
    /// that does not carry one — and then running the same normalisation any stored reading gets, so
    /// an upright Pencil and no Pencil at all come out of one arithmetic rather than two constants
    /// that can drift apart. `BrushInput.neutral` is what the *tests* compare against; it is a claim
    /// about this function, not its implementation.
    ///
    /// `velocity` is the exception and has to be, because it reads the channel's **presence**: a Δt of
    /// zero is not a speed, so "no interval recorded" and "no time passed" cannot be one answer.
    func value(of input: BrushInput, at site: DabSite) -> CGFloat {
        switch input {
        case .pressure:
            return channelValue(.pressure, at: site.parameter)
        case .tiltAngle:
            // 0 upright, 1 flat: the sensor is how far it is *leaned*, so the neutral falls out of
            // the altitude neutral rather than being a second constant.
            let altitude = channelValue(.tiltAltitude, at: site.parameter)
            return min(max(1 - altitude / (.pi / 2), 0), 1)
        case .tiltDirection:
            return SampleChannel.wrappedAngle(channelValue(.tiltAzimuth, at: site.parameter)) / (2 * .pi)
        case .direction:
            let tangent = path.tangent(at: site.parameter)
            guard tangent.x != 0 || tangent.y != 0 else { return BrushInput.direction.neutral }
            return SampleChannel.wrappedAngle(atan2(tangent.y, tangent.x)) / (2 * .pi)
        case .taper:
            guard let total = totalArcWidths, total > 0 else { return BrushInput.taper.neutral }
            let fromNearerEnd = min(site.arcWidths, total - site.arcWidths)
            return min(max(fromNearerEnd / (total / 2), 0), 1)
        case .velocity:
            guard samples.carries(.deltaTime) else { return BrushInput.velocity.neutral }
            return velocity(at: site.parameter)
        case let .random(channel, randomiser):
            return random.unit(channel, at: site.arcWidths, randomiser: randomiser)
        }
    }

    /// One channel interpolated to `parameter`, by that channel's own rule — angles the short way
    /// round. Clamped to the run's domain, so an out-of-range parameter answers the nearest endpoint
    /// rather than extrapolating.
    private func channelValue(_ channel: SampleChannel, at parameter: CGFloat) -> CGFloat {
        guard !samples.isEmpty else { return channel.neutral }
        guard parameter > 0 else { return samples.value(channel, at: 0) }
        let last = samples.count - 1
        guard parameter < CGFloat(last) else { return samples.value(channel, at: last) }
        let index = Int(parameter.rounded(.down))
        let fraction = parameter - CGFloat(index)
        return channel.interpolated(samples.value(channel, at: index),
                                    samples.value(channel, at: index + 1), fraction)
    }

    /// Speed across the segment `parameter` falls in, in brush widths per second, normalised and
    /// clamped.
    ///
    /// Per **segment** rather than per point: Δt is stored as "seconds since the previous stored
    /// point", so the pair (chord from `i` to `i+1`, Δt at `i+1`) is one measurement of one motion,
    /// and interpolating either half of it across the segment would be inventing detail the record
    /// does not have.
    ///
    /// The chord rather than the curve's own length for the same reason `StrokePathFit` measures
    /// deviation against the chord: within the fit's 0.25 pt tolerance the two differ by less than a
    /// quarter of a point over a segment, and the curve length would cost a subdivision walk per dab.
    private func velocity(at parameter: CGFloat) -> CGFloat {
        guard samples.count > 1 else { return BrushInput.velocity.neutral }
        let index = min(max(Int(parameter.rounded(.down)), 0), samples.count - 2)
        let a = samples.positions[index], b = samples.positions[index + 1]
        let seconds = max(samples.value(.deltaTime, at: index + 1), SampleChannel.deltaTimeQuantum)
        let widths = hypot(b.x - a.x, b.y - a.y) / (brushSize > 0 ? brushSize : 1)
        return min(max(widths / seconds / StrokeSensors.referenceSpeed, 0), 1)
    }
}
