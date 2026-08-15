import Foundation

// MARK: - Effects
//
// LAYER_COMPOSITING.md §4.4 and §7's Tier 3. **This file is the abstraction every later effect
// inherits**, so its shape matters more than the seven kernels it currently describes.
//
// **An effect knows nothing about which wrapper produced its input.** §4.4 ships every effect twice
// — as a stack layer (`LayerKind.compositing`, grading the accumulated backdrop within its own
// container) and as a 1-input node (grading its slot) — and says only the input-resolution rule
// differs. So an `Effect` is a colour transform and holds no reference to a layer, a slot, a
// container, or a tree. That is what lets one value serve both forms, and it is the reason the
// reserved `LayerKind.compositing` case can hold one: the layer supplies the texture, this supplies
// the transform.
//
// **Both backends consume the same derived values, and neither switches on the enum.** `passes`,
// `lookupTable` and `weights` are what `applyEffect` in `Composite.metal` is bound to and what
// `EffectReference.apply` reads. An effect's *interpretation* — which knob means what, how a curve
// becomes a table, how a radius becomes a set of convolution weights — happens exactly once, here, in
// Swift. The alternative (each backend destructuring the associated values itself) is two places to
// get a parameter's meaning wrong, and the way it fails is a picture that differs between GPU and CPU
// for reasons nothing to do with the arithmetic under test.
//
// **A multi-pass effect declares itself by returning more than one `EffectPass`, and nothing else
// about it is special.** `passes` is a list of (kind, parameter block) pairs, and both backends run
// the list in order, feeding each pass the previous one's output. A per-pixel effect returns one
// element and its encode path is the single dispatch it always was — no intermediate is allocated, no
// branch is taken, nothing is paid. A separable blur returns two elements differing only in their step
// vector; bloom returns four. The kernel is never told "which pass is this": a pass is fully described
// by the parameters it carries, so pass identity is data rather than a branch, and the same code that
// runs one dispatch runs four. See `Effect.passes` for why that is stated as a step vector rather than
// a pass index.
//
// That is `MaskResolver`'s pattern rather than a new one: §6.3's threshold is resolved once on the
// CPU and both backends receive the finished coverage, for the same reason. It buys exactness on the
// resolved part and costs a real thing, which is worth stating plainly — **a parity sweep cannot
// catch a mistake in the resolution itself**, because both sides make it identically. What catches
// that is a spot check against a value computed from the published formula, which is why
// `EffectParityLogicTests` has both shapes of test and not just the sweep.
//
// **A *grade* never changes alpha** (see `EffectReference.apply`), which is what makes one composable
// as an adjustment: it regrades what is there without reshaping it. **Blur and bloom do change alpha,
// and that is not an exception being tolerated — it is what those two effects are.** A Gaussian blur
// that left coverage alone would soften the colour inside a shape and leave its silhouette razor
// sharp, which is not a blur; a glow that could not spread past the artwork's own coverage would not
// be visible at all, since a glow is by definition the light outside the thing emitting it. So the
// contract is per effect and `Effect.reshapesCoverage` states it in code rather than in prose:
// everything that answers false is pinned byte-for-byte on alpha by `testNoEffectChangesAlpha`, and
// the two that answer true are pinned instead on the property that actually matters for them, which is
// that they convolve *premultiplied* values so colour and coverage stay in step (a blur of
// unpremultiplied colour pulls in the colour of pixels that are not there — the same argument
// `ChromaticAberration` already makes about its bilinear tap).

/// One Tier 3 effect and the parameters it runs with.
///
/// An enum with associated values rather than a kind-plus-every-parameter struct, for the reason
/// `BlendMode`'s exhaustive switches give: a Brightness effect cannot carry a gradient's stops, and
/// adding a case fails to compile in `kindCode`, `params`, `lookupTable` and `displayName` until
/// someone has decided what it does in each. A struct with one field per effect would carry seven
/// sets of dead parameters through every document and would make "which of these is live" a runtime
/// question.
enum Effect: Equatable {
    /// The five-knob transfer function every levels UI is, resolved into `lookupTable`.
    case levels(Levels)
    /// An arbitrary tone curve through control points — the same table as `levels`, built differently.
    case curves(Curves)
    case brightnessContrast(BrightnessContrast)
    case hsvShift(HSVShift)
    case gradientMap(GradientMap)
    case chromaticAberration(ChromaticAberration)
    /// Posterize, ordered dither and halftone: one quantizer, three screens (§7 lists them as one item).
    case posterize(Posterize)
    case noise(Noise)
    /// Gaussian and directional, which are the same 1D convolution run twice and once (§7's "separable,
    /// two passes" item — the first effect in this file that is not one dispatch).
    case blur(Blur)
    /// Threshold, blur, add — §7's "nearly free once blur exists", and it is: two small kernel cases
    /// and a four-element pass list, with no new plumbing anywhere.
    case bloom(Bloom)

    /// **The 3×3 Sobel gradient magnitude of `Lum`, one direct pass.** §7 pairs it with Outline: "it
    /// can derive line art from a painting". It reads a 3×3 neighbourhood of the *premultiplied* texel
    /// directly — never unpremultiplied, the same convention `blur1D` follows — so a transparency edge
    /// and a colour edge are the same kind of gradient and the impulse fixture (opaque on transparent)
    /// exercises exactly what a painted line-art edge needs. The output is `(m, m, m, m)`, where `m` is
    /// the normalized magnitude: trivially a valid premultiplied colour (`rgb == a` always), and the
    /// reason this replaces the image rather than being mixed over it — see `reshapesCoverage`.
    case sobel(Sobel)
    /// **Sharpen / unsharp mask: `x + amount·(x − blur_r(x))`.** Fits the multi-pass contract with zero
    /// new plumbing — see `Sharpen`'s doc for the three-pass shape, which is bloom's combine shape
    /// exactly, and for what "amount" operates on.
    case sharpen(Sharpen)
    /// **Outline / stroke around alpha — one direct disc gather.** Exact Euclidean distance, not the
    /// L∞ a pair of separable max passes would give (which paints a square ring around a round shape).
    /// See `Outline` and `Effect.maxOutlineRadius` for the cost that choice buys.
    case outline(Outline)

