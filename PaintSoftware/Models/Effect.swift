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
// the five that answer true are pinned instead on the property that actually matters for them, which is
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
    /// exercises exactly what a painted line-art edge needs. The output is `(m, m, m, a)` clamped to
    /// `rgb <= a`, where `m` is the normalized magnitude and `a` is the coverage the kernel was handed:
    /// an edge map over whatever image it was given, opaque exactly where that image was. It replaces
    /// the image rather than being mixed over it — see `reshapesCoverage`.
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
    /// Sobel replaces the image with an edge map, sharpen's combine operates on the full premultiplied
    /// vector exactly as bloom's does, and an outline by definition paints coverage where the shape had
    /// none.
    ///
    /// **Sobel's `true` became conservative rather than descriptive on 2026-08-27, and is left that
    /// way deliberately.** It now writes back the coverage it was handed (`sobel` in either backend),
    /// so its alpha out equals its alpha in on every fixture and it does not in fact move coverage.
    /// It stays `true` because what answers false here is pinned byte-for-byte on alpha as a *grade* —
    /// something that regrades what is there without replacing it — and an edge map is not one.
    /// Moving it is a ruling of its own, not a consequence of deleting a control.
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

    /// **Which image an effect is handed** — EFFECT_BACKDROP.md §4.
    ///
    /// Until 2026-08-27 there was only one answer and so no property: the live canvas painted the
    /// paper as a `UIView` behind the composite, so every effect graded an accumulator that was
    /// transparent wherever the artist had not painted, and every kernel correctly short-circuited on
    /// alpha 0. That is BUGS.md's *"Every effect and blend mode is masked to the layer's own ink"* —
    /// the kernels were right and the input was wrong. Once the paper is in the accumulator the
    /// question becomes real, because three effects read the accumulator's alpha as **coverage** and
    /// filling paper into it destroys that information.
    enum Input: String, Codable, Equatable, CaseIterable {
        /// Everything below this node, paper included. What a grade wants: a brightness layer over a
        /// white canvas should brighten the canvas.
        case backdrop
        /// Everything below this node with the paper left out — the sub-walk re-run into a fresh
        /// transparent buffer (EFFECT_BACKDROP.md §3 option A), so alpha still means coverage.
        case ink
    }

    /// The §4 table in code. **Exhaustive with no `default:`, deliberately**, for the reason
    /// CLAUDE.md records three times over in `CanvasManager`'s history: a hand-maintained list of
    /// exceptions rots, and a fourteenth effect added later must be *forced* to answer this question
    /// rather than inherit an answer that happens to be wrong for it. `reshapesCoverage` above takes
    /// the other bargain — it has a `default:` — and is the reason this one does not.
    ///
    /// **Nine grades read colour and take the backdrop.** Levels, Curves, Brightness/Contrast, HSV
    /// Shift, Gradient Map, Posterize, Noise and Chromatic Aberration have nothing to say about
    /// shape; Blur convolves premultiplied values and blurring uniform paper is the identity, so an
    /// opaque backdrop changes almost nothing about it.
    ///
    /// **Sharpen is the tenth, and §4's table does not name it** — it lists twelve of the thirteen
    /// cases. `.backdrop` is the answer that needs no new behaviour and is right on its own terms:
    /// sharpen is `x + amount·(x − blur_r(x))`, whose second term is zero across flat paper, so a
    /// uniform backdrop is the identity for it exactly as it is for the blur it is built on.
    ///
    /// **Three read shape instead of colour**, which is why they are here at all:
    /// - **Outline** keys on `src.a > threshold`, so over an opaque backdrop that is true everywhere
    ///   and there is no silhouette left to trace. `.ink` is fixed, not a default — `.backdrop` would
    ///   not be a mode, it would be a no-op.
    /// - **Bloom** thresholds luminance, and white paper is Lum 1.0, so paper-inclusive bloom makes
    ///   the whole canvas a source. Ruled the artist's choice, **defaulting to `.ink`** — which is
    ///   the shipped look, so nothing visibly changes.
    /// - **Sobel** convolves, and it takes the backdrop — **fixed, and with no control**. It writes
    ///   back the coverage it was handed, so over the paper the flat regions are opaque black and the
    ///   edges are bright: what an edge detector conventionally is. That is a change to what ships and
    ///   an artist with a Sobel layer in an open document will see it. It joins the literal list below
    ///   rather than getting a case of its own, even though it reads shape rather than colour, because
    ///   the answer is a constant again.
    ///
    ///   **It had an artist-facing `.ink` setting for a few hours on 2026-08-27 and the owner deleted
    ///   it the same day**: *"drop it. Remember to cleanly remove and delete the feature so no remnants
    ///   of it are left in the code."* EFFECT_BACKDROP.md §5.2 keeps the superseded ruling and §2.2 the
    ///   two measurements that killed it — `(m,m,m,m)` over white paper composites to
    ///   `m·255 + 255(1−m) = 255` for **every** m, so an ink-only Sobel is arithmetically invisible on
    ///   the default paper whatever colour the ink is; and the kernel reads *premultiplied* rgb, so
    ///   black ink is `(0,0,0)` inside the stroke and `(0,0,0)` outside it and an ink-only Sobel finds
    ///   **zero** edges in black line art. The setting was near-useless for the two commonest documents
    ///   there are.
    ///
    /// Bloom's is the one answer here that is the artist's stored choice rather than a fixed one
    /// (EFFECT_BACKDROP.md §6 step 5) — it reads its own `Bloom.input` field, seeded with the ruled
    /// default above, which is why it binds its associated value rather than joining the literal list.
    var input: Input {
        switch self {
        case .levels, .curves, .brightnessContrast, .hsvShift, .gradientMap,
             .posterize, .noise, .chromaticAberration, .blur, .sharpen, .sobel:
            return .backdrop
        case .outline:
            return .ink
        case .bloom(let params):
            return params.input
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
        /// EFFECT_BACKDROP.md §4/§6 step 5 — the artist's choice of what Bloom sees. Defaults to
        /// `.ink`, which is today's shipped look, so a document saved before this field existed
        /// decodes into the same picture it already drew.
        var input: Effect.Input = .ink
    }

    /// **Sobel has no parameters at all, and the empty struct is the whole of it.** The divisor that
    /// keeps the magnitude from clipping is a resolved constant (`Effect.params`) rather than an
    /// artist-facing number, and the `input` field that lived here for a few hours on 2026-08-27 was
    /// deleted by the owner's ruling — `Effect.input`'s Sobel bullet carries the two measurements and
    /// EFFECT_BACKDROP.md §5.2 the superseded ruling it replaced.
    ///
    /// Kept as an empty struct rather than collapsed into a bare `case sobel`, for `Effect.Curves`'
    /// reason in reverse: the payload is where a knob goes if one is ever ruled, and adding a field is
    /// a smaller change than reshaping the enum and the `{"kind":…,"params":…}` every document writes.
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

    /// The gradient's colour at position `t`, on an already-sorted, non-empty stop list.
    ///
    /// **The one definition of what a stop list means.** `gradientTable` samples this at 256 evenly
    /// spaced positions to build the bytes both backends read, and `gradientRampStops` samples it
    /// wherever the settings-panel preview needs a stop, so the picture in the panel and the pixels
    /// on the canvas cannot drift apart the way they would if each had its own loop.
    ///
    /// **Between two stops the mix goes through Oklab, not through the RGB channels** — TODO item
    /// (10a), and the owner's complaint stated as code: *"RGB goes muddy through the middle between
    /// two saturated hues."* Lerping the three channels puts the middle of the ramp well below the
    /// lightness either end suggests, because the channel values are gamma-encoded. MEASURED on the
    /// 256 entries: orange-to-blue moves up to 60/255, green-to-magenta 70/255, red-to-cyan 79/255,
    /// and in every case the move is the middle of the ramp getting *lighter* — see
    /// `docs/oklab-ramps/`.
    ///
    /// **What it costs, stated because it is not free.** The default stop list is black to white, and
    /// a black-to-white gradient map used to be exactly "the pixel's own `Lum`, restated as a
    /// colour": entry 113 was (113, 113, 113). Through Oklab it is (83, 83, 83), because the entry
    /// whose *perceptual lightness* is 0.443 is darker than the byte 113. So a gradient map used to
    /// convert to greyscale now darkens the midtones by up to 31/255.
    ///
    /// **RULED BY THE OWNER 2026-08-30, shown `docs/oklab-ramps/02-the-cost.png`: apply it everywhere,
    /// greys included.** Offered the alternative — mix achromatic stop pairs the old way so a
    /// black-to-white gradient map stays an exact brightness conversion, one extra branch here — they
    /// took the uniform rule. **So the darkening is intended, not an oversight**; do not "fix" it, and
    /// do not add the special case back without asking. `EffectParityLogicTests`'
    /// `testGradientMapIndexesByTheSameLuminanceTheBlendModesUse` pins entry 113 at 83 and records the
    /// old value in its doc.
    private static func gradientColour(_ sorted: [GradientStop], at t: Double) -> CodableColor {
        guard let first = sorted.first else { return CodableColor(red: 0, green: 0, blue: 0, alpha: 1) }
        guard let upper = sorted.firstIndex(where: { $0.position >= t }) else {
            return sorted[sorted.count - 1].color
        }
        guard upper > 0 else { return first.color }

        let low = sorted[upper - 1].color, high = sorted[upper].color
        let span = sorted[upper].position - sorted[upper - 1].position
        let f = span > 0 ? (t - sorted[upper - 1].position) / span : 0
        let mixed = ColorMath.mixOklab((r: low.red, g: low.green, b: low.blue),
                                       (r: high.red, g: high.green, b: high.blue), f)
        return CodableColor(red: mixed.r, green: mixed.g, blue: mixed.b, alpha: 1)
    }

    /// The gradient sampled at 256 evenly spaced positions.
    ///
    /// An empty or single-stop gradient is a flat colour rather than an error, and an unsorted stop
    /// list is sorted here — both because a manifest is not a place to require an invariant that the
    /// UI could break and the document then fail to open (§6.6's "show the artwork" direction).
    ///
    /// **What the Oklab mix costs here, MEASURED** (`swiftc -O` on the host Mac, 20,000 builds):
    /// **34 µs** to build the whole table against 0.3 µs for the channel lerp it replaced. This runs
    /// once per effect encode, not per pixel, so at 24 fps with a gradient map on screen it is 0.8 ms
    /// of every second — no memo, and the reason (10a) is outside the performance conversation that
    /// (10b) is inside.
    private static func gradientTable(_ stops: [GradientStop]) -> [UInt8] {
        let sorted = stops.sorted { $0.position < $1.position }
        guard !sorted.isEmpty else { return identityTable }
        var bytes = [UInt8](repeating: 255, count: 1024)
        for i in 0..<256 {
            let colour = gradientColour(sorted, at: Double(i) / 255)
            bytes[i * 4] = UInt8((min(max(colour.red, 0), 1) * 255).rounded())
            bytes[i * 4 + 1] = UInt8((min(max(colour.green, 0), 1) * 255).rounded())
            bytes[i * 4 + 2] = UInt8((min(max(colour.blue, 0), 1) * 255).rounded())
        }
        return bytes
    }

    /// How many evenly spaced samples `gradientRampStops` lays down across the whole ramp.
    ///
    /// MEASURED over seven stop pairs, worst case, against the ramp `gradientColour` actually
    /// computes: 65 samples leave a UI gradient **7/255** away from the truth if it interpolates in
    /// sRGB components and 1/255 if it interpolates in linear light. Handing the two raw stops
    /// straight to `LinearGradient`, which is what the preview did before the ramp curved, is
    /// **85/255** away — a preview showing a muddy middle the canvas no longer has.
    static let gradientPreviewSampleCount = 65

    /// The stop list a straight-line UI gradient needs in order to draw the ramp these stops
    /// actually resolve to.
    ///
    /// A `LinearGradient` interpolates in a straight line between whatever stops it is given, so once
    /// the ramp between two stops stopped being a straight line the preview had to stop being two
    /// stops. This resamples: every position the artist placed a stop at (so the corners stay sharp
    /// exactly where the ramp bends) plus `sampleCount` evenly spaced positions across 0...1 (so each
    /// curved span is broken into pieces short enough for the straight lines to hide inside).
    ///
    /// Returns a single flat pair for the two degenerate lists, matching what `gradientTable`
    /// resolves them to — see `GradientStopsEditor.previewStops`, which used to own that rule.
    static func gradientRampStops(_ stops: [GradientStop],
                                  sampleCount: Int = gradientPreviewSampleCount) -> [GradientStop] {
        let sorted = stops.sorted { $0.position < $1.position }
        guard let first = sorted.first else {
            let black = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
            return [GradientStop(position: 0, color: black), GradientStop(position: 1, color: black)]
        }
        guard sorted.count > 1 else {
            return [GradientStop(position: 0, color: first.color),
                    GradientStop(position: 1, color: first.color)]
        }

        let n = max(sampleCount, 2)
        let grid = (0..<n).map { Double($0) / Double(n - 1) }
        let corners = sorted.map(\.position).filter { $0 > 0 && $0 < 1 }

        // The corners can land on the grid, and a duplicated location is a zero-width segment
        // SwiftUI has no use for.
        var positions: [Double] = []
        for p in (grid + corners).sorted() where positions.last.map({ p - $0 > 1e-9 }) ?? true {
            positions.append(p)
        }
        return positions.map { GradientStop(position: $0, color: gradientColour(sorted, at: $0)) }
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
    private enum CodingKeys: String, CodingKey { case threshold, radius, intensity, input }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threshold = try c.decodeIfPresent(Double.self, forKey: .threshold) ?? 0.75
        radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? 8
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 1
        // Absent means "saved before this field existed" — decodes to `.ink`, today's shipped look,
        // not the struct's own default literal repeated by coincidence (see `Sobel` below, where the
        // decode default and the ruled default are the same value for a different reason).
        input = try c.decodeIfPresent(Effect.Input.self, forKey: .input) ?? .ink
    }
}

