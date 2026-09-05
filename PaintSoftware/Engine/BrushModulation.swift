import CoreGraphics
import Foundation
import UIKit

/// **A brush parameter a sensor can drive** — BRUSH.md §6's outputs, and the brief's *"every
/// parameter should be able to be sensor driven"*.
///
/// The raw values are folded into `DabRandom`'s hash (see `DabRandom.Channel.modulation`), so a row
/// driven by `random` draws from a cell addressed by *which output it drives*. **Add cases, never
/// renumber them**, exactly as `DabRandom.Channel` says of its own: renumbering re-rolls every stroke
/// drawn with a randomised brush.
///
/// **`roundness` is missing from this list and BRUSH.md §6 names it.** That is a decision recorded in
/// §6 and §12 rather than an omission: a non-circular dab contradicts §3.5's ruling that *"a tip's
/// mask is square, by ruling. One scalar for the dab's size keeps `DabPose` at one multiply,
/// `BakedDab` at one number and the dirty-rect bound at one `abs`."* Shipping it means a second
/// extent through `DabTarget`'s two primitives, `BakedDab`, `DabPose.applied(to:)`, `dabBounds`,
/// `StrokeScratch`'s window and both compositors' dirty rects — and nothing before §12 stage 9's
/// chisel and flat brushes needs it. A field the renderer does not read would be worse than its
/// absence; this repo has a section on exactly that.
enum BrushOutput: String, Codable, CaseIterable, Hashable {
    /// A multiplier on the stroke's own diameter — `1` is full width.
    case size
    /// **What one stamp lays down** — BRUSH.md §2.11. The stroke's own opacity is the *cap* on what
    /// all of them together may reach, and it is not an output at all: it belongs to the stroke, is
    /// applied once at the merge (`DabTarget.beginStrokeGroup`), and cannot be modulated per dab
    /// without being the thing it caps.
    case flow
    /// The tip's rotation, in **turns**. See `BrushAngleSettings` — the one output that is not a
    /// plain sum of a base and its rows.
    case angle
    /// Distance to the next dab, as a fraction of the stroke's diameter.
    case spacing
    /// Random displacement off the path, as a fraction of the dab's diameter.
    case scatter
    /// **The probability that a dab is stamped at all** — BRUSH.md §2.18.
    case density
    /// The `.round` tip's edge falloff. A `.stamp` tip carries its edge in its own pixels and does
    /// not read this.
    case hardness
    /// Signed shifts applied to the stroke's colour, per dab.
    case hue
    case saturation
    case brightness

    /// A stable per-output number for `DabRandom.Channel.modulation`. Written down rather than taken
    /// from `allCases.firstIndex`, which would renumber every output whenever a case is inserted.
    var channelBase: UInt64 {
        switch self {
        case .size: return 1
        // 2 was `opacity`, deleted by §12 stage 8 when the cap moved onto the stroke. The gap
        // stays: this comment's own instruction is "add cases, never renumber them", and a
        // renumber re-rolls every stroke drawn with a randomised brush.
        case .flow: return 3
        case .angle: return 4
        case .spacing: return 5
        case .scatter: return 6
        case .density: return 7
        case .hardness: return 8
        case .hue: return 9
        case .saturation: return 10
        case .brightness: return 11
        }
    }

    /// What this output is worth with no modulation on it — the value `BrushDabSettings.default`
    /// carries and the identity a row is added on top of.
    var neutralBase: Double {
        switch self {
        case .size, .flow, .density: return 1
        case .spacing: return 0.1
        case .hardness: return 0.8
        case .angle, .scatter, .hue, .saturation, .brightness: return 0
        }
    }
}