    /// The label an effect picker shows, written out for the reason `BlendMode.displayName` is.
    var displayName: String {
        switch self {
        case .levels:              return "Levels"
        case .curves:              return "Curves"
        case .brightnessContrast:  return "Brightness / Contrast"
        case .hsvShift:            return "HSV Shift"
        case .gradientMap:         return "Gradient Map"
        case .chromaticAberration: return "Chromatic Aberration"
        case .posterize:           return "Posterize"
        case .noise:               return "Noise"
        case .blur(let blur):      return blur.isDirectional ? "Directional Blur" : "Gaussian Blur"
        case .bloom:               return "Bloom"
        case .sobel:               return "Sobel"
        case .sharpen:             return "Sharpen"
        case .outline:             return "Outline"
        }
    }

    /// Whether this effect may change alpha. **False for every grade, true for blur, bloom, Sobel,
    /// sharpen and outline** — the file header's argument for blur and bloom (a blur that left the
    /// silhouette sharp is not a blur) applies to all three of the newer effects for their own reasons:
    /// Sobel's output *is* a magnitude, sharpen's combine operates on the full premultiplied vector
    /// exactly as bloom's does, and an outline by definition paints coverage where the shape had none.
    ///
    /// Stated as a property rather than a comment because it is the precondition of a test: everything
    /// answering false is swept for byte-exact alpha, and a grade that quietly started reshaping
    /// coverage would have to come here and say so first.
    var reshapesCoverage: Bool {
        switch self {
        case .blur, .bloom, .sobel, .sharpen, .outline: return true
        default:                                        return false
        }
    }
}

// MARK: - Parameters

extension Effect {

    /// Photoshop's and GIMP's Levels, which is also every other implementation of it:
    /// `out = outBlack + (clamp((c - inBlack) / (inWhite - inBlack)) ^ (1/gamma)) * (outWhite - outBlack)`.
    ///
    /// One set of knobs for all three channels — the composite channel of a levels dialog. Per-channel
    /// levels needs no kernel work whatever, because `lookupTable` is already RGBA per entry and the
    /// kernel already indexes each channel with its own value; it is a parameter change here and
    /// nothing else, which is why the table is RGBA rather than a single 256-byte ramp.
    struct Levels: Equatable {
        var inputBlack: Double = 0
        var inputWhite: Double = 1
        /// The midtone slider. Above 1 lifts shadows, below 1 deepens them — `t^(1/gamma)`.
        var gamma: Double = 1
        var outputBlack: Double = 0
        var outputWhite: Double = 1
    }