/// **Empty, synthesized, and that synthesis is a compatibility guarantee rather than an omission.**
/// Sobel carried an `input` key for a few hours on 2026-08-27, so documents saved in that window hold
/// `{"kind":"sobel","params":{"input":"ink"}}`. A keyed container reads only the keys its `CodingKeys`
/// names, and an empty struct names none — so the stale key is ignored and the node decodes into the
/// one Sobel there is, rather than throwing and taking the artist's whole project down with it.
/// `testASobelSavedWithTheDeletedInputKeyStillDecodes` demonstrates that in this file's own two-step
/// decode path rather than trusting the language rule.
extension Effect.Sobel: Codable {}

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

// MARK: - The parameter table
//
// **KEYFRAMES.md §8 stage 1.** Until this table existed nothing in the app could *name* an effect
// parameter. Every knob lived as a literal inside `EffectSettingsBar.rows`' one `switch effect` —
// 25 `slider(...)` call sites, each hard-coding its own range, its own format and its own
// write-back — so "Bloom's intensity" was something an artist could drag and not something any
// other code could refer to. A keyframe track has to store *which* parameter it drives and a graph
// editor has to draw an axis for it, so both need an address. This is that address space, and
// `EffectSettingsBar.rows` now reads it rather than repeating it, so the two cannot drift.
//
// **The address is (effect case, field), and it is deliberately not `EffectParams`.** That struct
// looks like the flat parameter space this wants and cannot be it, for three separate reasons:
//
// * it is *derived* — a computed property with no setter, so there is nothing to write back through;
// * it is *lossy* — `case .levels, .curves: break`, so Levels' five sliders and the whole Curves
//   editor contribute nothing to it at all (they resolve into `lookupTable` instead) and Gradient
//   Map contributes only `mix`;
// * it is *aliased* — `offsetX`/`offsetY` are a per-channel displacement for Chromatic Aberration
//   and a per-tap step vector for a blur pass, and `amount` carries Noise's amount, Sharpen's
//   amount, Outline's *width* and Sobel's fixed `1/√20`. Four quantities, one name.
//
// Addressing through it would key the wrong thing, key nothing at all, or key two parameters at
// once depending on which effect happened to be under the playhead.