extension DabRandom.Channel {
    /// **The field cell a modulation row draws from** — one per (output, row), so two `random` rows
    /// are independent draws rather than the same number wearing two hats.
    ///
    /// BRUSH.md §4: *"A channel is what replaces 'the next draw off the stream', and it is not
    /// optional. Scatter angle and scatter distance are two values at one arc length; a stream told
    /// them apart by order, and with no order the channel has to be in the hash or they would be the
    /// same number. §6's matrix adds a row per modulation on top of the three that exist."*
    ///
    /// **Derived from where the row sits rather than stored on it**, which is what makes "no two rows
    /// share a channel" a fact instead of an invariant somebody has to maintain. The cost is stated
    /// rather than hidden: inserting a row *before* another one on the same output re-rolls that
    /// one's draws. That is the same class of change as editing a brush's spacing (§4: *"those are
    /// different dabs"*) and it is confined to one output's own rows.
    /// The stride is **4096 rows an output**, which is not a round number chosen for looks: at any
    /// stride `s`, row `s` of one output collides with row 0 of the next, and a silent collision here
    /// is two parameters moving together for no visible reason. 4096 is past anything a brush editor
    /// could produce, and 0–15 stay reserved for the four intrinsic draws.
    ///
    /// **`slot` is BRUSH.md §2.22's second input, and it addresses a whole second *plane* rather than
    /// a second half of the row block.** A row with `random` in both slots must draw two independent
    /// values — reusing one channel would **square** a single draw rather than multiply two — so the
    /// second slot needs a channel of its own. Splitting the 4096 rows in half would work and is the
    /// wrong shape: it reintroduces exactly the collision the paragraph above reasons about, at half
    /// the distance. `slotStride` is instead larger than the whole matrix's span
    /// (`16 + 11 · 4096 + 4095 = 49,167`), so **no row count whatever can make slot 0 meet slot 1**.
    /// Slot 0's arithmetic is unchanged to the bit, which is what keeps every brush drawn before
    /// §2.22 drawing the same ink.
    static func modulation(_ output: BrushOutput, row: Int, slot: Int = 0) -> DabRandom.Channel {
        DabRandom.Channel(rawValue: 16
                          &+ UInt64(max(slot, 0)) &* DabRandom.Channel.slotStride
                          &+ output.channelBase &* DabRandom.Channel.outputStride
                          &+ UInt64(max(row, 0)))
    }

    /// Rows an output may carry before it would meet the next output. See above.
    static let outputStride: UInt64 = 4096
    /// The distance between one row's first input's channel and its second's — a power of two past
    /// the whole matrix's span, so the two planes cannot meet at any row count.
    static let slotStride: UInt64 = 1 << 20
}

/// **One row of BRUSH.md §6's matrix** — *(input, curve, amount)* driving one output.
///
/// `output = base + Σ amount · curve(input) · reading(second)` — BRUSH.md §2.22. The sensor's reading
/// is clamped to `0…1` and shaped by the curve; the amount is signed and is **not** clamped, and
/// neither is the sum — every output enforces its own legal range where it is used, which is the same
/// division `ResponseCurve` makes and `AnimationCurve` made before it.
///
/// **The second input is optional and its absence reads 1**, so a row without one is the plain
/// `amount · curve(input)` it was before §2.22, to the bit — `x * 1` is exactly `x`.
struct BrushModulation: Codable, Hashable {
    /// Which parameter this row drives.
    var output: BrushOutput
    /// Which sensor drives it. For `.random`, the channel carried here is **derived, not authored** —
    /// `BrushModulations` rewrites it from the row's position on construction and on decode, so a
    /// hand-written or stale channel cannot make two rows move together. The wavelength is the
    /// authored half.
    var input: BrushInput
    /// How the `0…1` reading is shaped. `.linear` is the pass-through and costs nothing.
    var curve: ResponseCurve
    /// How much of the shaped reading reaches the output. Signed.
    var amount: Double
    /// **BRUSH.md §2.22's second input — a *gain* on the first, not a second row.** Optional; absent
    /// reads 1.
    ///
    /// Two rows *add*, so `spacing ← random` beside `spacing ← pressure` is a pressure shift **plus**
    /// a fixed-amplitude wobble. A second input *scales*, so the wobble's amplitude is what pressure
    /// moves — which is §7.0's fourth worked example, *"how much random wobble there is depends on
    /// pressure"*, and the one thing the additive matrix could not state at all.
    ///
    /// **It is not curved, by ruling.** A second `ResponseCurve` per row for a gain term is
    /// expressiveness the ask does not need and a second thing to keep in step. And for `.random`,
    /// the channel here is derived exactly as `input`'s is — `BrushModulations` rewrites it from the
    /// row's position *in the second slot*, so a row randomised on both sides draws two independent
    /// values rather than squaring one.
    var second: BrushInput?