    /// A tone curve as control points, resolved by **monotone cubic (Fritsch–Carlson) interpolation**.
    ///
    /// Shape-preserving is the whole requirement for a tone curve: a natural cubic spline through the
    /// same points overshoots between them, which on a curve reads as a dark band appearing above a
    /// point the artist dragged up. Fritsch–Carlson is the standard fix and is what the monotonicity
    /// assertion in `EffectParityLogicTests` pins.
    ///
    /// Outside the first and last point the curve holds flat, so a curve that does not start at x = 0
    /// clips rather than extrapolating off the end of the table.
    struct Curves: Equatable {
        var points: [CurvePoint] = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]
    }

    /// **CSS Filter Effects Module Level 1's `contrast()` and `brightness()`**, in that order.
    ///
    /// A published definition rather than one of the many plausible ones: `contrast(amount)` is the
    /// linear transfer `slope = amount, intercept = 0.5 - 0.5 * amount` and `brightness(amount)` is
    /// `slope = amount, intercept = 0`, so 1 is the identity for both. Choosing the spec matters here
    /// for the same reason phases 5a/7 chose W3C Compositing Level 1 for the blend modes — a
    /// "reasonable" alternative (adding a signed offset, or scaling around black instead of mid-grey)
    /// is a different picture, and there is no way to tell later which one the document was graded
    /// with.
    ///
    /// The spec composes filter functions in list order, and this applies contrast first: it is the
    /// order the two names are written in everywhere, and the result is clamped once at the end rather
    /// than between the two, so a value driven briefly out of range by contrast can be brought back by
    /// brightness instead of being flattened in between.
    ///
    /// **Applied to the stored values, not to linear light.** SVG filter primitives default to
    /// linearRGB; CSS filter *functions* specify sRGB; this app is device-RGB and colour-management-free
    /// end to end (`Composite.metal`'s header is emphatic about why), so the transfer runs on the bytes
    /// as stored. Same convention as the blend modes, which W3C also states in a managed space.
    struct BrightnessContrast: Equatable {
        var brightness: Double = 1
        var contrast: Double = 1
    }

    /// A shift in HSV — hue rotated, saturation and value scaled.
    ///
    /// **Not CSS `hue-rotate()`**, which is a fixed 3×3 matrix approximating a luminance-preserving
    /// rotation and leaves greys grey only by construction. §7 asks for an HSV shift, which is what
    /// Photoshop's and CSP's Hue/Saturation adjustment does, and the difference is visible: a matrix
    /// rotation desaturates saturated primaries as it turns them, an HSV rotation does not.
    ///
    /// The conversion is `ColorMath.rgbToHSB`/`hsbToRGB` — the app's existing one, already used by the
    /// colour picker — which is deliberate: it makes the CPU reference for this effect an
    /// *independently written* implementation rather than a transcription of the shader, so the
    /// measured GPU-vs-CPU delta for HSV is worth more than it would be if both sides came from one
    /// author's hand in one sitting.
    struct HSVShift: Equatable {
        /// Degrees, wrapping. Artist-facing units; the conversion helpers take turns.
        var hueDegrees: Double = 0
        var saturation: Double = 1
        var value: Double = 1
    }

    /// Luminance in, colour out — the gradient sampled at the pixel's own brightness.
    ///
    /// **Luminance is W3C Compositing Level 1's `Lum`** (0.3 R + 0.59 G + 0.11 B), which is not a new
    /// choice: it is the same weighting `Compositor.swift`'s `lum` and `Composite.metal`'s `lum`
    /// already use for Hue/Saturation/Color/Luminosity and Lighter/Darker Color, and "how bright is
    /// this colour" gets one definition in this app rather than two that nearly agree.
    ///
    /// Stop alpha is ignored, because an effect never changes coverage.
    struct GradientMap: Equatable {
        var stops: [GradientStop] = [
            GradientStop(position: 0, color: CodableColor(red: 0, green: 0, blue: 0, alpha: 1)),
            GradientStop(position: 1, color: CodableColor(red: 1, green: 1, blue: 1, alpha: 1)),
        ]
        /// 0 leaves the pixel alone, 1 replaces it with the mapped colour.
        var mix: Double = 1
    }

    /// §7's "per-channel UV offset": red sampled at `+offset`, blue at `-offset`, green where it is.
    ///
    /// Directional rather than radial. Radial (scaling each channel's distance from an optical centre)
    /// is what a lens actually does and is the natural next parameter, but it is a second behaviour in
    /// the same kernel, and a displacement stated in pixels is a thing a test can assert exactly.
    ///
    /// Sampling is bilinear with clamp-to-edge, on **premultiplied** texels — which is the whole reason
    /// premultiplied storage exists, since interpolating unpremultiplied colour across an alpha edge
    /// pulls in the colour of pixels that are not there.
    struct ChromaticAberration: Equatable {
        var offsetX: Double = 0
        var offsetY: Double = 0
    }

    /// Quantization to `levels` steps, offset by a screen.
    ///
    /// The three effects §7 groups together are one formula: `floor(c * (n - 1) + d) / (n - 1)`, where
    /// `d` is the screen's value at this pixel. At `d = 0.5` that is plain rounding, which is
    /// posterize; a Bayer matrix in `d` is ordered dithering; a clustered-dot matrix is halftone. So
    /// `screen` selects a table and `screenStrength` fades `d` back toward 0.5, and posterize is the
    /// strength-0 case rather than a separate branch.
    struct Posterize: Equatable {
        /// Steps per channel, at least 2 — two steps is pure black and white.
        var levels: Int = 4
        var screen: Screen = .none
        /// 0 is flat posterize whatever the screen; 1 is the screen at full amplitude.
        var screenStrength: Double = 0
    }

    /// Uniform noise added to colour, from a hash of the pixel's coordinates.
    ///
    /// A hash rather than a random buffer so the grain is a pure function of position and seed — the
    /// same value on both backends, at any canvas size, without either one uploading anything. See
    /// `EffectReference.noiseValue` for why the hash is stated in wrapping 32-bit integer arithmetic
    /// and truncated to 24 bits before it becomes a float.
    struct Noise: Equatable {
        /// Peak deviation, in colour units, of the uniform noise added to each channel.
        var amount: Double = 0
        /// One value per pixel rather than one per channel — grain, rather than colour speckle.
        var isMonochrome: Bool = true
        var seed: UInt32 = 1
    }

    /// Gaussian and directional blur — **one 1D convolution, run on two axes or on one**.
    ///
    /// A Gaussian is separable: convolving with a 2D Gaussian is convolving with a 1D Gaussian
    /// horizontally and then vertically, which turns `O(r²)` taps per pixel into `O(r)` and is the
    /// entire reason §7 calls this the item that needs the ping-pong buffer. A directional (motion)
    /// blur is the *same* 1D convolution run once, along an arbitrary angle rather than along an axis.
    /// So the two are one kernel and one weight table, differing only in the pass list `passes` builds:
    /// two passes stepping `(1, 0)` and `(0, 1)`, or one stepping `(cos θ, sin θ)`.
    ///
    /// **`radius` is the support, and `sigma` is derived as `radius / 3`.** Truncating a Gaussian at 3σ
    /// is the standard rule (it discards ~0.3% of the mass, below a channel step), and stating the knob
    /// as the radius rather than as σ is what every blur UI does — so the artist's number is the one
    /// that says how far the blur actually reaches, and the tap count follows from it rather than
    /// being a second thing to get wrong.
    ///
    /// **Capped at `Effect.maxBlurTaps`.** A blur is the first effect in this file whose cost is not
    /// bounded by the pixel count alone — it is `2 · (2r + 1)` samples per pixel — so the cap is a real
    /// limit rather than a defensive one, and it is here rather than in a UI because both backends have
    /// to agree on what an out-of-range radius means.
    struct Blur: Equatable {
        /// Pixels. 0 is the identity, and exactly so — the pass list collapses to a single centre tap.
        var radius: Double = 0
        /// Only read when `isDirectional`. 0° steps along +x, 90° along +y.
        var angleDegrees: Double = 0
        /// One angled pass instead of two axis-aligned ones. See the type's note: this is not a
        /// different kernel, it is a different pass list over the same one.
        var isDirectional: Bool = false
    }

    /// Threshold, blur, add — the three passes §7 names, plus the blur's own second pass, so four.
    ///
    /// **The bright pass carries its brightness in *coverage*, not in colour.** The threshold pass
    /// scales the whole premultiplied texel by how far the pixel's `Lum` sits above the threshold, so a
    /// pixel just over the line contributes a faint, mostly-transparent glow and one at full white
    /// contributes all of itself. That is what makes the blur that follows spread the glow correctly:
    /// convolving premultiplied values weights each contribution by its own coverage, which is exactly
    /// the "how much light is here" the combine pass then adds.
    ///
    /// Additive rather than screen or lighten, because a glow is light arriving on top of the image and
    /// addition is what light does. The combine pass clamps and then re-imposes `rgb <= a`, since an
    /// additive result can otherwise leave the premultiplied invariant and make a later unpremultiply
    /// produce a colour above 1.
    struct Bloom: Equatable {
        /// `Lum` above which a pixel starts to glow. 1 means nothing glows; 0 means everything does.
        var threshold: Double = 0.75
        /// The glow's reach, in pixels — the same radius `Blur` takes, resolved the same way.
        var radius: Double = 8
        /// How much of the blurred bright pass is added back. 0 is the identity.
        var intensity: Double = 1
    }

    /// No knobs today — the divisor that keeps the magnitude from clipping is a resolved constant
    /// (`Effect.params`), not an artist-facing number. Kept as a struct anyway, for the same reason
    /// every other case is a struct rather than a bare case: a later knob (a mix, a threshold) is then
    /// a field here and a parameter change, not a new case.
    struct Sobel: Equatable {}

    /// The blur half is **exactly** `Effect.blur(Blur(radius: radius))` — same `gaussianHalfKernel`,
    /// same σ = radius/3, same 128-tap cap — which is the load-bearing fact `weights` states in code
    /// and two tests in `EffectMultiPassLogicTests` pin: that the kernel is shared rather than re-typed,
    /// and that `amount: −1` reproduces the plain blur byte for byte (`x + (−1)(x − blur) ≡ blur`).
    ///
    /// **The combine sharpens the whole premultiplied vector, alpha included** — the same shape
    /// `bloomCombine` already has (its two operands are this effect's blurred pass and its own
    /// `original`, clamped and re-imposed the same way) rather than a colour-only combine that would
    /// need the gather kernel to unpremultiply itself. That crisps the silhouette along with the
    /// colour, which is why this is one of the effects `reshapesCoverage` names; an artist who wants
    /// colour-only sharpening with the alpha left soft is a mode this effect does not yet offer.
    struct Sharpen: Equatable {
        /// Pixels — same meaning as `Blur.radius`. 0 makes the blur pass-through, so `amount` cannot
        /// do anything either: see `taps == 0` in `blur1D`.
        var radius: Double = 0
        /// How much of `original − blur` is added back. 0 is the identity for any radius. Negative is
        /// reachable here even before a UI admits it, because `amount: −1` is the strongest cheap test
        /// this effect has — it ties a brand-new combine to the blur kernel already proven by
        /// `EffectMultiPassLogicTests`' impulse-response and separable-vs-direct checks.
        var amount: Double = 0
    }

    /// A stroke painted where alpha is absent within `width` of alpha that is present — §7's "distance
    /// field around alpha". **Outside mode only**: a pixel already part of the shape (`alpha >
    /// threshold`) is left byte-for-byte unchanged, and a pixel outside it within `width` becomes fully
    /// opaque `color`, replacing whatever partial coverage was there.
    ///
    /// `threshold` is the same binary-with-a-threshold shape §6.3's `MaskResolver` uses: one comparison
    /// resolved the same way by both backends rather than a soft ramp, so an alpha sitting exactly on
    /// the line reads as the same side everywhere.
    struct Outline: Equatable {
        /// Pixels, Euclidean. **Capped by `Effect.maxOutlineRadius`, not `Effect.maxBlurTaps`** — a
        /// disc gather is `O((2r+1)²)`, not `O(r)`, so a blur's cap would be a hang waiting to happen.
        var width: Double = 1
        var color: CodableColor = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
        /// The alpha above which a pixel counts as "in the shape". 0.5 is the usual choice for content
        /// that already anti-aliases its own edge.
        var threshold: Double = 0.5
    }

    /// Which screen `Posterize` offsets its quantizer with. **Codes must match `kScreen…` in
    /// `Composite.metal`.**
    enum Screen: String, Codable, Equatable, CaseIterable {
        case none
        case ordered
        case halftone

        var code: UInt32 {
            switch self {
            case .none:     return 0
            case .ordered:  return 1
            case .halftone: return 2
            }
        }
    }
}

