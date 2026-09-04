import CoreGraphics
import Foundation

/// **The curve in §6's *(input, curve, amount)*** — how a sensor's `0…1` reading is shaped before it
/// is scaled by the modulation's amount. BRUSH.md §6, §2.19 and §7.
///
/// ## It is `AnimationCurve` over a different axis, and that is the whole design
///
/// BRUSH.md §7: *"The curve editor already exists. TODO (38) built bezier tangent handles with a tap
/// grammar for the timeline's graph band; a pressure curve is the same control over a different
/// domain, and reusing it is what keeps this from being a second curve implementation."*
///
/// So this type holds an `AnimationCurve` and does exactly one thing to it: it converts the sensor's
/// `0…1` domain onto that curve's own integer-frame axis. There is no bezier arithmetic here, no
/// second tangent grammar, no second set of handle modes and no second answer to what `.autoClamped`
/// means. Everything §12 stage 10's editor already knows how to draw and drag, it can draw and drag
/// here; see `curve`, which is the binding it edits.
///
/// **Why a wrapper rather than storing a bare `AnimationCurve` on the modulation.** The scale below
/// is a unit conversion, and an unnamed unit conversion repeated at every call site is the shape of
/// bug this repo has caught three times (RENDER.md §3.8's size-keyed memos, §4.1's points-versus-
/// widths). Naming it once means a caller cannot forget it. `value(at:)` is the only way in.
///
/// **Why not widen `AnimationCurve.Key.frame` to a `Double` instead.** Its decision 4 — at most one
/// key per frame — is stated *because* the document timeline is integer-only, and it is what keeps a
/// zero-length segment (which divides by zero in the bezier parameterisation) unrepresentable.
/// Widening it would trade that invariant, across every keyframed channel in the document, for a
/// finer key placement than a finger can author. The fixed grid below is 1/1000 of the sensor's
/// range, which is four times finer than the 0…1 sliders that author every other brush number.
///
/// ## The identity is the *empty* curve, and it is free
///
/// A modulation with no curve drawn on it is a straight pass-through, which is what almost every row
/// is and what all five shipped presets use. That case must not cost a binary search and a Newton
/// solve per dab per row, so it is a `guard` — and it is also why this cannot simply forward to
/// `AnimationCurve.evaluate`, which answers **0** for an empty curve (correctly, for a channel: a
/// channel with no keys is not animated and the caller is meant to read its static value instead).
/// Here 0 would silently delete the modulation.
struct ResponseCurve: Codable, Hashable {

    /// How many of `AnimationCurve`'s frames the sensor's `0…1` range is spread across.
    ///
    /// 1024, so a key lands on a thousand-and-twenty-fourth of the input range. `AnimationCurve`
    /// evaluates at a `Double` time, so the *curve* is continuous at any resolution; this only bounds
    /// where a **key** may sit, and a finger authoring a pressure curve cannot place one finer.
    ///
    /// **A power of two, and that is load-bearing rather than tidy.** `value(at:)` multiplies by this
    /// and `AnimationCurve`'s linear segment divides by it, so the round trip has to be the identity
    /// or a straight ramp is not a straight ramp. At 1024 it is exact for every input, because both
    /// operations are an exponent shift. MEASURED over 200,000 random inputs: **0** disagreements at
    /// 1024 and **6,909** at 1000 — and a disagreement is one ulp of dab diameter, which is precisely
    /// what `RasterVectorParityLogicTests`' zero tolerance and the preset pin are unwilling to spend.
    static let scale: Double = 1024

    /// The keys and handles, in `AnimationCurve`'s own terms. Public because §12 stage 10's editor
    /// binds to it directly — that is the point of this type being a wrapper.
    ///
    /// Its `step` is left at 1 and nothing here reads it: "hold the value for a run of frames" is a
    /// fact about a timeline and has no meaning over a sensor's range.
    var curve: AnimationCurve