    init(_ output: BrushOutput, _ input: BrushInput, second: BrushInput? = nil,
         amount: Double, curve: ResponseCurve = .linear) {
        self.output = output
        self.input = input
        self.second = second
        self.curve = curve
        self.amount = amount
    }

    /// This row's contribution, given a reading of each of its inputs.
    ///
    /// `secondReading` defaults to 1, which is what the absence of a second input reads — and `x * 1`
    /// is exactly `x` in IEEE arithmetic, so a row without one contributes the identical `Double` it
    /// contributed before §2.22 rather than a nearby one.
    ///
    /// **The gain is clamped to `0…1` and the first reading's clamp is the curve's.** Every
    /// `BrushInput` is *defined* to answer inside `0…1`, so this is the same belt-and-braces
    /// `ResponseCurve.value(at:)` applies to its own input — and without it the two slots would treat
    /// one sensor differently: a stray reading above 1 would be flattened as an input and would
    /// *amplify* the row as a gain. A second input attenuates; raising `amount` is how a row is made
    /// bigger.
    func contribution(_ reading: CGFloat, second secondReading: CGFloat = 1) -> Double {
        amount * Double(curve.value(at: reading)) * Double(min(max(secondReading, 0), 1))
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case output, input, second, curve, amount }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        output = try c.decode(BrushOutput.self, forKey: .output)
        input = try c.decode(BrushInput.self, forKey: .input)
        // A row with no curve drawn on it is the common case and the default; leaving the key out is
        // what keeps a plain ramp two numbers on the wire.
        // §2.22: absent-by-default, so every brush written before the second input existed decodes
        // to a row with none and renders unchanged.
        second = try c.decodeIfPresent(BrushInput.self, forKey: .second)
        curve = try c.decodeIfPresent(ResponseCurve.self, forKey: .curve) ?? .linear
        amount = try c.decode(Double.self, forKey: .amount)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(output, forKey: .output)
        try c.encode(input, forKey: .input)
        // Left off the wire entirely when there is none — a row without a second input writes the
        // same four keys it always wrote.
        if let second { try c.encode(second, forKey: .second) }
        if !curve.isLinear { try c.encode(curve, forKey: .curve) }
        try c.encode(amount, forKey: .amount)
    }
}

/// **BRUSH.md §6's matrix** — every modulation a brush carries, as one ordered table.
///
/// A table rather than a field per output, which is §9.2's *"the modulation matrix means a new
/// parameter is data rather than code — a row in a table, not a branch in the stamper"*. An array
/// rather than a `[BrushOutput: [BrushModulation]]`, because a `Brush` is encoded into a document and
/// a dictionary's key order is not defined: the same brush would write two different files.
///
/// The one invariant it holds is `DabRandom.Channel.modulation`'s: a `.random` row's channel is a
/// function of where the row sits, stamped at the two places rows can enter the type. That is
/// `AnimationCurve`'s idiom for its own decision 4, and for the same reason — an invariant enforced
/// at construction cannot be broken afterwards.
struct BrushModulations: Codable, Hashable {

    /// Every row, in author order. `private(set)` because the channel normalisation above is the
    /// invariant and `init` / `setRows` are the only doors.
    private(set) var rows: [BrushModulation]

    init(_ rows: [BrushModulation] = []) {
        self.rows = BrushModulations.normalised(rows)
    }

    static let `default` = BrushModulations()

    var isEmpty: Bool { rows.isEmpty }

    mutating func setRows(_ rows: [BrushModulation]) {
        self.rows = BrushModulations.normalised(rows)
    }

    /// The rows driving one output, in order.
    func rows(for output: BrushOutput) -> [BrushModulation] { rows.filter { $0.output == output } }

    /// Whether any row drives `output` — the cheap question the render path asks before spending a
    /// colour conversion or a random draw on a parameter nothing modulates.
    func drives(_ output: BrushOutput) -> Bool { rows.contains { $0.output == output } }