/// One knot of a tone curve, both coordinates in `[0, 1]`.
///
/// The one type in this file with a synthesized `Codable`, and deliberately: a point with a missing
/// coordinate is not an older format to be defaulted, it is a corrupt one, so failing to decode is
/// the correct behaviour rather than the thing the `decodeIfPresent` recipe protects against.
struct CurvePoint: Equatable, Codable {
    var x: Double
    var y: Double
}

/// One stop of a gradient map. `CodableColor` rather than a new colour type because the manifest
/// already speaks it (`ProjectManifest.backgroundColor`).
struct GradientStop: Equatable, Codable {
    var position: Double
    var color: CodableColor
}

// MARK: - What the kernels are given

/// The flat parameter block both backends receive, mirrored field for field by `EffectParams` in
/// `Composite.metal`.
///
/// **Every field is a 4-byte scalar, and that is the layout rule rather than an accident.** A
/// `float2` or a `packed_float3` in a Metal struct has alignment a Swift `SIMD2<Float>` matches only
/// by luck, and a silent padding disagreement between the two declarations shifts every field after
/// it — which does not fail to compile, it renders a different picture. All-scalar means the two
/// declarations agree if they list the same names in the same order, which is a property a reader can
/// check by eye.
///
/// One block for every effect rather than one per effect, for the reason §5.1 gives about blend modes:
/// a single `switch` in a single kernel means adding an effect is a case and a parameter, with no new
/// pipeline, no new binding, and nothing for the compositor to register.
struct EffectParams: Equatable {
    var brightness: Float = 1
    var contrast: Float = 1
    var hueTurns: Float = 0
    var saturation: Float = 1
    var value: Float = 1
    /// **A displacement in pixels, shared by the two effects that need one** — chromatic aberration's
    /// per-channel offset and a blur pass's per-tap step. One field rather than two that would mean the
    /// same thing, and the reason a blur pass needs no "which pass am I" flag at all: the step vector
    /// *is* the pass's identity.
    var offsetX: Float = 0
    var offsetY: Float = 0
    var mix: Float = 1
    var levels: Float = 2
    var screenStrength: Float = 0
    var amount: Float = 0
    /// The `Lum` above which a bloom's threshold pass starts letting light through.
    var threshold: Float = 0
    /// How much of the blurred bright pass a bloom's combine pass adds back.
    var intensity: Float = 0
    var screen: UInt32 = 0
    var seed: UInt32 = 0
    var isMonochrome: UInt32 = 0
    /// Half-kernel size for a blur pass: `taps` weights on each side of the centre, so `2 * taps + 1`
    /// samples. 0 is a single centre tap, which is the identity.
    var taps: UInt32 = 0
    /// **Appended at the end, deliberately** — Outline's stroke colour. The all-scalar layout rule
    /// (this struct's own doc) makes the end of the block the one position where adding fields cannot
    /// shift any existing one; anywhere else would silently corrupt every field after it, for every
    /// effect shipping today. No effect before this one has needed a colour of its own.
    var colorR: Float = 0
    var colorG: Float = 0
    var colorB: Float = 0
}

/// One dispatch of `applyEffect` — **the unit both backends iterate, and the whole of what "multi-pass"
/// means here.**
///
/// A pass is a kernel branch and the parameters it runs with, and nothing else: no texture, no index,
/// no reference to the effect that produced it. That is deliberate and is what keeps the encode path
/// uniform — the backend, not the pass, decides which texture a pass reads and writes, by the fixed
/// rule that pass *n* reads pass *n−1*'s output. A pass that needs the effect's *original* input as
/// well (bloom's combine) gets it from a binding that is constant for the whole effect, so even that
/// case adds no field here.
///
/// **There is no pass index in this struct, on purpose.** The obvious design gives each pass an
/// ordinal and has the kernel switch on it; the two blur passes then differ by a branch rather than by
/// data, and every later multi-pass effect has to invent its own meaning for the same integer. Stating
/// the difference as the step vector the pass convolves along means the kernel has one blur case, the
/// horizontal and vertical passes are the same code with different numbers, and a directional blur —
/// which is neither of them — needs nothing new.
struct EffectPass: Equatable {
    var kind: UInt32
    var params: EffectParams
}

extension Effect {