/// **How a keyframe curve carries one parameter between two keys.**
enum EffectParameterAnimation: String, Equatable {
    /// Tweened. Every value between the two keys is a value the model renders.
    case continuous
    /// **Held until the next key**, because there is no meaningful midpoint. Half a Bayer screen is
    /// not a screen and half of `true` is not a boolean.
    ///
    /// Two of the six are stepped for a stronger reason than "it is not a number": they change the
    /// *render shape* rather than a value. `Blur.isDirectional` rewrites `passes` from two entries
    /// to one, and `Bloom.input` decides whether the compositor performs an entire sub-walk into two
    /// borrowed textures (EFFECT_BACKDROP.md §3 option A). Neither is a quantity that could be
    /// blended even in principle.
    case stepped
    /// A variable-length list, tweened **element by element when the two keys have the same count
    /// and held when they do not** — the owner's ruling on KEYFRAMES.md §9 question 4. `Curves.points`
    /// and `GradientMap.stops` are the only two, and both are ordered lists whose *n*-th element has
    /// an obvious counterpart in another list of the same length and none at all otherwise.
    case componentwise
    /// Cannot be keyed at any step. **Nothing answers this today** and it is here so that a later
    /// parameter which genuinely cannot be animated — a file reference, a device-dependent handle —
    /// has an answer that is not `.stepped` chosen by default.
    case notAnimatable
}

/// The shape of the value behind a parameter. `EffectParameter.read`/`write` bridge the first five
/// to `Double`; the last three need a channel of their own.
enum EffectParameterValue: String, Equatable {
    case double
    case integer
    case boolean
    /// `Noise.seed`, a `UInt32`.
    case unsignedInteger
    /// A `CaseIterable` enum, bridged to its index in `allCases`.
    case option
    /// `Outline.color`. Tweened per channel — four continuous numbers wearing one name — which is
    /// why it is `.continuous` above rather than `.componentwise`: the count is fixed at four.
    case colour
    case curvePoints
    case gradientStops
}