    /// Whether any row is driven by `taper` — BRUSH.md §13's open question, decided in §12 stage 7.
    ///
    /// **`stampStroke` measures the stroke's whole length only when this is true.** Taper is the one
    /// input that needs a number the walk does not otherwise have (`StrokeSensors.totalArcWidths`), and
    /// measuring it is a second flattening pass over the curve. Asking first means a brush that does
    /// not taper pays nothing at all, and one that does pays a walk it could not be drawn without.
    /// **Both slots are asked**, and that is not defensive. §2.22's second input reaches the funnel by
    /// the same door as the first, so a row whose *gain* is `taper` needs `totalArcWidths` measured
    /// exactly as much — and `StrokeSensors` answers `taper`'s neutral, **1**, where the length is
    /// missing. A scan of first inputs alone would leave such a row silently at full gain for the
    /// whole stroke, which is a green render of a brush that does not taper.
    var readsTaper: Bool { rows.contains { $0.input == .taper || $0.second == .taper } }

    /// Whether every row is driven by `pressure` alone.
    ///
    /// **The question the consumers that have a pressure and no walk have to ask.** `StrokeGeometry`'s
    /// capsule chain, `VectorEraser`'s clean-cut gate and the `.preview` polyline all resolve a brush
    /// at a bare pressure with every other sensor at its neutral (`Brush.dabValues(atPressure:)`), and
    /// that is the *true* answer only for a brush this returns true for. Everything else falls back to
    /// the exact alpha punch, which is BRUSH.md §11's *"`supportsCleanCut` / `supportsSplitting` gate
    /// on brush properties, not on a list of known brushes"* reached through one more door.
    /// **A row's *second* input (§2.22) is asked too, and it has to be.** `dabValues(atPressure:)`
    /// answers every non-pressure sensor with its neutral, so a `size ← pressure × velocity` row
    /// contributes nothing at all there while contributing along the whole of a real stroke — the
    /// capsule chain would then claim a coverage the ink does not have, and `VectorEraser` would cut
    /// away faded ink it cannot see. `nil` is pressure-only because its absence reads a constant 1.
    var isPressureOnly: Bool {
        rows.allSatisfy { $0.input == .pressure && ($0.second ?? .pressure) == .pressure }
    }

    /// The amount of the first row driving `output` from `input`, or 0 where there is none.
    func amount(for output: BrushOutput, from input: BrushInput) -> Double {
        rows.first { $0.output == output && $0.input == input }?.amount ?? 0
    }

    /// Sets that amount, replacing the row in place or adding one carrying `curve`.
    ///
    /// **A row at amount 0 is kept rather than removed**, and that is deliberate: the curve is the
    /// artist's, and dropping the row at the bottom of a slider's travel would throw it away and
    /// hand back a straight line when the slider came back up.
    mutating func setAmount(_ amount: Double, for output: BrushOutput, from input: BrushInput,
                            curve: ResponseCurve = .linear) {
        if let index = rows.firstIndex(where: { $0.output == output && $0.input == input }) {
            rows[index].amount = amount
        } else {
            setRows(rows + [BrushModulation(output, input, amount: amount, curve: curve)])
        }
    }

    private static func normalised(_ input: [BrushModulation]) -> [BrushModulation] {
        var perOutput: [BrushOutput: Int] = [:]
        return input.map { row in
            var row = row
            let index = perOutput[row.output, default: 0]
            perOutput[row.output] = index + 1
            if case .random(_, let wavelength) = row.input {
                row.input = .random(.modulation(row.output, row: index), wavelength: wavelength)
            }
            // §2.22's second slot is rewritten here for the same reason the first is, and leaving it
            // out is the failure the mechanism exists to prevent: a hand-written or stale channel in
            // the gain slot could make two rows move together, or make one row square a single draw.
            if case .random(_, let wavelength)? = row.second {
                row.second = .random(.modulation(row.output, row: index, slot: 1), wavelength: wavelength)
            }
            return row
        }
    }

    // MARK: - Codable

    /// Encoded as the bare array, so a brush's JSON carries `"modulations":[…]` rather than a wrapper
    /// object around one key.
    init(from decoder: Decoder) throws {
        self.init(try [BrushModulation](from: decoder))
    }