    /// Which branch of `applyEffect`'s switch runs. **Must match the `kEffect…` constants in
    /// `Composite.metal`, case for case**, and is covered the way `BlendMode.shaderCode` is — by
    /// `EffectParityLogicTests` running every effect through both backends, where a wrong code shows
    /// up as one effect rendering as another rather than as a compile error.
    ///
    /// **Levels and Curves share a code.** Both resolve to the same per-channel table and the kernel
    /// has no way to tell them apart, which is the point of resolving them here: a third curve shape
    /// later is a new case in this file and no shader change at all.
    ///
    /// **For a multi-pass effect this is pass 0's kind**, not a summary of the whole thing —
    /// `passes[0] == EffectPass(kind: kindCode, params: params)` is an invariant, asserted by
    /// `EffectMultiPassLogicTests`. A one-pass effect is therefore still fully described by this and
    /// `params`, which is why neither had to change meaning when multi-pass arrived.
    var kindCode: UInt32 {
        switch self {
        case .levels, .curves:     return 0
        case .brightnessContrast:  return 1
        case .hsvShift:            return 2
        case .gradientMap:         return 3
        case .chromaticAberration: return 4
        case .posterize:           return 5
        case .noise:               return 6
        case .blur:                return 7
        // Pass 0 of a bloom is its threshold; the blur and combine codes are reached through `passes`.
        case .bloom:               return 8
        case .sobel:               return 10
        // Pass 0 of a sharpen is a blur pass — sharing blur's code precedented by Levels/Curves
        // sharing 0, and what makes `passes[0] == EffectPass(kind: kindCode, params: params)` (the
        // invariant this property exists to serve) hold without a wasted copy pass.
        case .sharpen:             return 7
        case .outline:             return 12
        }
    }

    /// This effect's parameters, flattened — pass 0's, for an effect with more than one. Effects fully
    /// resolved into `lookupTable` contribute nothing here beyond what the kernel needs after the
    /// lookup.
    var params: EffectParams {
        var p = EffectParams()
        switch self {
        case .levels, .curves:
            break
        case .brightnessContrast(let bc):
            p.brightness = Float(bc.brightness)
            p.contrast = Float(bc.contrast)
        case .hsvShift(let hsv):
            // Turns rather than degrees, because that is the unit `ColorMath` works in and the
            // conversion belongs on the side that has a `Double` to do it in.
            p.hueTurns = Float(hsv.hueDegrees / 360)
            p.saturation = Float(hsv.saturation)
            p.value = Float(hsv.value)
        case .gradientMap(let map):
            p.mix = Float(map.mix)
        case .chromaticAberration(let ca):
            p.offsetX = Float(ca.offsetX)
            p.offsetY = Float(ca.offsetY)
        case .posterize(let post):
            p.levels = Float(max(2, post.levels))
            p.screen = post.screen.code
            p.screenStrength = Float(post.screenStrength)
        case .noise(let noise):
            p.amount = Float(noise.amount)
            p.seed = noise.seed
            p.isMonochrome = noise.isMonochrome ? 1 : 0
        case .blur(let blur):
            p.taps = UInt32(Self.tapCount(forRadius: blur.radius))
            let step = blur.isDirectional
                ? SIMD2<Double>(cos(blur.angleDegrees * .pi / 180), sin(blur.angleDegrees * .pi / 180))
                : SIMD2<Double>(1, 0)
            p.offsetX = Float(step.x)
            p.offsetY = Float(step.y)
        case .bloom(let bloom):
            p.threshold = Float(min(max(bloom.threshold, 0), 1))
            p.intensity = Float(max(bloom.intensity, 0))
            p.taps = UInt32(Self.tapCount(forRadius: bloom.radius))
        case .sobel:
            // The divisor that peak-normalizes the magnitude without ever clipping it. Max |Gx| = 4
            // for input in [0, 1], but the true maximum of sqrt(Gx² + Gy²) over all binary 3×3
            // patterns is sqrt(20) ≈ 4.4721 (attained at Gx = 2, Gy = 4, a diagonal step — enumerated
            // over all 512 patterns rather than assumed). Dividing by 4 instead would clip a diagonal
            // edge by up to 12%; dividing by 8 never clips but reads a straight edge at 0.5, dimmer
            // than it needs to be. This is exactly the kind of constant a backend parity sweep cannot
            // see — both backends receive whatever `amount` Swift resolved — so it is recorded here
            // rather than as a shader literal, and `testTheSobelImpulseMatchesTheKnownGradientKernels`
            // states the expected bytes this produces.
            p.amount = Float(1.0 / 20.0.squareRoot())
        case .sharpen(let sharpen):
            p.taps = UInt32(Self.tapCount(forRadius: sharpen.radius))
            p.offsetX = 1
            p.offsetY = 0
            p.amount = Float(sharpen.amount)
        case .outline(let outline):
            // `amount` carries the (fractional) search radius rather than `taps`, which is a uint and
            // would truncate a non-integer width — the Euclidean comparison inside the kernel needs
            // the exact value, not its ceiling.
            p.amount = Float(min(max(outline.width, 0), Self.maxOutlineRadius))
            p.threshold = Float(min(max(outline.threshold, 0), 1))
            p.colorR = Float(min(max(outline.color.red, 0), 1))
            p.colorG = Float(min(max(outline.color.green, 0), 1))
            p.colorB = Float(min(max(outline.color.blue, 0), 1))
        }
        return p
    }

    /// **The pass list — one entry per dispatch, run in order, each fed the previous one's output.**
    ///
    /// Every per-pixel effect returns exactly one entry, and that is what keeps a single-pass effect
    /// from paying for this: one pass means no intermediate texture is allocated and the encode path is
    /// the single dispatch it was before multi-pass existed.
    ///
    /// A Gaussian blur is two entries whose only difference is the step vector — `(1, 0)` then
    /// `(0, 1)`. A directional blur is one entry stepping along its angle. Bloom is four: threshold,
    /// the two blur passes, then a combine that reads the effect's *original* input alongside the
    /// blurred bright pass. The combine is the one pass that needs a second texture, and it is bound
    /// for every pass rather than declared per pass, so nothing here has to describe it.
    var passes: [EffectPass] {
        let first = EffectPass(kind: kindCode, params: params)
        switch self {
        case .blur(let blur):
            // A directional blur is genuinely one convolution along one line; only the Gaussian is
            // separable into two, and the second pass differs from the first by two floats.
            guard !blur.isDirectional else { return [first] }
            var vertical = first
            vertical.params.offsetX = 0
            vertical.params.offsetY = 1
            return [first, vertical]

        case .bloom:
            var horizontal = first
            horizontal.kind = Self.kBlur1D
            horizontal.params.offsetX = 1
            horizontal.params.offsetY = 0
            var vertical = horizontal
            vertical.params.offsetX = 0
            vertical.params.offsetY = 1
            var combine = first
            combine.kind = Self.kBloomCombine
            return [first, horizontal, vertical, combine]

        case .sharpen:
            // `first` already IS the horizontal blur pass — its kind is 7 (shared with blur) and its
            // params already carry the step (1, 0), unlike bloom's pass 0, which is a threshold and so
            // has to be rebuilt into a blur pass from scratch.
            var vertical = first
            vertical.params.offsetX = 0
            vertical.params.offsetY = 1
            var combine = first
            combine.kind = Self.kSharpenCombine
            return [first, vertical, combine]

        default:
            return [first]
        }
    }