/// Whether every value in `EffectParameter.modelDomain` renders distinctly.
enum EffectParameterQuantisation: String, Equatable {
    /// It does.
    case continuous
    /// The stored field is an `Int` or a `UInt32`, so the steps are the artist's own and the slider
    /// readout already shows them.
    case integral
    /// **The stored field is a `Double` and the render path rounds it anyway** — the trap this case
    /// exists to record. `Effect.tapCount` is `min(Int(radius.rounded()), maxBlurTaps)`, so radius
    /// 8.0 and radius 8.4 produce byte-identical output and a smoothly keyframed blur ramp renders
    /// as integer steps. It applies to all three radii that reach `tapCount` — `Blur.radius`,
    /// `Bloom.radius` and `Sharpen.radius` — not only the blur's.
    ///
    /// `Outline` sidesteps it and says so in `Effect.params`: it carries its fractional width in the
    /// `amount` float rather than in the `taps` uint, precisely because a uint would truncate it.
    /// A graph editor should say this about a channel rather than leave the artist to discover it.
    case roundedByTheRenderPath
}

/// **One addressable effect parameter.**
///
/// `EffectSettingsBar` builds its sliders from these, and a keyframe track stores `id`.
struct EffectParameter: Identifiable {

    /// **The persisted address, and the one field here that must never change.**
    ///
    /// `"<case>.<parameter>"`, lower-camel after the dot. A keyframe track stores this string and a
    /// saved document carries it, so it has to **survive a Swift rename**: renaming the enum case,
    /// the payload struct or the stored property must not change it, and if one of those renames
    /// makes this string look wrong, the string is what stays. It is decoupled from the field name
    /// on purpose and already differs from it twice — `hsvShift.hue` addresses `hueDegrees` and
    /// `blur.angle` addresses `angleDegrees` — which is the property working, not a mistake.
    let id: String

    /// The artist-facing label. The settings bar's row label for anything with a row.
    let name: String

    /// The suffix of this control's accessibility identifier in `EffectSettingsBar`, so the bar can
    /// take its `effectSettings.<x>` name from here rather than repeating it. Separate from `id`
    /// because the two answer different questions: `id` is what a saved document stores, this is
    /// what an XCUITest taps, and neither may be changed to make it match the other.
    ///
    /// Non-nil for every parameter that has a control today, which is all 33 of them.
    let controlIdentifier: String?

    let value: EffectParameterValue
    let animation: EffectParameterAnimation
    let quantisation: EffectParameterQuantisation

    /// **What the settings-bar slider offers, or nil where the control is not a slider.**
    /// Non-nil for exactly the 25 parameters `rows` draws a `Slider` for.
    let uiRange: ClosedRange<Double>?

    /// **Every value the model accepts and renders distinctly** — a different fact from `uiRange`,
    /// and wider than it far more often than not. `Effect.maxBlurTaps` is 128 while the radius
    /// slider stops at 64; `Sharpen.amount`'s slider starts at 0 while negative is deliberately
    /// reachable in the model and `amount: -1` is a pinned test identity (it reproduces a plain
    /// blur byte for byte). Most of the grades clamp nothing at all, and their domain is infinite.
    ///
    /// A graph editor should draw its Y axis over `uiRange` and *allow* a key anywhere in here.
    /// For a compound value these bound one component: one colour channel, one curve coordinate,
    /// one gradient stop's position.
    let modelDomain: ClosedRange<Double>

    /// The `String(format:)` the settings bar prints the live readout with, or nil for a
    /// non-slider. Carries the unit — `"%.1f px"`, `"%.0f°"`.
    let format: String?

    /// **The typed address**: a `WritableKeyPath<P, V>` where `P` is this case's payload struct.
    /// `read` and `write` below are built from it by the factories in `Effect.parameters`, so the
    /// two cannot disagree about which field this is.
    let keyPath: AnyKeyPath

    /// This parameter's value on `effect`, as a `Double` — nil if `effect` is a different case, or
    /// if the value is compound (`.colour`, `.curvePoints`, `.gradientStops`) and has no single
    /// number. An option reads as its index in `allCases`, a boolean as 0 or 1.
    let read: (Effect) -> Double?

    /// `effect` with this parameter set. Returns `effect` unchanged if it is a different case or
    /// the value is compound. Rounds and clamps the way the control does: an `Int` field takes
    /// `Int(v.rounded())`, an option index is clamped into `allCases`.
    let write: (Effect, Double) -> Effect
}

extension EffectParameter {
    /// The model clamps nothing, so the domain is every finite number. Used by the grades, whose
    /// transfer functions guard against degenerate values rather than restricting their inputs.
    static let unbounded: ClosedRange<Double> = (-.infinity)...(.infinity)
}

/// The pair that turns a key path *into a payload struct* into a read/write on a whole `Effect`.
///
/// An enum with associated values has no writable key paths of its own, which is the reason this
/// exists: `\Effect.Blur.radius` is a perfectly good `WritableKeyPath<Effect.Blur, Double>` and
/// there is no `\Effect.blur.radius`. One lens per case, built once inside that case's branch of
/// `Effect.parameters`, closes the gap for every parameter in it.
private struct EffectCaseLens<P> {
    let extract: (Effect) -> P?
    let embed: (P) -> Effect

    func parameter(_ id: String, _ name: String, _ control: String?,
                   value: EffectParameterValue,
                   animation: EffectParameterAnimation,
                   quantisation: EffectParameterQuantisation,
                   ui: ClosedRange<Double>?, model: ClosedRange<Double>, format: String?,
                   keyPath: AnyKeyPath,
                   read: @escaping (P) -> Double?,
                   write: @escaping (inout P, Double) -> Void) -> EffectParameter {
        EffectParameter(
            id: id, name: name, controlIdentifier: control, value: value,
            animation: animation, quantisation: quantisation,
            uiRange: ui, modelDomain: model, format: format, keyPath: keyPath,
            read: { extract($0).flatMap(read) },
            write: { effect, newValue in
                guard var payload = extract(effect) else { return effect }
                write(&payload, newValue)
                return embed(payload)
            })
    }