    func encode(to encoder: Encoder) throws { try rows.encode(to: encoder) }
}

// MARK: - The resolved dab

/// **Every §6 output, resolved at one dab.** What the matrix answers; what the stamper turns into a
/// stamp.
///
/// The line between this and `BrushStamper.stampDab` is **values against draws**: everything here is
/// a pure function of the brush and the sensors at this site, and the three things that additionally
/// need a *draw* from the stroke's random field — the scatter offset, the angle's jitter and §2.18's
/// dropout — are taken in the stamper, from `DabRandom`. That keeps this type answerable by a caller
/// that has a pressure and no stroke (`Brush.dabValues(atPressure:)`).
struct BrushDabValues: Equatable {
    /// Fraction of the stroke's own diameter.
    var size: Double
    /// **What this one stamp lays down**, and the whole of a dab's alpha — BRUSH.md §2.11. The
    /// stroke's opacity is not here and never was a dab quantity: it caps the *sum* of the stamps.
    var flow: Double
    /// Fraction of the stroke's own diameter — the gap leading **away** from this dab.
    var spacing: Double
    var hardness: Double
    var scatter: Double
    /// `≥ 1` stamps every dab. See `BrushStamper`, which is where the draw it is compared against is
    /// taken.
    var density: Double
    /// Turns. The base plus direction-follow plus every `.angle` row; the jitter is a draw and is
    /// added in the stamper.
    var angleTurns: Double
    var hueShift: Double
    var saturationShift: Double
    var brightnessShift: Double
}

extension Brush {

    /// **BRUSH.md §6's matrix, evaluated once at one dab.**
    ///
    /// `reading` answers a sensor. `BrushStamper` hands it `StrokeSensors.value(of:at:)` — §5.5's one
    /// evaluation funnel — and the pressure-only overload below hands it the neutrals. Taking a
    /// closure rather than a `StrokeSensors` is what lets one evaluator serve both without a second
    /// arm to keep in step, which §10 is explicit about: *"Two ways to compute a dab's size is two
    /// ways for it to be wrong, and the parity test compares tiers rather than paths, so it would not
    /// catch the divergence."*
    ///
    /// One pass over the rows, accumulating into locals — no dictionary, no allocation, and nothing at
    /// all for a brush with no rows, which is what every dab of an unmodulated brush costs.
    func dabValues(_ reading: (BrushInput) -> CGFloat) -> BrushDabValues {
        var values = BrushDabValues(size: dab.size, flow: dab.flow,
                                    spacing: dab.spacing, hardness: dab.hardness, scatter: dab.scatter,
                                    density: dab.density, angleTurns: dab.angle.base,
                                    hueShift: dab.hueShift, saturationShift: dab.saturationShift,
                                    brightnessShift: dab.brightnessShift)
        // §6: "Angle has three contributions that sum: a base angle, direction-follow as a 0–100%
        // amount, and jitter." Two of them are here; the third is a draw. Direction-follow is not
        // folded into a row because §6 names it as its own contribution and an artist sets it as a
        // percentage — `BrushModulationLogicTests` pins that the two forms agree, so the redundancy
        // is a tested identity rather than §10's two-ways-to-compute trap.
        if dab.angle.directionFollow != 0 {
            values.angleTurns += dab.angle.directionFollow * Double(reading(.direction))
        }
        for row in modulations.rows {
            // §2.22: `amount · curve(input) · reading(second)`, and the second input's absence reads
            // 1. The `map` is what keeps a row without one from paying a *sensor* evaluation — the
            // multiply itself is exact either way, but `reading` is §5.5's funnel and a `direction`
            // read walks the curve's tangent.
            let contribution = row.contribution(reading(row.input), second: row.second.map(reading) ?? 1)
            switch row.output {
            case .size: values.size += contribution
            case .flow: values.flow += contribution
            case .angle: values.angleTurns += contribution
            case .spacing: values.spacing += contribution
            case .scatter: values.scatter += contribution
            case .density: values.density += contribution
            case .hardness: values.hardness += contribution
            case .hue: values.hueShift += contribution
            case .saturation: values.saturationShift += contribution
            case .brightness: values.brightnessShift += contribution
            }
        }
        return values
    }