    init(_ curve: AnimationCurve = AnimationCurve()) { self.curve = curve }

    /// The straight pass-through — `value(at: x) == x`, clamped to `0…1`. The default every
    /// modulation starts at.
    static let linear = ResponseCurve()

    /// Whether this curve shapes anything at all. `linear` and a curve whose keys were all deleted
    /// are the same thing, deliberately: there is no third state where a row is "curved by nothing".
    var isLinear: Bool { curve.isEmpty }

    /// The curve at a sensor reading.
    ///
    /// **The input is clamped to `0…1` and the output is not clamped at all.** Both halves are
    /// deliberate. Every `BrushInput` is defined to answer inside `0…1`, so clamping the input is
    /// belt-and-braces that also fixes what a curve means outside its own domain; the output is left
    /// alone because `AnimationCurve`'s decision 1 is that overshoot is the feature, and an output's
    /// legal range is enforced where the output is *used* (a diameter has a floor, an alpha a
    /// ceiling) rather than eleven times over in here.
    func value(at x: CGFloat) -> CGFloat {
        let clamped = min(max(x, 0), 1)
        guard !curve.isEmpty else { return clamped }
        return CGFloat(curve.evaluate(at: Double(clamped) * ResponseCurve.scale))
    }

    // MARK: - Building one

    /// A straight ramp from `low` at input 0 to `high` at input 1.
    ///
    /// **Bit-exact with `low + (high - low) · x`**, which is what makes it able to carry
    /// `BrushDynamics`' deleted size blend with no pixel moving: `AnimationCurve`'s `.linear` segment
    /// is `a.value + (b.value - a.value) * ((t - a.frame) / h)`, and with the keys at 0 and `scale`
    /// that is `low + (high - low) * (x·scale / scale)`. The division is by the exact value it
    /// multiplied by, so it is the identity in IEEE arithmetic rather than nearly so — which is what
    /// `BrushModulationLogicTests` pins at zero tolerance.
    static func ramp(from low: Double, to high: Double) -> ResponseCurve {
        ResponseCurve(AnimationCurve(keys: [
            AnimationCurve.Key(frame: 0, value: low, tangentMode: .vector, interpolation: .linear),
            AnimationCurve.Key(frame: Int(scale), value: high, tangentMode: .vector, interpolation: .linear)
        ]))
    }

    /// **BRUSH.md §2.19's threshold** — flat at `high` above `knee`, falling to `low` at input 0.
    ///
    /// The shape `density ← pressure` needs and the reason §2.19 exists: *"a taper is low pressure"*,
    /// so a plain ramp eats the point off every tapered stroke and a hair spike ends in gaps. Holding
    /// flat above about a third of full pressure keeps the taper solid while a stroke drawn genuinely
    /// light breaks up along its whole length.
    ///
    /// Two `.linear` segments and a corner at the knee, rather than one eased curve, because the knee
    /// is the thing being expressed: an `.autoClamped` bezier through the same three keys rounds it
    /// off and puts the dropout back into the taper it was drawn to keep out.
    static func threshold(knee: Double, low: Double = 0, high: Double = 1) -> ResponseCurve {
        let k = min(max(knee, 0), 1)
        return ResponseCurve(AnimationCurve(keys: [
            AnimationCurve.Key(frame: 0, value: low, tangentMode: .vector, interpolation: .linear),
            AnimationCurve.Key(frame: Int(k * scale), value: high, tangentMode: .vector, interpolation: .linear),
            AnimationCurve.Key(frame: Int(scale), value: high, tangentMode: .vector, interpolation: .linear)
        ]))
    }

    // MARK: - Codable

    /// Encoded as the curve itself — one value, not a wrapper object, so a brush's JSON carries the
    /// same shape a keyframed channel's does and stage 10's editor reads one thing.
    init(from decoder: Decoder) throws {
        curve = try AnimationCurve(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try curve.encode(to: encoder)
    }
}