    /// A `Double` field — 24 of the 33, and every one of them `.continuous`.
    func double(_ id: String, _ name: String, _ control: String,
                _ keyPath: WritableKeyPath<P, Double>,
                ui: ClosedRange<Double>?, model: ClosedRange<Double>, format: String?,
                quantisation: EffectParameterQuantisation = .continuous) -> EffectParameter {
        parameter(id, name, control, value: .double, animation: .continuous,
                  quantisation: quantisation, ui: ui, model: model, format: format,
                  keyPath: keyPath,
                  read: { $0[keyPath: keyPath] },
                  write: { $0[keyPath: keyPath] = $1 })
    }

    /// An `Int` field. `Posterize.levels` is the only one, and it is `.stepped`: three levels and
    /// four levels are different pictures with nothing in between them.
    func integer(_ id: String, _ name: String, _ control: String,
                 _ keyPath: WritableKeyPath<P, Int>,
                 ui: ClosedRange<Double>?, model: ClosedRange<Double>, format: String?)
    -> EffectParameter {
        parameter(id, name, control, value: .integer, animation: .stepped,
                  quantisation: .integral, ui: ui, model: model, format: format,
                  keyPath: keyPath,
                  read: { Double($0[keyPath: keyPath]) },
                  // `Int(v.rounded())` is what the settings bar's Levels slider already does.
                  write: { $0[keyPath: keyPath] = Int($1.rounded()) })
    }

    func boolean(_ id: String, _ name: String, _ control: String,
                 _ keyPath: WritableKeyPath<P, Bool>) -> EffectParameter {
        parameter(id, name, control, value: .boolean, animation: .stepped,
                  quantisation: .integral, ui: nil, model: 0...1, format: nil,
                  keyPath: keyPath,
                  read: { $0[keyPath: keyPath] ? 1 : 0 },
                  write: { $0[keyPath: keyPath] = $1 >= 0.5 })
    }

    /// `Noise.seed`. The settings bar rerolls it with a button rather than a slider, and says why:
    /// *"A seed is not a quantity — nudging it by one is as different a grain as any other value"*.
    /// That is the same argument as `.stepped`, made about a number.
    func seed(_ id: String, _ name: String, _ control: String,
              _ keyPath: WritableKeyPath<P, UInt32>) -> EffectParameter {
        parameter(id, name, control, value: .unsignedInteger, animation: .stepped,
                  quantisation: .integral, ui: nil, model: 0...Double(UInt32.max), format: nil,
                  keyPath: keyPath,
                  read: { Double($0[keyPath: keyPath]) },
                  write: { $0[keyPath: keyPath] = UInt32(min(max($1.rounded(), 0),
                                                             Double(UInt32.max))) })
    }

    /// A `CaseIterable` enum, addressed by its index in `allCases`.
    func option<O>(_ id: String, _ name: String, _ control: String,
                   _ keyPath: WritableKeyPath<P, O>) -> EffectParameter
    where O: CaseIterable & Equatable, O.AllCases: RandomAccessCollection, O.AllCases.Index == Int {
        let cases = Array(O.allCases)
        assert(!cases.isEmpty, "An option parameter over an enum with no cases has no address space")
        return parameter(id, name, control, value: .option, animation: .stepped,
                         quantisation: .integral, ui: nil,
                         model: 0...Double(max(cases.count - 1, 0)), format: nil,
                         keyPath: keyPath,
                         read: { payload in
                             cases.firstIndex(of: payload[keyPath: keyPath]).map(Double.init)
                         },
                         write: { payload, newValue in
                             guard !cases.isEmpty else { return }
                             let index = Int(min(max(newValue.rounded(), 0),
                                                 Double(cases.count - 1)))
                             payload[keyPath: keyPath] = cases[index]
                         })
    }

    /// A value with no single number behind it — a colour, a list of curve points, a list of
    /// gradient stops. `read` returns nil and `write` is the identity, so a scalar channel cannot
    /// silently half-address one; these need a channel that speaks their own type.
    func compound(_ id: String, _ name: String, _ control: String,
                  value: EffectParameterValue,
                  animation: EffectParameterAnimation,
                  componentDomain: ClosedRange<Double>,
                  keyPath: AnyKeyPath) -> EffectParameter {
        parameter(id, name, control, value: value, animation: animation,
                  quantisation: .continuous, ui: nil, model: componentDomain, format: nil,
                  keyPath: keyPath,
                  read: { _ in nil },
                  write: { _, _ in })
    }
}

extension Effect {