    /// The matrix at one pressure, with every other sensor at its **neutral** — §5.5's defined answer.
    ///
    /// **True only for a brush whose rows are all pressure-driven**, which `BrushModulations
    /// .isPressureOnly` is the question for and which the three callers that need this all gate on.
    /// It is the honest shape of "what width does this brush draw at pressure p" asked without a
    /// walk: there is no arc length, so no random field; no curve, so no direction; no clock, so no
    /// velocity.
    func dabValues(atPressure pressure: CGFloat) -> BrushDabValues {
        let clamped = min(max(pressure, 0), 1)
        return dabValues { $0 == .pressure ? clamped : $0.neutral }
    }
}

// MARK: - Grouped settings

/// **The base value of every dab output** — BRUSH.md §6's *"`Brush`'s flat scalars group into
/// sub-structs the way `dynamics` and `blendMode` already are, each with a `static let default` and
/// defaulted decode."*
///
/// The reason §6 gives is a persistence one: `Brush`'s `Codable` is compiler-synthesized, so every new
/// flat key is a decode-compatibility question and a nested field with a default is not.
///
/// **`size` here is a fraction and `Brush.size` is the stroke's own diameter.** They are genuinely
/// two different numbers: the stroke's is per-stroke, comes from the toolbar, and is multiplied by a
/// lasso resize; this one is per-dab and is what the matrix moves. `BrushStamper` multiplies one by
/// the other.
///
/// **`Brush.opacity` has no counterpart here, and since §12 stage 8 that is the point.** BRUSH.md
/// §2.11 makes opacity a property of the *stroke* — the cap on what all its stamps together may
/// reach — and `flow` the property of one stamp. A per-dab opacity multiplier would be a second way
/// to spell flow, which is §10's two-ways-to-compute trap with a ruling attached.
struct BrushDabSettings: Codable, Hashable {
    /// Fraction of the stroke's diameter, before modulation. §6's `size` output.
    var size: Double = BrushOutput.size.neutralBase
    /// **What one stamp lays down**, before modulation — §6's `flow` output and BRUSH.md §2.11's
    /// half of the pair. The other half, the stroke's opacity, is `Brush.opacity` and the toolbar's.
    var flow: Double = BrushOutput.flow.neutralBase
    /// Distance between stamps, as a fraction of the stroke's diameter.
    var spacing: Double = BrushOutput.spacing.neutralBase
    /// `0…1` edge falloff — 0 fully feathered, 1 crisp. A `.round` tip's parameter only.
    var hardness: Double = BrushOutput.hardness.neutralBase
    /// `0…1` random position jitter, as a fraction of the dab's diameter.
    var scatter: Double = BrushOutput.scatter.neutralBase
    /// **BRUSH.md §2.18** — the probability a dab is stamped at all. 1 stamps every dab, which is
    /// every brush that does not ask for otherwise.
    var density: Double = BrushOutput.density.neutralBase
    /// **λ for `density`'s dropout draw, in brush widths — §2.18, and it sits on the row rather than
    /// on a modulation entry on purpose.**
    ///
    /// *"The coherence lives in the draw, not in the value compared against — modulating `density` by
    /// a coherent random while drawing white noise gives a thinned speckle rather than gaps."* At λ = 0
    /// ten overlapping dabs cover every point of the line, so dropping half of them only roughens the
    /// edge; at λ ≈ 3–4 widths a contiguous *run* drops and the line breaks into the long arcs the
    /// owner picked out of the comparison sheet. 3.5 is the middle of the ruled band, and it costs
    /// nothing while `density` is 1.
    var densityWavelength: CGFloat = 3.5
    /// §6's `angle` output, which has three contributions rather than one base.
    var angle: BrushAngleSettings = .default
    /// Signed shifts on the stroke's colour, applied per dab. 0 is the colour as picked.
    var hueShift: Double = BrushOutput.hue.neutralBase
    var saturationShift: Double = BrushOutput.saturation.neutralBase
    var brightnessShift: Double = BrushOutput.brightness.neutralBase

    static let `default` = BrushDabSettings()
}