    /// The half-kernel weights a blur pass convolves with — `weights[0]` at the centre and
    /// `weights[i]` at `±i` steps, **normalized in `Double` so the full kernel sums to 1** before it is
    /// narrowed to `Float`.
    ///
    /// Resolved here for exactly the reason `lookupTable` is: the alternative is `exp` in both kernels,
    /// and a transcendental evaluated once by Metal with fast math on and once by libm is the kind of
    /// disagreement a parity sweep would then report as a blur bug. Neither backend computes a weight;
    /// both are handed the same floats and do a weighted sum. **Bound unconditionally**, one element
    /// long for the effects that do not convolve, so the binding contract does not vary by kind — the
    /// same rule `lookupTable` follows.
    var weights: [Float] {
        switch self {
        case .blur(let blur): return Self.gaussianHalfKernel(radius: blur.radius)
        case .bloom(let bloom): return Self.gaussianHalfKernel(radius: bloom.radius)
        // The exact same call `Effect.blur` makes at the same radius — not a re-derivation. Pinned by
        // `testSharpenSharesItsBlurKernelWithBlurAtTheSameRadius`, which is what would catch a copy
        // that quietly stopped being the same call.
        case .sharpen(let sharpen): return Self.gaussianHalfKernel(radius: sharpen.radius)
        default: return [1]
        }
    }

    /// `2 · maxBlurTaps + 1` samples per pass is the ceiling a blur's cost is measured against; see
    /// `Blur` for why the cap is a real limit rather than a defensive one.
    static let maxBlurTaps = 128

    /// The ceiling on `Outline.width`. **Bounds a quadratic-cost kernel, not a linear one** — a direct
    /// disc gather is `O((2r + 1)²)` reads per pixel, so `maxBlurTaps`'s 128 would be 66,049 reads per
    /// pixel here rather than 257. Chosen far more conservatively for that reason: at the ceiling this
    /// is still ~2,401 reads/pixel, already two orders of magnitude past a same-radius blur.
    static let maxOutlineRadius = 24.0

    private static func tapCount(forRadius radius: Double) -> Int {
        guard radius.isFinite, radius > 0 else { return 0 }
        return min(Int(radius.rounded()), maxBlurTaps)
    }

    /// `w[i] = exp(-i² / 2σ²)`, σ = radius/3, normalized so `w[0] + 2 Σ w[i] == 1`.
    ///
    /// A zero radius returns `[1]`, which makes the blur exactly the identity rather than nearly one —
    /// the single centre tap reproduces the texel it read, and the identity test can assert bytes.
    private static func gaussianHalfKernel(radius: Double) -> [Float] {
        let taps = tapCount(forRadius: radius)
        guard taps > 0 else { return [1] }
        let sigma = max(radius / 3, 1e-4)
        let denominator = 2 * sigma * sigma
        let unnormalized = (0...taps).map { exp(-Double($0 * $0) / denominator) }
        let total = unnormalized[0] + 2 * unnormalized.dropFirst().reduce(0, +)
        return unnormalized.map { Float($0 / total) }
    }

    /// **Must match the `kEffect…` constants in `Composite.metal` and `EffectReference`**, the same
    /// contract `kindCode` carries — named here because `passes` reaches two branches no `kindCode`
    /// ever returns.
    private static let kBlur1D: UInt32 = 7
    private static let kBloomCombine: UInt32 = 9
    private static let kSharpenCombine: UInt32 = 11

    /// 256 RGBA entries, 1024 bytes — the resolved transfer table, and **the only form a curve reaches
    /// either backend in**.
    ///
    /// Bound unconditionally, with an identity ramp for the effects that do not read it, so the
    /// kernel's binding contract does not vary by kind. 1 KB per dispatch is inside `setBytes`' 4 KB
    /// limit and below the noise floor of a canvas-sized read.
    ///
    /// Indexed by channel for Levels and Curves (`out.r = lut[in.r].r`) and by luminance for Gradient
    /// Map (`out = lut[Lum(c)]`) — the same 1 KB serving two indexing rules, which is what makes
    /// per-channel curves a later parameter change rather than a later kernel.
    var lookupTable: [UInt8] {
        switch self {
        case .levels(let levels):
            return Self.table { levels.transfer($0) }
        case .curves(let curves):
            let interpolant = MonotoneCubic(points: curves.points)
            return Self.table { interpolant.value(at: $0) }
        case .gradientMap(let map):
            return Self.gradientTable(map.stops)
        default:
            return Self.identityTable
        }
    }

    /// A table whose three colour channels all carry `transfer`, sampled at `i / 255`.
    private static func table(_ transfer: (Double) -> Double) -> [UInt8] {
        var bytes = [UInt8](repeating: 255, count: 1024)
        for i in 0..<256 {
            let value = UInt8((min(max(transfer(Double(i) / 255), 0), 1) * 255).rounded())
            bytes[i * 4] = value
            bytes[i * 4 + 1] = value
            bytes[i * 4 + 2] = value
        }
        return bytes
    }

    /// The gradient sampled at 256 evenly spaced positions, linear between stops.
    ///
    /// An empty or single-stop gradient is a flat colour rather than an error, and an unsorted stop
    /// list is sorted here — both because a manifest is not a place to require an invariant that the
    /// UI could break and the document then fail to open (§6.6's "show the artwork" direction).
    private static func gradientTable(_ stops: [GradientStop]) -> [UInt8] {
        let sorted = stops.sorted { $0.position < $1.position }
        guard let first = sorted.first else { return identityTable }
        var bytes = [UInt8](repeating: 255, count: 1024)
        for i in 0..<256 {
            let t = Double(i) / 255
            var colour = first.color
            if let upper = sorted.firstIndex(where: { $0.position >= t }) {
                if upper == 0 {
                    colour = sorted[0].color
                } else {
                    let low = sorted[upper - 1], high = sorted[upper]
                    let span = high.position - low.position
                    let f = span > 0 ? (t - low.position) / span : 0
                    colour = CodableColor(red: low.color.red + (high.color.red - low.color.red) * f,
                                          green: low.color.green + (high.color.green - low.color.green) * f,
                                          blue: low.color.blue + (high.color.blue - low.color.blue) * f,
                                          alpha: 1)
                }
            } else {
                colour = sorted[sorted.count - 1].color
            }
            bytes[i * 4] = UInt8((min(max(colour.red, 0), 1) * 255).rounded())
            bytes[i * 4 + 1] = UInt8((min(max(colour.green, 0), 1) * 255).rounded())
            bytes[i * 4 + 2] = UInt8((min(max(colour.blue, 0), 1) * 255).rounded())
        }
        return bytes
    }