    /// **Every parameter this effect has, in the order `EffectSettingsBar` shows them.**
    ///
    /// **Exhaustive, with no `default:`** — the same bargain `Effect.input` takes and the opposite
    /// of `reshapesCoverage`'s, and here it is load-bearing rather than stylistic. `Effect` cannot
    /// be `CaseIterable` (it has associated values) and every all-effects sweep in the suite is a
    /// hand-typed literal, so nothing else in this codebase would notice a fourteenth effect
    /// missing from this table. A `default:` would hand it an empty parameter list, its keyframe
    /// channels would silently not exist, and the first symptom would be an artist unable to
    /// animate a knob they can see.
    ///
    /// **Thirteen cases, fourteen menu entries.** Gaussian and Directional Blur are one case split
    /// by `Blur.isDirectional`, so they share one branch here and `blur.directional` is itself a
    /// parameter — which is the honest shape, since an artist can flip a Gaussian blur into a
    /// directional one without changing effect.
    ///
    /// **Depends only on the case, never on the values in it.** Two Blurs return the same table,
    /// and `blur.angle` is listed whether or not the blur is directional right now — the settings
    /// bar hides that row when it is not, but the *address* has to exist for a channel to be
    /// authored on it. Nothing here reads an associated value, which is why the branches bind
    /// nothing.
    var parameters: [EffectParameter] {
        switch self {

        case .levels:
            let l = EffectCaseLens<Levels>(extract: { if case .levels(let p) = $0 { return p }; return nil },
                                           embed: { .levels($0) })
            // The four endpoints clamp nowhere: `Levels.transfer` guards against a collapsed or
            // inverted range rather than restricting the knobs, and `Effect.table` clamps the
            // *byte* it writes, not the value it was given. So a key outside 0...1 is meaningful.
            return [
                l.double("levels.inputBlack", "Input Black", "inputBlack", \.inputBlack,
                         ui: 0...1, model: EffectParameter.unbounded, format: "%.2f"),
                l.double("levels.inputWhite", "Input White", "inputWhite", \.inputWhite,
                         ui: 0...1, model: EffectParameter.unbounded, format: "%.2f"),
                // `transfer` skips the power entirely when gamma <= 0, so the domain stops at 0.
                l.double("levels.gamma", "Gamma", "gamma", \.gamma,
                         ui: 0.1...5, model: 0...(.infinity), format: "%.2f"),
                l.double("levels.outputBlack", "Output Black", "outputBlack", \.outputBlack,
                         ui: 0...1, model: EffectParameter.unbounded, format: "%.2f"),
                l.double("levels.outputWhite", "Output White", "outputWhite", \.outputWhite,
                         ui: 0...1, model: EffectParameter.unbounded, format: "%.2f"),
            ]

        case .curves:
            let l = EffectCaseLens<Curves>(extract: { if case .curves(let p) = $0 { return p }; return nil },
                                           embed: { .curves($0) })
            return [
                l.compound("curves.points", "Points", "curveGraph",
                           value: .curvePoints, animation: .componentwise,
                           componentDomain: 0...1, keyPath: \Curves.points),
            ]

        case .brightnessContrast:
            let l = EffectCaseLens<BrightnessContrast>(
                extract: { if case .brightnessContrast(let p) = $0 { return p }; return nil },
                embed: { .brightnessContrast($0) })
            return [
                l.double("brightnessContrast.brightness", "Brightness", "brightness", \.brightness,
                         ui: 0...2, model: EffectParameter.unbounded, format: "%.2f"),
                l.double("brightnessContrast.contrast", "Contrast", "contrast", \.contrast,
                         ui: 0...2, model: EffectParameter.unbounded, format: "%.2f"),
            ]

        case .hsvShift:
            let l = EffectCaseLens<HSVShift>(extract: { if case .hsvShift(let p) = $0 { return p }; return nil },
                                            embed: { .hsvShift($0) })
            return [
                // Wraps rather than clamps, so 200° is a real value and not an out-of-range one.
                l.double("hsvShift.hue", "Hue", "hue", \.hueDegrees,
                         ui: -180...180, model: EffectParameter.unbounded, format: "%.0f°"),
                l.double("hsvShift.saturation", "Saturation", "saturation", \.saturation,
                         ui: 0...2, model: EffectParameter.unbounded, format: "%.2f"),
                l.double("hsvShift.value", "Value", "value", \.value,
                         ui: 0...2, model: EffectParameter.unbounded, format: "%.2f"),
            ]

        case .gradientMap:
            let l = EffectCaseLens<GradientMap>(extract: { if case .gradientMap(let p) = $0 { return p }; return nil },
                                               embed: { .gradientMap($0) })
            return [
                l.compound("gradientMap.stops", "Stops", "gradientPreview",
                           value: .gradientStops, animation: .componentwise,
                           componentDomain: 0...1, keyPath: \GradientMap.stops),
                l.double("gradientMap.mix", "Mix", "mix", \.mix,
                         ui: 0...1, model: EffectParameter.unbounded, format: "%.2f"),
            ]

        case .chromaticAberration:
            let l = EffectCaseLens<ChromaticAberration>(
                extract: { if case .chromaticAberration(let p) = $0 { return p }; return nil },
                embed: { .chromaticAberration($0) })
            return [
                l.double("chromaticAberration.offsetX", "Offset X", "offsetX", \.offsetX,
                         ui: -20...20, model: EffectParameter.unbounded, format: "%.1f px"),
                l.double("chromaticAberration.offsetY", "Offset Y", "offsetY", \.offsetY,
                         ui: -20...20, model: EffectParameter.unbounded, format: "%.1f px"),
            ]

        case .posterize:
            let l = EffectCaseLens<Posterize>(extract: { if case .posterize(let p) = $0 { return p }; return nil },
                                             embed: { .posterize($0) })
            return [
                // `params` reads `max(2, levels)`, so 2 is a floor the model enforces and the ceiling
                // is the slider's alone.
                l.integer("posterize.levels", "Levels", "levels", \.levels,
                          ui: 2...32, model: 2...(.infinity), format: "%.0f"),
                l.option("posterize.screen", "Screen", "screen", \.screen),
                l.double("posterize.screenStrength", "Screen Strength", "screenStrength",
                         \.screenStrength,
                         ui: 0...1, model: EffectParameter.unbounded, format: "%.2f"),
            ]

        case .noise:
            let l = EffectCaseLens<Noise>(extract: { if case .noise(let p) = $0 { return p }; return nil },
                                         embed: { .noise($0) })
            return [
                l.double("noise.amount", "Amount", "amount", \.amount,
                         ui: 0...0.5, model: EffectParameter.unbounded, format: "%.3f"),
                l.boolean("noise.monochrome", "Monochrome", "monochrome", \.isMonochrome),
                l.seed("noise.seed", "Grain Seed", "reseed", \.seed),
            ]

        case .blur:
            let l = EffectCaseLens<Blur>(extract: { if case .blur(let p) = $0 { return p }; return nil },
                                        embed: { .blur($0) })
            return [
                l.double("blur.radius", "Radius", "radius", \.radius,
                         ui: 0...64, model: 0...Double(Effect.maxBlurTaps), format: "%.1f px",
                         quantisation: .roundedByTheRenderPath),
                l.double("blur.angle", "Angle", "angle", \.angleDegrees,
                         ui: 0...360, model: EffectParameter.unbounded, format: "%.0f°"),
                // Rewrites the pass list from two entries to one. Not a quantity in any sense.
                l.boolean("blur.directional", "Directional", "directional", \.isDirectional),
            ]

        case .bloom:
            let l = EffectCaseLens<Bloom>(extract: { if case .bloom(let p) = $0 { return p }; return nil },
                                         embed: { .bloom($0) })
            return [
                l.double("bloom.threshold", "Threshold", "threshold", \.threshold,
                         ui: 0...1, model: 0...1, format: "%.2f"),
                l.double("bloom.radius", "Radius", "radius", \.radius,
                         ui: 0...64, model: 0...Double(Effect.maxBlurTaps), format: "%.1f px",
                         quantisation: .roundedByTheRenderPath),
                l.double("bloom.intensity", "Intensity", "intensity", \.intensity,
                         ui: 0...4, model: 0...(.infinity), format: "%.2f"),
                // Decides whether the compositor re-walks everything below into a fresh transparent
                // buffer. The settings bar shows it as an inverted "Include Canvas Color" toggle.
                l.option("bloom.input", "Input", "includeCanvasColor", \.input),
            ]

        case .sobel:
            // **The zero-parameter effect, and the only one.** Its settings bar is a single caption
            // and this is an empty list, so anything rendering a channel list has to survive one —
            // that is not a degenerate case to guard against, it is a shipped effect.
            return []

        case .sharpen:
            let l = EffectCaseLens<Sharpen>(extract: { if case .sharpen(let p) = $0 { return p }; return nil },
                                           embed: { .sharpen($0) })
            return [
                l.double("sharpen.radius", "Radius", "radius", \.radius,
                         ui: 0...32, model: 0...Double(Effect.maxBlurTaps), format: "%.1f px",
                         quantisation: .roundedByTheRenderPath),
                // **Negative is deliberately reachable and the slider does not admit it.**
                // `Sharpen`'s own doc: `amount: -1` reproduces a plain blur byte for byte, and
                // `EffectMultiPassLogicTests` pins that identity. A graph editor must let a key sit
                // below 0 even though the bar cannot drag one there.
                l.double("sharpen.amount", "Amount", "amount", \.amount,
                         ui: 0...4, model: EffectParameter.unbounded, format: "%.2f"),
            ]

        case .outline:
            let l = EffectCaseLens<Outline>(extract: { if case .outline(let p) = $0 { return p }; return nil },
                                           embed: { .outline($0) })
            return [
                // The one parameter whose slider and model agree exactly: `params` clamps width to
                // `maxOutlineRadius` and the slider's upper bound *is* `maxOutlineRadius`.
                l.double("outline.width", "Width", "width", \.width,
                         ui: 0...Effect.maxOutlineRadius, model: 0...Effect.maxOutlineRadius,
                         format: "%.1f px"),
                l.double("outline.threshold", "Alpha Threshold", "threshold", \.threshold,
                         ui: 0...1, model: 0...1, format: "%.2f"),
                l.compound("outline.color", "Colour", "color",
                           value: .colour, animation: .continuous,
                           componentDomain: 0...1, keyPath: \Outline.color),
            ]
        }
    }
}