extension BrushDabSettings {
    private enum CodingKeys: String, CodingKey {
        case size, flow, spacing, hardness, scatter, density, densityWavelength, angle
        case hueShift, saturationShift, brightnessShift
    }

    /// Defaulted throughout — §6's whole reason for the nesting. A field added here later is one
    /// field, not a decode-compatibility question.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BrushDabSettings.default
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size
        flow = try c.decodeIfPresent(Double.self, forKey: .flow) ?? d.flow
        spacing = try c.decodeIfPresent(Double.self, forKey: .spacing) ?? d.spacing
        hardness = try c.decodeIfPresent(Double.self, forKey: .hardness) ?? d.hardness
        scatter = try c.decodeIfPresent(Double.self, forKey: .scatter) ?? d.scatter
        density = try c.decodeIfPresent(Double.self, forKey: .density) ?? d.density
        densityWavelength = try c.decodeIfPresent(CGFloat.self, forKey: .densityWavelength) ?? d.densityWavelength
        angle = try c.decodeIfPresent(BrushAngleSettings.self, forKey: .angle) ?? d.angle
        hueShift = try c.decodeIfPresent(Double.self, forKey: .hueShift) ?? d.hueShift
        saturationShift = try c.decodeIfPresent(Double.self, forKey: .saturationShift) ?? d.saturationShift
        brightnessShift = try c.decodeIfPresent(Double.self, forKey: .brightnessShift) ?? d.brightnessShift
    }
}

/// **§6's `angle` output — the one that is not a plain sum of a base and its rows.**
///
/// *"Angle has three contributions that sum: a base angle, direction-follow as a 0–100% amount, and
/// jitter."* All three are in turns, and the tip is turned by their sum.
///
/// **`directionFollow` *is* also expressible as a modulation row** — `angle ← direction` at amount 1,
/// since this output is in turns and the funnel answers direction in turns — and that is not §10's
/// two-ways-to-compute trap by accident. §6 names all three, an artist sets a follow as a percentage
/// rather than by drawing a curve, and `BrushModulationLogicTests` pins that the named form and the
/// row form render the same dabs. A redundancy that is asserted is a tested identity; it is the
/// *unasserted* one §10 warns about.
///
/// **`jitter` is not.** It draws from `DabRandom.Channel.rotation` — one of the four intrinsic draws,
/// not a matrix channel — and it is *signed*, `±jitter/2` of a turn about the base rather than
/// `0…jitter` above it. An `angle ← random` row is a different value out of a different cell, so the
/// two coexist rather than duplicate.
struct BrushAngleSettings: Codable, Hashable {
    /// A fixed tilt on the tip, in turns.
    var base: Double = 0
    /// `0…1` — how much of the stroke's own travelling direction the tip follows. The brief's
    /// *"rotation of your brush follows your brush's painting direction"*.
    var directionFollow: Double = 0
    /// `0…1` — per-dab jitter, reaching ±half a turn at 1. A draw, so it is taken in the stamper.
    var jitter: Double = 0

    static let `default` = BrushAngleSettings()
}

extension BrushAngleSettings {
    private enum CodingKeys: String, CodingKey { case base, directionFollow, jitter }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BrushAngleSettings.default
        base = try c.decodeIfPresent(Double.self, forKey: .base) ?? d.base
        directionFollow = try c.decodeIfPresent(Double.self, forKey: .directionFollow) ?? d.directionFollow
        jitter = try c.decodeIfPresent(Double.self, forKey: .jitter) ?? d.jitter
    }
}

/// **What a brush does to the gesture rather than to a dab.** The two settings that are not §6
/// outputs, and could not be: `stabilization` acts on the incoming path before any dab exists, and a
/// blend mode is not a scalar to add a curve to.
struct BrushStrokeSettings: Codable, Hashable {
    /// `0…1` — how strongly raw input is smoothed before it reaches the canvas (`StrokeStabilizer`);
    /// 0 draws exactly at the raw touch position. BRUSH.md §2.12.
    var stabilization: Double = 0.2
    var blendMode: BrushBlendMode = .normal

    static let `default` = BrushStrokeSettings()
}