    /// `lut[i] == i` on every channel, so an effect that does not use the table cannot be changed by
    /// whatever happened to be bound.
    static let identityTable: [UInt8] = table { $0 }
}

extension Effect.Levels {

    /// The transfer function, on one channel. Guards rather than clamps: an inverted or collapsed
    /// input range and a non-positive gamma are all reachable from a UI that lets two sliders cross,
    /// and none of them should produce a NaN in a texture.
    func transfer(_ c: Double) -> Double {
        let span = inputWhite - inputBlack
        let normalized = span != 0 ? (c - inputBlack) / span : (c >= inputWhite ? 1 : 0)
        let clamped = min(max(normalized, 0), 1)
        let curved = gamma > 0 ? pow(clamped, 1 / gamma) : clamped
        return outputBlack + curved * (outputWhite - outputBlack)
    }
}

// MARK: - Monotone cubic interpolation

/// Fritsch–Carlson monotone cubic Hermite interpolation — see `Effect.Curves` for why a tone curve
/// needs the shape-preserving variant rather than a natural spline.
///
/// Not fileprivate: `EffectParityLogicTests` asserts monotonicity directly, which is the property the
/// whole choice of interpolant is about and is not observable through a 256-entry table alone.
struct MonotoneCubic {

    private let xs: [Double]
    private let ys: [Double]
    private let slopes: [Double]

    init(points: [CurvePoint]) {
        // Duplicate x values would divide by zero in the secant; the later one wins, which is what
        // dragging one control point onto another looks like in every curve UI.
        var sorted = points.sorted { $0.x < $1.x }
        sorted = sorted.enumerated().filter { $0.offset == sorted.count - 1 || sorted[$0.offset + 1].x != $0.element.x }
            .map(\.element)
        xs = sorted.map(\.x)
        ys = sorted.map(\.y)

        guard xs.count > 1 else {
            slopes = xs.isEmpty ? [] : [0]
            return
        }
        var secants: [Double] = []
        for k in 0..<(xs.count - 1) { secants.append((ys[k + 1] - ys[k]) / (xs[k + 1] - xs[k])) }

        var m = [Double](repeating: 0, count: xs.count)
        m[0] = secants[0]
        m[xs.count - 1] = secants[secants.count - 1]
        for k in 1..<(xs.count - 1) { m[k] = (secants[k - 1] + secants[k]) / 2 }

        // The Fritsch–Carlson limiter: a tangent longer than three times the secant is what produces
        // the overshoot, so the pair is scaled back onto the circle of radius 3.
        for k in 0..<secants.count {
            if secants[k] == 0 {
                m[k] = 0
                m[k + 1] = 0
                continue
            }
            let a = m[k] / secants[k], b = m[k + 1] / secants[k]
            let magnitude = a * a + b * b
            if magnitude > 9 {
                let tau = 3 / magnitude.squareRoot()
                m[k] = tau * a * secants[k]
                m[k + 1] = tau * b * secants[k]
            }
        }
        slopes = m
    }

    /// The curve at `x`, holding flat outside the control points' span.
    func value(at x: Double) -> Double {
        guard let firstX = xs.first, let lastX = xs.last else { return x }
        if x <= firstX { return ys[0] }
        if x >= lastX { return ys[ys.count - 1] }

        var k = 0
        while k < xs.count - 2 && xs[k + 1] < x { k += 1 }
        let h = xs[k + 1] - xs[k]
        let t = (x - xs[k]) / h
        let t2 = t * t, t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * ys[k]
            + (t3 - 2 * t2 + t) * h * slopes[k]
            + (-2 * t3 + 3 * t2) * ys[k + 1]
            + (t3 - t2) * h * slopes[k + 1]
    }
}

// MARK: - Persistence
//
// §4.4's effects are not persisted by anything yet — the two wrappers are what own a stored effect,
// and neither exists. The format is settled here anyway, because the wrappers are what a later phase
// adds and a format decided under that deadline is the one that gets a migration written for it.
//
// **The recipe is `FolderManifest.alphaMask`'s, unchanged**: an owner declares `var effect: Effect?`,
// decodes it with `decodeIfPresent` (nil means "no effect", which is also what every project saved
// before effects existed says), and encodes it only when it is there — so a document with no effect in
// it is byte-for-byte the manifest it was. Nothing needs a migration and nothing reads an *absence* as
// a signal, which is the one thing `FolderManifest.opacity` does differently and the reason it has to
// keep being written unconditionally.

extension Effect: Codable {

    /// `{"kind": …, "params": {…}}`, hand-written for `MaskSource`'s reason: a synthesized payload case
    /// encodes as `{"levels":{"_0":{…}}}`, whose inner key is a compiler implementation detail rather
    /// than a format anyone would choose to migrate later.
    private enum CodingKeys: String, CodingKey { case kind, params }

    private enum Kind: String, Codable {
        case levels, curves, brightnessContrast, hsvShift, gradientMap, chromaticAberration,
             posterize, noise, blur, bloom, sobel, sharpen, outline
    }

    private var kind: Kind {
        switch self {
        case .levels:              return .levels
        case .curves:              return .curves
        case .brightnessContrast:  return .brightnessContrast
        case .hsvShift:            return .hsvShift
        case .gradientMap:         return .gradientMap
        case .chromaticAberration: return .chromaticAberration
        case .posterize:           return .posterize
        case .noise:               return .noise
        case .blur:                return .blur
        case .bloom:               return .bloom
        case .sobel:               return .sobel
        case .sharpen:             return .sharpen
        case .outline:             return .outline
        }
    }