// MARK: - §4.1's resolution: one effect, at one frame
//
// KEYFRAMES.md §8 stage 2. Stage 0 threaded the frame down to `Layer.layerEffect(atFrame:)` and
// `LayerFolder.resolvedEffect(atFrame:)` and left both returning the stored constant; stage 1 gave
// every parameter an address and a lens. This is the body those two were left waiting for.

extension EffectParameter {

    /// **Whether a `Double`-valued `AnimationCurve` may drive this parameter** — which is exactly the
    /// scope stage 2 takes, and it is narrower than "animatable".
    ///
    /// `.continuous` **and** backed by a single `Double`. Three kinds are excluded, and each is
    /// refused for a reason of its own rather than for want of time — the point of naming them here
    /// is that a track pointed at one of them must not be quietly stored and quietly do nothing.
    ///
    /// * **`.stepped` (six parameters).** `posterize.levels` is an `Int`, `noise.seed` a `UInt32`,
    ///   `blur.directional` and `noise.monochrome` `Bool`s, `posterize.screen` and `bloom.input`
    ///   indices into an enum. A curve is `Double`-valued and would hand 2.5 to every one of them;
    ///   the lens would round it, and the artist would get a staircase the graph editor never drew.
    ///   Two of the six are worse than merely non-numeric — `blur.directional` rewrites the pass list
    ///   from two entries to one and `bloom.input` decides whether the compositor performs an entire
    ///   sub-walk — so there is no midpoint to render even in principle.
    ///   `EffectParameterAnimation.stepped` already names what these want: evaluate, then **hold**
    ///   until the next key. That is a channel of its own, not this one with a rounding step bolted
    ///   on, and it is a later stage.
    /// * **`.componentwise` (two).** `curves.points` and `gradientMap.stops` are variable-length
    ///   lists. One curve cannot address a list at all: each element needs its own, plus the
    ///   same-count-tweens / different-counts-hold rule the owner settled on §9 question 4. That is a
    ///   channel *set*, and it is a later stage too.
    /// * **`.continuous` but compound (one, and it is the trap).** `outline.color` is `.continuous`
    ///   because four colour channels genuinely do tween — but its descriptor comes from
    ///   `EffectCaseLens.compound`, whose `read` returns nil and whose `write` is the **identity**. A
    ///   scalar track pointed at it would store, evaluate, write nothing and render exactly as
    ///   before: green everywhere, wrong on screen, and nothing in the model to point at. It wants
    ///   four curves and a decision about which colour space they interpolate in, neither of which
    ///   falls out for free.
    ///
    ///   **The colour-space half now has an answer to reuse rather than to re-derive.** TODO (10a)
    ///   put `ColorMath.mixOklab` in the tree and `gradientColour` above already tweens two colours
    ///   through it, for the reason recorded there. Note what that does to the *other* half: a colour
    ///   tween through Oklab is **not** four independent channel curves, because mixing the channels
    ///   separately is exactly the muddy middle (10a) removed. It is one curve driving a position
    ///   between two colours, plus alpha — which is a smaller change than "four curves", and a
    ///   different one.
    var isScalarAnimatable: Bool { animation == .continuous && value == .double }
}