extension BrushStrokeSettings {
    private enum CodingKeys: String, CodingKey { case stabilization, blendMode }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BrushStrokeSettings.default
        stabilization = try c.decodeIfPresent(Double.self, forKey: .stabilization) ?? d.stabilization
        blendMode = try c.decodeIfPresent(BrushBlendMode.self, forKey: .blendMode) ?? d.blendMode
    }
}

// MARK: - Colour

/// The stroke's colour with §6's three shifts applied — the `hue` / `saturation` / `brightness`
/// outputs, which are the only ones that reach a dab as something other than a number.
///
/// **Called only when a shift is non-zero**, and that guard is not tidiness: `DabGradientCache` and
/// `DabImageCache` are both keyed on the dab's colour, so a colour that changes per dab is the
/// "rainbow brush stamping a new colour per dab" `DabGradientCache` names as its pathological case.
/// A brush that asks for colour jitter pays for it; every brush that does not pays one comparison.
enum BrushColorShift {
    static func apply(to color: UIColor, hue: Double, saturation: Double, brightness: Double) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return color }
        // Hue wraps — it is an angle, and a shift past the end of the wheel is the far side of it, not
        // magenta pinned at 1. Saturation and brightness clamp, because they have ends.
        var shifted = (h + CGFloat(hue)).truncatingRemainder(dividingBy: 1)
        if shifted < 0 { shifted += 1 }
        return UIColor(hue: shifted,
                       saturation: min(max(s + CGFloat(saturation), 0), 1),
                       brightness: min(max(b + CGFloat(brightness), 0), 1),
                       alpha: a)
    }
}

// MARK: - The rows a pressure-reactive brush is made of

extension BrushModulation {

    /// **`size ← pressure`** — a straight ramp from `atZero` of the stroke's width at no press up to
    /// full width at a full one, mixed in at `amount`.
    ///
    /// With `BrushDabSettings.size` set to `1 - amount`, this is *exactly* — to the bit —
    /// what `BrushDynamics.sizeFraction(forPressure:)` computed before §12 stage 7 deleted it:
    /// `(1 - k) + k · (m + (1 - m) · p)`, in that association and that order. `ResponseCurve.ramp`
    /// carries the argument for why the curve half is exact; `BrushModulationLogicTests` carries the
    /// pin that the five shipped presets render byte-identically because of it.
    static func sizeFromPressure(amount: Double, atZero: Double) -> BrushModulation {
        BrushModulation(.size, .pressure, amount: amount, curve: .ramp(from: atZero, to: 1))
    }

    /// **`flow ← pressure`** — a feather-light touch lays down less ink, mixed in at `amount`.
    /// Straight through, so with a base of `1 - amount` it is `(1 - k) + k · p`, which is
    /// `BrushDynamics.opacityFraction` to the bit.
    ///
    /// **It drives `flow` since §12 stage 8, and the rename is the ruling.** *"Pressure drives flow,
    /// not a per-dab ceiling"*: a light pass is faint, and going over it again darkens it — up to the
    /// stroke's opacity and no further. The arithmetic is unchanged; what changed is which of the two
    /// numbers §2.11 separates it is the arithmetic *of*.
    static func flowFromPressure(amount: Double) -> BrushModulation {
        BrushModulation(.flow, .pressure, amount: amount)
    }

    /// **`density ← pressure`, BRUSH.md §2.18 and §2.19** — the rough ink nib's dropout.
    ///
    /// A *threshold*, not a ramp, and §2.19 is the ruling: *"a taper is low pressure"*, so a linear
    /// fall would eat the point off every tapered stroke and end a hair spike in gaps. Density holds
    /// at 1 above `knee` and falls to `floor` at no press, so a taper stays solid while a stroke drawn
    /// genuinely light breaks along its whole length.
    ///
    /// The base is 0 and the amount 1, so the row *is* the curve: density is entirely what pressure
    /// says. Its λ is not here — it belongs to the draw, so it is `BrushDabSettings.densityWavelength`.
    static func densityFromPressure(knee: Double = 1.0 / 3, floor: Double = 0) -> BrushModulation {
        BrushModulation(.density, .pressure, amount: 1, curve: .threshold(knee: knee, low: floor))
    }
}