    /// `params` is itself `decodeIfPresent`, so an effect written as `{"kind":"levels"}` — which is
    /// what an all-defaults effect could reasonably be encoded as by a later version — decodes into
    /// the defaults rather than failing. Each parameter struct then applies the same rule field by
    /// field, so a knob added in a future phase is absent, not fatal, in every document written before
    /// it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func params<T: Decodable>(_ type: T.Type, _ fallback: T) throws -> T {
            try container.decodeIfPresent(type, forKey: .params) ?? fallback
        }
        switch try container.decode(Kind.self, forKey: .kind) {
        case .levels:              self = .levels(try params(Levels.self, Levels()))
        case .curves:              self = .curves(try params(Curves.self, Curves()))
        case .brightnessContrast:  self = .brightnessContrast(try params(BrightnessContrast.self, BrightnessContrast()))
        case .hsvShift:            self = .hsvShift(try params(HSVShift.self, HSVShift()))
        case .gradientMap:         self = .gradientMap(try params(GradientMap.self, GradientMap()))
        case .chromaticAberration: self = .chromaticAberration(try params(ChromaticAberration.self, ChromaticAberration()))
        case .posterize:           self = .posterize(try params(Posterize.self, Posterize()))
        case .noise:               self = .noise(try params(Noise.self, Noise()))
        case .blur:                self = .blur(try params(Blur.self, Blur()))
        case .bloom:               self = .bloom(try params(Bloom.self, Bloom()))
        case .sobel:               self = .sobel(try params(Sobel.self, Sobel()))
        case .sharpen:             self = .sharpen(try params(Sharpen.self, Sharpen()))
        case .outline:             self = .outline(try params(Outline.self, Outline()))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .levels(let p):              try container.encode(p, forKey: .params)
        case .curves(let p):              try container.encode(p, forKey: .params)
        case .brightnessContrast(let p):  try container.encode(p, forKey: .params)
        case .hsvShift(let p):            try container.encode(p, forKey: .params)
        case .gradientMap(let p):         try container.encode(p, forKey: .params)
        case .chromaticAberration(let p): try container.encode(p, forKey: .params)
        case .posterize(let p):           try container.encode(p, forKey: .params)
        case .noise(let p):               try container.encode(p, forKey: .params)
        case .blur(let p):                try container.encode(p, forKey: .params)
        case .bloom(let p):               try container.encode(p, forKey: .params)
        case .sobel(let p):               try container.encode(p, forKey: .params)
        case .sharpen(let p):             try container.encode(p, forKey: .params)
        case .outline(let p):             try container.encode(p, forKey: .params)
        }
    }
}

// Every parameter struct below decodes each field with `decodeIfPresent` and encodes synthesized —
// the asymmetry is the point. A synthesized *decoder* demands every key, so a property's default is
// not a fallback for a missing one (`LayerManifest`'s comment says the same); a synthesized *encoder*
// writes them all, which is what a reader of the file wants and costs a few dozen bytes per effect.

extension Effect.Levels: Codable {
    private enum CodingKeys: String, CodingKey { case inputBlack, inputWhite, gamma, outputBlack, outputWhite }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputBlack = try c.decodeIfPresent(Double.self, forKey: .inputBlack) ?? 0
        inputWhite = try c.decodeIfPresent(Double.self, forKey: .inputWhite) ?? 1
        gamma = try c.decodeIfPresent(Double.self, forKey: .gamma) ?? 1
        outputBlack = try c.decodeIfPresent(Double.self, forKey: .outputBlack) ?? 0
        outputWhite = try c.decodeIfPresent(Double.self, forKey: .outputWhite) ?? 1
    }
}

extension Effect.Curves: Codable {
    private enum CodingKeys: String, CodingKey { case points }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = try c.decodeIfPresent([CurvePoint].self, forKey: .points)
            ?? [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]
    }
}

extension Effect.BrightnessContrast: Codable {
    private enum CodingKeys: String, CodingKey { case brightness, contrast }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 1
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 1
    }
}

extension Effect.HSVShift: Codable {
    private enum CodingKeys: String, CodingKey { case hueDegrees, saturation, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hueDegrees = try c.decodeIfPresent(Double.self, forKey: .hueDegrees) ?? 0
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 1
        value = try c.decodeIfPresent(Double.self, forKey: .value) ?? 1
    }
}

extension Effect.GradientMap: Codable {
    private enum CodingKeys: String, CodingKey { case stops, mix }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stops = try c.decodeIfPresent([GradientStop].self, forKey: .stops) ?? Effect.GradientMap().stops
        mix = try c.decodeIfPresent(Double.self, forKey: .mix) ?? 1
    }
}

extension Effect.ChromaticAberration: Codable {
    private enum CodingKeys: String, CodingKey { case offsetX, offsetY }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offsetX = try c.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0
        offsetY = try c.decodeIfPresent(Double.self, forKey: .offsetY) ?? 0
    }
}

extension Effect.Posterize: Codable {
    private enum CodingKeys: String, CodingKey { case levels, screen, screenStrength }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        levels = try c.decodeIfPresent(Int.self, forKey: .levels) ?? 4
        screen = try c.decodeIfPresent(Effect.Screen.self, forKey: .screen) ?? .none
        screenStrength = try c.decodeIfPresent(Double.self, forKey: .screenStrength) ?? 0
    }
}

extension Effect.Noise: Codable {
    private enum CodingKeys: String, CodingKey { case amount, isMonochrome, seed }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        isMonochrome = try c.decodeIfPresent(Bool.self, forKey: .isMonochrome) ?? true
        seed = try c.decodeIfPresent(UInt32.self, forKey: .seed) ?? 1
    }
}

extension Effect.Blur: Codable {
    private enum CodingKeys: String, CodingKey { case radius, angleDegrees, isDirectional }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? 0
        angleDegrees = try c.decodeIfPresent(Double.self, forKey: .angleDegrees) ?? 0
        isDirectional = try c.decodeIfPresent(Bool.self, forKey: .isDirectional) ?? false
    }
}

extension Effect.Bloom: Codable {
    private enum CodingKeys: String, CodingKey { case threshold, radius, intensity }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threshold = try c.decodeIfPresent(Double.self, forKey: .threshold) ?? 0.75
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? 8
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 1
    }
}

extension Effect.Sobel: Codable {
    // No fields yet — a synthesized `Decodable` on an empty struct still needs an explicit
    // `init(from:)` that does not require a keyed container, so a bare `{"kind":"sobel"}` decodes.
    init(from decoder: Decoder) throws {}
}

extension Effect.Sharpen: Codable {
    private enum CodingKeys: String, CodingKey { case radius, amount }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? 0
        amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0
    }
}

extension Effect.Outline: Codable {
    private enum CodingKeys: String, CodingKey { case width, color, threshold }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 1
        color = try c.decodeIfPresent(CodableColor.self, forKey: .color)
            ?? CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
        threshold = try c.decodeIfPresent(Double.self, forKey: .threshold) ?? 0.5
    }
}