extension Effect {

    /// **This effect with every keyed parameter evaluated at `frame`** — KEYFRAMES.md §4.1's
    /// `Effect.resolved(atFrame:)`, and the whole of stage 2's evaluation half.
    ///
    /// `tracks` is keyed by `EffectParameter.id`, and its keys are read in whatever time base the
    /// caller's tracks use — **absolute document frames** for the layer channel §2.4 rules on, which
    /// is the only caller today (`Layer.layerEffect(atFrame:)`). Nothing here knows or cares which;
    /// the frame arrives already resolved, which is what will let a cel-local object channel reuse
    /// this method unchanged.
    ///
    /// **The walk is over `parameters`, never over `tracks`, and both of the properties that matter
    /// come from that direction rather than from the other one:**
    ///
    ///  * **The order is the table's, so it is deterministic.** A dictionary's is not, and while no
    ///    two descriptors in one effect write the same field today, "it happens not to matter" is not
    ///    a property worth resting on.
    ///  * **The `isScalarAnimatable` refusal above lives in one place.** Every write site could
    ///    otherwise store a track that renders as nothing, and each would have to remember not to.
    ///
    /// **Presence is never touched, and that is load-bearing rather than incidental.** This takes an
    /// `Effect` and returns an `Effect`; there is no arm that returns nil. So a track can change what
    /// a grade *does* at a frame and can never change whether there *is* one — which is precisely
    /// what `CanvasManager.compositorSizeGate` and the panel-versus-rendering division in
    /// `Layer.layerEffect(atFrame:)` each rest on, at length, and each say expires the day a track can
    /// turn an effect on or off. Stage 2 did not spend either.
    ///
    /// **The empty-`tracks` guard is not merely an optimisation.** `parameters` builds its descriptor
    /// list — thirty-three closures at the largest — on every call, and this method is reached once
    /// per graded layer per tree derivation, which is several times a frame. The overwhelming
    /// majority of documents have no track at all, and for those this is one dictionary
    /// `isEmpty` and a return.
    func resolved(atFrame frame: Int, through tracks: [String: AnimationCurve]) -> Effect {
        guard !tracks.isEmpty else { return self }
        var resolved = self
        for parameter in parameters {
            guard parameter.isScalarAnimatable,
                  let curve = tracks[parameter.id], !curve.isEmpty else { continue }
            // `evaluate` holds flat outside the outermost keys (`AnimationCurve` decision 2), so a
            // frame before the first key or after the last is that key's value rather than an
            // extrapolation — which is what makes a layer channel safe to ask at *any* document
            // frame, including ones this layer has no cel on.
            resolved = parameter.write(resolved, curve.evaluate(at: Double(frame)))
        }
        return resolved
    }

    /// **Which of `tracks` the grade `effect` can drive** — the filter every writer of `Layer.effect`
    /// and `LayerFolder.effect` runs over the tracks stored beside it, so that a grade's channels do
    /// not outlive the grade.
    ///
    /// A track the current effect has no parameter for renders nothing and can be reached by nothing:
    /// the timeline builds its channel list from that effect's own descriptors
    /// (`CanvasManager.curvedEffectChannelIDs`), so such a curve is invisible, uneditable and
    /// undeletable, and is nevertheless written into every saved copy of the document. It is storage
    /// with no way in and no way out, and the artist meets it only by accident. So it goes.
    ///
    /// **By parameter id, never by comparing effect cases**, which is what makes the answer exact in
    /// both directions and a no-op for free when nothing really changed. The two case-shaped tests
    /// this tree offers are each wrong for it, in opposite ways:
    ///
    ///  * `kindCode` is a GPU dispatch code that **merges** distinct cases — `.levels` and `.curves`
    ///    both answer 0, `.blur` and `.sharpen` both answer 7 — so a "did the kind change" test on it
    ///    keeps every track across Levels → Curves.
    ///  * `EffectCatalog.isCurrent` compares `displayName`, which is **finer** than the case: Gaussian
    ///    Blur and Directional Blur are one `.blur` split by `Blur.isDirectional`, so a test on it
    ///    would throw away `blur.radius` and `blur.angle` when the artist merely flips that toggle.
    ///    The ids do not, because `parameters` lists all three of `.blur`'s under either spelling.
    ///
    /// Ids are `"<case>.<field>"` (`EffectParameter.id`), so `blur.radius`, `bloom.radius` and
    /// `sharpen.radius` are three addresses rather than one name three effects share. A nil effect
    /// therefore keeps nothing, which is what "this layer is not grading" means; and re-picking the
    /// effect that is already set keeps everything, with no early-out anywhere needed to arrange it.
    static func tracksAddressed(by effect: Effect?,
                                from tracks: [String: AnimationCurve]) -> [String: AnimationCurve] {
        channelEntriesAddressed(by: effect, from: tracks)
    }

    /// **The same rule for any dictionary keyed by `EffectParameter.id`.**
    ///
    /// A curve is not the only per-channel thing a grade owns: `Layer.pendingBaselines` holds the value
    /// each channel had before the artist's first edit since their last keyframe, under the same ids.
    /// A held value the new grade cannot address is exactly what a track it cannot address is —
    /// storage nothing can reach, written into every saved copy of the document, and met again only by
    /// accident. One rule, applied wherever those ids are the key, so the two cannot answer differently.
    static func channelEntriesAddressed<Value>(by effect: Effect?,
                                               from entries: [String: Value]) -> [String: Value] {
        guard !entries.isEmpty else { return entries }
        guard let effect else { return [:] }
        // `parameters` builds up to thirty-three closures per call, which is why `resolved` above
        // guards against paying it on every render. Here it is once per discrete pick — the price a
        // mode picker can afford, and the reason this is not folded into the resolver.
        let addressable = Set(effect.parameters.map(\.id))
        return entries.filter { addressable.contains($0.key) }
    }
}
