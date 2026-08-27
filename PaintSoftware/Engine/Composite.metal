#include <metal_stdlib>
using namespace metal;

// Compositing kernels for MetalCompositor — LAYER_COMPOSITING.md §5.1.
//
// Coordinate and pixel conventions match the rest of the app exactly, which is what makes a
// byte-identical comparison against the CoreGraphics path meaningful: index 0 is the top-left pixel,
// y increases downward, and every texture is `rgba8Unorm` — **not** `rgba8Unorm_srgb`. That
// distinction is load-bearing. The sRGB variants linearize on read and re-encode on write, so the
// same arithmetic through them lands nowhere near the CPU reference; the app's bytes are device-RGB
// premultiplied-last and these kernels move them without colour management, as `PixelOps` and
// `MetalFillEngine` already do.
//
// Alpha is premultiplied throughout, which is why applying a layer's opacity is a scale of all four
// channels rather than of `a` alone: premultiplied `(r,g,b,a) * o` is the same colour at `o` times
// the coverage, whereas scaling only `a` would brighten the colour as it faded.
//
// **The blend math, by contrast, runs unpremultiplied and re-premultiplies on write** — see
// `blendOver`. Blending premultiplied channels directly is the single most likely way to get this
// file wrong, and it fails in a way that is easy to miss: solid interiors look right and only
// antialiased edges, where alpha is fractional, come out dark. §5.1's "blend modes are one switch in
// one shader" is true of the switch; the wrapper around it is where the care goes.

// MARK: - Mode codes
//
// **These must match `BlendMode.shaderCode` in MetalCompositor.swift, case for case.** The pair is
// two literals in two languages with nothing but this comment between them, so it is deliberately
// covered by a test rather than by a convention: `CompositorParityLogicTests` composites every one
// of the modes through both backends, and a code that disagreed would show up there as one mode
// rendering as another rather than as a compile error.
constant uint kBlendNormal      = 0;
constant uint kBlendMultiply    = 1;
constant uint kBlendScreen      = 2;
constant uint kBlendOverlay     = 3;
constant uint kBlendAdd         = 4;
constant uint kBlendSubtract    = 5;
constant uint kBlendDarken      = 6;
constant uint kBlendLighten     = 7;
constant uint kBlendColorDodge  = 8;
constant uint kBlendColorBurn   = 9;
constant uint kBlendSoftLight   = 10;
constant uint kBlendHardLight   = 11;
constant uint kBlendLinearLight = 12;
constant uint kBlendDifference  = 13;
// Tier 2 (§7). Vivid Light, Pin Light, Linear Burn, Divide and Exclusion are separable, like
// everything above; Hue, Saturation, Color, Luminosity, Lighter Color and Darker Color are not, but
// need no new plumbing here — see the note above `blendHue` for why `blendChannels` covers both
// shapes through the one `float3 -> float3` call already.
constant uint kBlendVividLight   = 14;
constant uint kBlendPinLight     = 15;
constant uint kBlendLinearBurn   = 16;
constant uint kBlendHue          = 17;
constant uint kBlendSaturation   = 18;
constant uint kBlendColor        = 19;
constant uint kBlendLuminosity   = 20;
constant uint kBlendDivide       = 21;
constant uint kBlendExclusion    = 22;
constant uint kBlendLighterColor = 23;
constant uint kBlendDarkerColor  = 24;

// MARK: - The separable blend functions
//
// W3C Compositing and Blending Level 1, which is the same set of formulas the PDF imaging model
// specifies and therefore the same ones CoreGraphics' `CGBlendMode` implements. That is not a
// coincidence to be relied on quietly: eleven of the fourteen modes below are compared directly
// against Apple's implementation of the same formula (see `BlendMode.coreGraphicsBlendMode`), so
// writing anything else here — a "close enough" soft light, say — turns a rounding measurement into
// a correctness failure with a rounding-shaped error bar.

static inline float3 blendMultiply(float3 cb, float3 cs) { return cb * cs; }
static inline float3 blendScreen(float3 cb, float3 cs)   { return cb + cs - cb * cs; }

static inline float3 blendHardLight(float3 cb, float3 cs) {
    return select(blendScreen(cb, 2.0f * cs - 1.0f), blendMultiply(cb, 2.0f * cs), cs <= 0.5f);
}

static inline float3 blendColorDodge(float3 cb, float3 cs) {
    // The two guards are the spec's, not defensive clamping: `cb == 0` stays black however hard it
    // is dodged, and `cs == 1` saturates rather than dividing by zero.
    float3 dodged = min(float3(1.0f), cb / max(1.0f - cs, 1e-6f));
    dodged = select(dodged, float3(1.0f), cs >= 1.0f);
    return select(dodged, float3(0.0f), cb <= 0.0f);
}

static inline float3 blendColorBurn(float3 cb, float3 cs) {
    float3 burned = 1.0f - min(float3(1.0f), (1.0f - cb) / max(cs, 1e-6f));
    burned = select(burned, float3(0.0f), cs <= 0.0f);
    return select(burned, float3(1.0f), cb >= 1.0f);
}

static inline float3 blendSoftLight(float3 cb, float3 cs) {
    // The spec's D(cb): a cubic below a quarter, a square root above it. The cubic exists to keep
    // the curve's slope finite at zero, where `sqrt` is vertical and would band on dark backdrops.
    float3 d = select(sqrt(cb), ((16.0f * cb - 12.0f) * cb + 4.0f) * cb, cb <= 0.25f);
    float3 darker  = cb - (1.0f - 2.0f * cs) * cb * (1.0f - cb);
    float3 lighter = cb + (2.0f * cs - 1.0f) * (d - cb);
    return select(lighter, darker, cs <= 0.5f);
}

// MARK: - Tier 2's separable additions (§7)

static inline float3 blendLinearBurn(float3 cb, float3 cs) {
    // Linear Dodge (`kBlendAdd`) is `cb + cs`, clamped above at 1; this is its mirror, clamped below
    // at 0 instead, since `cb + cs - 1` is the term that can go negative rather than over 1.
    return max(float3(0.0f), cb + cs - 1.0f);
}

static inline float3 blendVividLight(float3 cb, float3 cs) {
    // Color Burn below mid-grey, Color Dodge above it, each fed the doubled, re-centred source — the
    // same split `blendHardLight` makes between Multiply and Screen.
    float3 burned = blendColorBurn(cb, 2.0f * cs);
    float3 dodged = blendColorDodge(cb, 2.0f * cs - 1.0f);
    return select(dodged, burned, cs <= 0.5f);
}

static inline float3 blendPinLight(float3 cb, float3 cs) {
    // Darken below mid-grey, Lighten above it — Vivid Light's family, with the ordinary pair instead
    // of the dodge/burn pair.
    float3 darkened = min(cb, 2.0f * cs);
    float3 lightened = max(cb, 2.0f * cs - 1.0f);
    return select(lightened, darkened, cs <= 0.5f);
}

static inline float3 blendDivide(float3 cb, float3 cs) {
    // Mirrors `blendColorDodge`'s guard order exactly, with the pole moved from `1 - cs` to `cs`
    // itself: a black backdrop stays black regardless of the source (applied last, so it wins), and
    // a near-zero source saturates to white rather than dividing by it.
    float3 divided = min(float3(1.0f), cb / max(cs, 1e-6f));
    divided = select(divided, float3(1.0f), cs <= 0.0f);
    return select(divided, float3(0.0f), cb <= 0.0f);
}

static inline float3 blendExclusion(float3 cb, float3 cs) { return cb + cs - 2.0f * cb * cs; }

// MARK: - Tier 2's non-separable additions (§7)
//
// W3C Compositing and Blending Level 1's `Lum`/`Sat`/`ClipColor`/`SetLum`/`SetSat`, which
// Hue/Saturation/Color/Luminosity are built from. Unlike every function above, these read or write
// all three channels of one pixel together — which a `float3` already does, so they need no
// different calling convention from the separable functions, only a different body. That is the
// whole reason Tier 2's "non-separable" trap (see `Compositor.swift`'s `handRolledTriple`) is
// CPU-only: `blendChannels` below hands every mode, separable or not, the same `(cb, cs) -> float3`
// shape it always has.

static inline float lum(float3 c) { return 0.3f * c.r + 0.59f * c.g + 0.11f * c.b; }
static inline float sat(float3 c) { return max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b)); }

/// Pulls an out-of-gamut colour back into `[0, 1]` along the line through it and its own `Lum`. The
/// `max(_, 1e-6f)` guards matter only where both branches meet — a colour whose `Lum` equals its
/// `min`/`max` has all three channels equal, so `c - l` is exactly zero there and the guard turns a
/// `0 / 0` into a `0 / epsilon` rather than changing the result.
static inline float3 clipColor(float3 c) {
    float l = lum(c);
    float n = min(c.r, min(c.g, c.b));
    float x = max(c.r, max(c.g, c.b));
    if (n < 0.0f) { c = l + (c - l) * (l / max(l - n, 1e-6f)); }
    if (x > 1.0f) { c = l + (c - l) * ((1.0f - l) / max(x - l, 1e-6f)); }
    return c;
}

static inline float3 setLum(float3 c, float l) { return clipColor(c + (l - lum(c))); }

/// The spec states `SetSat` as a sort into min/mid/max followed by a per-slot rewrite. This is the
/// same function stated as one affine remap of the whole triple: `(c - cMin) * s / (cMax - cMin)`
/// sends `cMin` to 0 and `cMax` to `s` by construction, and the value in between lands exactly on the
/// spec's `Cmid` formula — so there is no sort and no per-channel branch, on either backend.
static inline float3 setSat(float3 c, float s) {
    float cMax = max(c.r, max(c.g, c.b));
    float cMin = min(c.r, min(c.g, c.b));
    if (cMax <= cMin) { return float3(0.0f); }
    return (c - cMin) * (s / (cMax - cMin));
}

/// Hue keeps the source's hue and saturation but the backdrop's luminosity.
static inline float3 blendHue(float3 cb, float3 cs) { return setLum(setSat(cs, sat(cb)), lum(cb)); }
/// Saturation keeps the backdrop's hue and luminosity but the source's saturation.
static inline float3 blendSaturation(float3 cb, float3 cs) { return setLum(setSat(cb, sat(cs)), lum(cb)); }
/// Color keeps the source's hue and saturation and the backdrop's luminosity, in one step.
static inline float3 blendColor(float3 cb, float3 cs) { return setLum(cs, lum(cb)); }
/// Luminosity is Color with backdrop and source swapped.
static inline float3 blendLuminosity(float3 cb, float3 cs) { return setLum(cb, lum(cs)); }

/// Whole-triple luminosity picks the whole-triple winner — not a per-channel max, which is what
/// `kBlendLighten` already is and would not need a new mode to express.
static inline float3 blendLighterColor(float3 cb, float3 cs) { return lum(cs) >= lum(cb) ? cs : cb; }
static inline float3 blendDarkerColor(float3 cb, float3 cs) { return lum(cs) <= lum(cb) ? cs : cb; }

/// The per-channel blend, unpremultiplied on both sides. `cb`/`cs` are backdrop and source colour.
static inline float3 blendChannels(uint mode, float3 cb, float3 cs) {
    switch (mode) {
        case kBlendMultiply:   return blendMultiply(cb, cs);
        case kBlendScreen:     return blendScreen(cb, cs);
        // Overlay is hard light with the operands swapped — the same curve applied by the backdrop
        // to the source instead of the other way round. Written as the swap rather than as a second
        // copy of the formula so the two can never drift apart.
        case kBlendOverlay:    return blendHardLight(cs, cb);
        case kBlendAdd:        return min(float3(1.0f), cb + cs);
        case kBlendSubtract:   return max(float3(0.0f), cb - cs);
        case kBlendDarken:     return min(cb, cs);
        case kBlendLighten:    return max(cb, cs);
        case kBlendColorDodge: return blendColorDodge(cb, cs);
        case kBlendColorBurn:  return blendColorBurn(cb, cs);
        case kBlendSoftLight:  return blendSoftLight(cb, cs);
        case kBlendHardLight:  return blendHardLight(cb, cs);
        // Linear light is linear burn below mid-grey and linear dodge above it, which collapses to
        // one clamped add of the doubled, re-centred source.
        case kBlendLinearLight: return saturate(cb + 2.0f * cs - 1.0f);
        case kBlendDifference: return abs(cb - cs);
        case kBlendVividLight:   return blendVividLight(cb, cs);
        case kBlendPinLight:     return blendPinLight(cb, cs);
        case kBlendLinearBurn:   return blendLinearBurn(cb, cs);
        case kBlendHue:          return blendHue(cb, cs);
        case kBlendSaturation:   return blendSaturation(cb, cs);
        case kBlendColor:        return blendColor(cb, cs);
        case kBlendLuminosity:   return blendLuminosity(cb, cs);
        case kBlendDivide:       return blendDivide(cb, cs);
        case kBlendExclusion:    return blendExclusion(cb, cs);
        case kBlendLighterColor: return blendLighterColor(cb, cs);
        case kBlendDarkerColor:  return blendDarkerColor(cb, cs);
        default:               return cs;
    }
}

/// One premultiplied source over one premultiplied backdrop, blended per `mode`.
///
/// The shape is W3C's, and every term of it earns its place:
///
///     Cr = (1 - ab) * Cs + ab * B(Cb, Cs)     — the blend only applies where there is a backdrop
///     co = as * Cr + (1 - as) * Cb * ab       — and the result composites source-over as usual
///     ao = as + ab * (1 - as)
///
/// The first line is why a `multiply` layer at the bottom of an isolated group reads as normal
/// (§4.2): with `ab == 0` the blend term vanishes and `Cr` is just the source. That behaviour is not
/// special-cased anywhere, in either backend — it falls out of this interpolation, which is the
/// reason to write it this way rather than branching on an empty backdrop.
static inline float4 blendOver(float4 dst, float4 src, uint mode) {
    // Normal keeps the exact expression phase 2 shipped, not the general path specialised. `as * (Cs
    // / as)` is not bit-identical to `Cs` in float, and phase 2's GPU-vs-CPU gate holds at delta 0
    // for source-over — a value worth more than the four lines it costs to keep.
    if (mode == kBlendNormal) { return fma(dst, 1.0f - src.a, src); }

    float sa = src.a, da = dst.a;
    // `saturate` guards against a premultiplied byte pair like (r=3, a=2) that 8-bit rounding can
    // produce upstream; it is not a licence to feed this function unpremultiplied input.
    float3 cs = sa > 0.0f ? saturate(src.rgb / sa) : float3(0.0f);
    float3 cb = da > 0.0f ? saturate(dst.rgb / da) : float3(0.0f);

    float3 cr = mix(cs, blendChannels(mode, cb, cs), da);
    return float4(fma(dst.rgb, 1.0f - sa, sa * cr), fma(da, 1.0f - sa, sa));
}

/// One layer or one group's assembled composite, onto a backdrop, at `opacity` and in `mode`.
///
/// Dispatched with `dispatchThreads`, so out-of-bounds threads are never launched and the kernel
/// needs no bounds check — the same assumption `Fill.metal`'s kernels make.
kernel void compositeOver(texture2d<float, access::read>  backdrop [[texture(0)]],
                          texture2d<float, access::read>  layer    [[texture(1)]],
                          texture2d<float, access::write> result   [[texture(2)]],
                          constant float                 &opacity  [[buffer(0)]],
                          constant uint                  &mode     [[buffer(1)]],
                          uint2 gid [[thread_position_in_grid]])
{
    float4 dst = backdrop.read(gid);
    float4 src = layer.read(gid) * opacity;
    result.write(blendOver(dst, src, mode), gid);
}

/// Fills a rectangle of a texture with a constant premultiplied colour — the canvas background, the
/// initial clear when there is none, and the transparent start of every buffered group's scratch
/// texture.
///
/// `origin` exists because a compute grid always starts at zero and the paper does not: the canvas
/// background covers the artwork rect, which is the canvas inset by its padding margin (see
/// `RenderBackground.rect`). Every other caller passes `(0, 0)` and dispatches the whole texture,
/// which is the same single write it always was.
kernel void compositeFill(texture2d<float, access::write> result [[texture(0)]],
                          constant float4                &color  [[buffer(0)]],
                          constant uint2                 &origin [[buffer(1)]],
                          uint2 gid [[thread_position_in_grid]])
{
    result.write(color, gid + origin);
}

/// One layer's pixels, or one group's assembled composite, clipped by a resolved alpha mask
/// (LAYER_COMPOSITING.md §6.1 — at render time, never baked into the layer).
///
/// All four channels scale, for the reason this file's header gives about opacity: the input is
/// premultiplied, so a pixel at half coverage is the same colour at half the coverage, while scaling
/// `a` alone would brighten it as it faded.
///
/// **The mask itself is not computed here.** §6.3's threshold is a step function, so a source alpha
/// that differed between the backends by the one channel step the blend modes are allowed would land
/// on opposite sides of it — `MaskResolver` resolves through the CPU reference for both backends and
/// this kernel receives the finished coverage. What is left is one multiply, and
/// `MaskResolver.apply` performs the same one in the same order in Swift so the two round to the
/// same byte.
kernel void compositeMask(texture2d<float, access::read>  layer  [[texture(0)]],
                          texture2d<float, access::read>  mask   [[texture(1)]],
                          texture2d<float, access::write> result [[texture(2)]],
                          uint2 gid [[thread_position_in_grid]])
{
    result.write(layer.read(gid) * mask.read(gid).r, gid);
}

/// **A graded backdrop rejoining the stack it was graded from** — §4.4's stack-layer wrapper, phase 9a.
///
/// Not `compositeOver`, and the difference is the whole of what an adjustment layer is. An effect
/// preserves alpha exactly (`applyEffect`), so the graded texture has the backdrop's own coverage —
/// and compositing a texture source-over a backdrop of the same alpha would inflate it to
/// `2a - a²`, thickening every antialiased edge in the document a grade passed over. The graded
/// pixels are not a new source to lay on top; they are the same pixels, regraded, so they *replace*
/// what they came from and `mix` is the only operator that says that.
///
/// That is also what makes `opacity` and the mask read as an *amount* here rather than as coverage:
/// half opacity is half-way between the ungraded and graded backdrop, which is what an artist means
/// by a 50% adjustment layer, and outside the mask the amount is 0 and the backdrop comes through
/// byte for byte. `CoreGraphicsCompositor.grade` computes `b + (g - b) * amount` in that order for
/// the same reason `MaskResolver.apply` mirrors `compositeMask` term for term.
///
/// `coverage` is bound even when the node has no mask, because a declared texture argument has to be;
/// `hasCoverage` is what keeps it unread, and the caller binds `base` again rather than allocating
/// something to ignore.
kernel void compositeEffectMix(texture2d<float, access::read>  base        [[texture(0)]],
                               texture2d<float, access::read>  graded      [[texture(1)]],
                               texture2d<float, access::read>  coverage    [[texture(2)]],
                               texture2d<float, access::write> result      [[texture(3)]],
                               constant float                 &opacity     [[buffer(0)]],
                               constant uint                  &hasCoverage [[buffer(1)]],
                               uint2 gid [[thread_position_in_grid]])
{
    float amount = opacity * (hasCoverage != 0u ? coverage.read(gid).r : 1.0f);
    float4 b = base.read(gid);
    result.write(mix(b, graded.read(gid), amount), gid);
}

// MARK: - Tier 3 effects (§4.4, §7)
//
// **One kernel with one switch, the shape §5.1 describes for blend modes and for the same reason.**
// Ten pipelines would be ten registrations in whichever object ends up owning the compositor's
// pipeline states, and adding the eleventh effect would touch that object again; one pipeline means an
// effect is a case here and a case in `Effect.kindCode`, with nothing to register.
//
// **The multi-pass effects did not need a second entry point, and that is the finding worth recording
// here.** An earlier note in this file said the neighbourhood filters "will not fit this kernel". They
// fit. A separable blur is two dispatches of *this* kernel differing only in the step vector in
// `params`, and bloom is four; what changed is not the kernel but the thing driving it —
// `EffectPipelines` now runs a list of passes rather than one, and `Effect.passes` in Swift decides how
// long that list is. Nothing here is told which pass it is running, because a pass is fully described
// by the numbers it carries.
//
// **Every kernel below is bound to the same values `EffectReference` reads**: a kind code, a flat
// parameter block, a 256-entry table, and a half-kernel of convolution weights. Neither backend
// interprets an `Effect`; `Effect.swift` does that once, in Swift, and hands both the result. See that
// file's header for what this buys and what it costs.
//
// Alpha is preserved by construction *for the grades* — the wrapper unpremultiplies, hands the
// *colour* to the switch, and re-premultiplies with the alpha it read, so a grade sits anywhere in a
// tree without changing what a mask beneath it resolves to. **Blur and bloom sit outside that wrapper
// and do change coverage**, because a blur that left the silhouette sharp is not a blur; they convolve
// premultiplied values so colour and coverage move together.

// **Must match `Effect.kindCode` in Effect.swift and `EffectReference`'s constants, case for case** —
// three literals in three places, covered by `EffectParityLogicTests` running every effect through
// both backends rather than by a convention, exactly as the `kBlend…` codes above are.
constant uint kEffectLookupTable         = 0;
constant uint kEffectBrightnessContrast  = 1;
constant uint kEffectHSVShift            = 2;
constant uint kEffectGradientMap         = 3;
constant uint kEffectChromaticAberration = 4;
constant uint kEffectPosterize           = 5;
constant uint kEffectNoise               = 6;
constant uint kEffectBlur1D              = 7;
constant uint kEffectBloomThreshold      = 8;
constant uint kEffectBloomCombine        = 9;
constant uint kEffectSobel               = 10;
constant uint kEffectSharpenCombine      = 11;
constant uint kEffectOutline             = 12;

/// Mirrors `EffectParams` in Effect.swift field for field. **All-scalar, deliberately**: a `float2`
/// here has an alignment a Swift `SIMD2<Float>` matches only by luck, and a padding disagreement
/// between the two declarations shifts every field after it — which does not fail to compile, it
/// renders a different picture.
struct EffectParams {
    float brightness;
    float contrast;
    float hueTurns;
    float saturation;
    float value;
    // A displacement in pixels, shared by chromatic aberration's per-channel offset and a blur pass's
    // per-tap step — and the reason a blur pass carries no "which pass am I" flag: the step is it.
    float offsetX;
    float offsetY;
    float mix;
    float levels;
    float screenStrength;
    float amount;
    float threshold;
    float intensity;
    uint  screen;
    uint  seed;
    uint  isMonochrome;
    uint  taps;
    // Appended at the end, deliberately — see the Swift declaration this mirrors for why that
    // position is the only one a mismatch cannot silently corrupt.
    float colorR;
    float colorG;
    float colorB;
};

/// One entry of the resolved transfer table.
///
/// `floor(v * 255 + 0.5)` rather than `round`, because half-up is the one rounding rule that can be
/// written identically in Metal and Swift — `round` is half-away-from-zero and Swift's default is
/// half-to-even, and an index that disagreed by one would step by however steep the curve is at that
/// point rather than by the channel step the blend modes are allowed.
static inline float3 lutEntry(constant uchar4 *lut, float value) {
    uint index = min(uint(floor(saturate(value) * 255.0f + 0.5f)), 255u);
    return float3(lut[index].rgb) / 255.0f;
}

// The two screens `Posterize` offsets its quantizer with: Bayer's recursive dispersed dot, and the
// classic clustered dot whose thresholds spiral outward from one cell so that growing coverage grows a
// dot instead of scattering pixels. That clustering is the whole difference between a halftone and a
// dither.
constant uint kBayer4[16]     = {  0,  8,  2, 10, 12,  4, 14,  6,  3, 11,  1,  9, 15,  7, 13,  5 };
constant uint kClustered4[16] = { 12,  5,  6, 13,  4,  0,  1,  7, 11,  3,  2,  8, 15, 10,  9, 14 };

/// The screen's value at one pixel, in `[0, 1)` and averaging 0.5 — the mean is what makes
/// `screenStrength == 0` exactly plain rounding, so posterize is the faded case of the same formula
/// rather than a branch of its own.
static inline float screenValue(uint kind, uint2 gid) {
    uint cell = (gid.y & 3u) * 4u + (gid.x & 3u);
    if (kind == 1u) { return (float(kBayer4[cell]) + 0.5f) / 16.0f; }
    if (kind == 2u) { return (float(kClustered4[cell]) + 0.5f) / 16.0f; }
    return 0.5f;
}

/// A hash of position and seed, in `[0, 1)`.
///
/// **Integer arithmetic, then a 24-bit truncation, and both halves are load-bearing.** `uint` wraps by
/// definition here and Swift's `&*`/`&+` are the same operation, so this is bit-identical across the
/// two languages — where the usual shader idiom (`fract(sin(dot(…)) * 43758.5)`) would depend on
/// `sin`'s last bit and on whether fast math rewrote the multiply. Truncating to the top 24 bits before
/// the conversion keeps the result exactly representable in `float`, so neither side has a rounding
/// decision to make either.
static inline float noiseValue(uint2 gid, uint seed, uint salt) {
    uint h = gid.x * 374761393u;
    h = h + gid.y * 668265263u;
    h = h + seed * 2246822519u + salt * 3266489917u;
    h = (h ^ (h >> 13)) * 1274126177u;
    h ^= h >> 16;
    return float(h >> 8) / 16777216.0f;
}

// The app's existing HSV conversion (`ColorMath.rgbToHSB`/`hsbToRGB`), transcribed — including its
// hue-in-turns convention and its achromatic answer of hue 0. Transcribed rather than replaced because
// the CPU reference calls the original: that makes HSV the one effect whose measured GPU-versus-CPU
// delta compares two implementations that were not written together, and the value of that depends on
// this being the same function rather than a better one.

static inline float3 rgbToHSB(float3 c) {
    float maxC = max(c.r, max(c.g, c.b));
    float minC = min(c.r, min(c.g, c.b));
    float delta = maxC - minC;
    float v = maxC;
    float s = maxC == 0.0f ? 0.0f : delta / maxC;
    if (!(delta > 0.0f)) { return float3(0.0f, s, v); }

    float h;
    if (maxC == c.r)      { h = fmod((c.g - c.b) / delta, 6.0f); }
    else if (maxC == c.g) { h = (c.b - c.r) / delta + 2.0f; }
    else                  { h = (c.r - c.g) / delta + 4.0f; }
    h /= 6.0f;
    if (h < 0.0f) { h += 1.0f; }
    return float3(h, s, v);
}

static inline float3 hsbToRGB(float3 hsb) {
    float v = hsb.z, s = hsb.y;
    if (!(s > 0.0f)) { return float3(v); }
    float wrapped = fmod(fmod(hsb.x, 1.0f) + 1.0f, 1.0f);
    float hh = wrapped * 6.0f;
    int sector = int(hh) % 6;
    float f = hh - float(int(hh));
    float p = v * (1.0f - s);
    float q = v * (1.0f - s * f);
    float t = v * (1.0f - s * (1.0f - f));
    switch (sector) {
        case 0:  return float3(v, t, p);
        case 1:  return float3(q, v, p);
        case 2:  return float3(p, v, t);
        case 3:  return float3(p, q, v);
        case 4:  return float3(t, p, v);
        default: return float3(v, p, q);
    }
}

/// The per-pixel colour transform, unpremultiplied in and out — the same contract `blendChannels` has,
/// and the shape `EffectReference.transform` mirrors line for line.
static inline float3 effectChannels(uint kind, constant EffectParams &params, constant uchar4 *lut,
                                    float3 c, uint2 gid) {
    switch (kind) {
        case kEffectLookupTable:
            // Each channel indexes the table with its own value, which is what makes per-channel
            // levels and curves a parameter change in Swift rather than a change here.
            return float3(lutEntry(lut, c.r).r, lutEntry(lut, c.g).g, lutEntry(lut, c.b).b);

        case kEffectBrightnessContrast:
            // Contrast then brightness, clamped once by the caller — CSS Filter Effects Level 1's two
            // linear transfers, in the order the two names are always written.
            return (c * params.contrast + (0.5f - 0.5f * params.contrast)) * params.brightness;

        case kEffectHSVShift: {
            float3 hsb = rgbToHSB(c);
            float s = saturate(hsb.y * params.saturation);
            float v = saturate(hsb.z * params.value);
            return hsbToRGB(float3(hsb.x + params.hueTurns, s, v));
        }

        case kEffectGradientMap: {
            // W3C Compositing Level 1's `Lum`, which `lum` above already states — one definition of
            // "how bright is this colour" in this file, not two that nearly agree.
            float3 mapped = lutEntry(lut, lum(c));
            return c + (mapped - c) * params.mix;
        }

        case kEffectPosterize: {
            float steps = max(params.levels - 1.0f, 1.0f);
            float dither = 0.5f + params.screenStrength * (screenValue(params.screen, gid) - 0.5f);
            return floor(c * steps + dither) / steps;
        }

        case kEffectNoise: {
            float3 deviation;
            if (params.isMonochrome != 0u) {
                deviation = float3((noiseValue(gid, params.seed, 0u) - 0.5f) * 2.0f * params.amount);
            } else {
                deviation = float3((noiseValue(gid, params.seed, 0u) - 0.5f) * 2.0f * params.amount,
                                   (noiseValue(gid, params.seed, 1u) - 0.5f) * 2.0f * params.amount,
                                   (noiseValue(gid, params.seed, 2u) - 0.5f) * 2.0f * params.amount);
            }
            return c + deviation;
        }

        default:
            return c;
    }
}

static inline float4 texelClamped(texture2d<float, access::read> source, int x, int y) {
    int width = int(source.get_width()), height = int(source.get_height());
    return source.read(uint2(uint(clamp(x, 0, width - 1)), uint(clamp(y, 0, height - 1))));
}

/// Bilinear, clamp-to-edge, on **premultiplied** texels — which is the whole reason premultiplied
/// storage exists, since interpolating unpremultiplied colour across an alpha edge pulls in the colour
/// of pixels that are not there.
static inline float4 sampleBilinear(texture2d<float, access::read> source, float2 position) {
    float2 base = floor(position);
    float2 fraction = position - base;
    int x = int(base.x), y = int(base.y);
    float4 top = mix(texelClamped(source, x, y), texelClamped(source, x + 1, y), fraction.x);
    float4 bottom = mix(texelClamped(source, x, y + 1), texelClamped(source, x + 1, y + 1), fraction.x);
    return mix(top, bottom, fraction.y);
}

/// The one gather effect in the set: red sampled at `+offset`, blue at `-offset`, green where it is.
///
/// Each channel is unpremultiplied by the alpha it was sampled with, and the triple is re-premultiplied
/// by the alpha at the pixel itself — so the shape of the artwork is the *green* channel's alpha and
/// the fringe appears in colour, never in coverage. Where a displaced sample lands on transparency its
/// channel contributes nothing, which is the dark fringe real lateral aberration shows at a hard edge.
static inline float4 chromaticAberration(texture2d<float, access::read> source,
                                         constant EffectParams &params, uint2 gid) {
    float2 position = float2(gid);
    float2 offset = float2(params.offsetX, params.offsetY);
    float4 centre = sampleBilinear(source, position);
    float alpha = centre.a;
    if (!(alpha > 0.0f)) { return float4(0.0f); }

    float4 shiftedRed = sampleBilinear(source, position + offset);
    float4 shiftedBlue = sampleBilinear(source, position - offset);
    float3 colour = saturate(float3(shiftedRed.a > 0.0f ? shiftedRed.r / shiftedRed.a : 0.0f,
                                    centre.g / alpha,
                                    shiftedBlue.a > 0.0f ? shiftedBlue.b / shiftedBlue.a : 0.0f));
    return float4(colour * alpha, alpha);
}

/// One separable pass: a weighted sum of `2 * taps + 1` samples along `(offsetX, offsetY)`.
///
/// **Premultiplied throughout, and never unpremultiplied.** A convolution is a weighted average, and
/// averaging premultiplied values is the only form of it that is correct across an alpha edge — the
/// argument `sampleBilinear` above already makes for one tap, applied to every tap here. The weights
/// are non-negative and sum to 1, so a valid premultiplied input stays valid (`rgb <= a` survives a
/// convex combination) and there is nothing to re-impose afterwards.
///
/// **The step is checked once for whether it lands on the pixel grid.** The Gaussian's two axis-aligned
/// passes always do; a directional blur's angle generally does not. On-grid taps read one texel,
/// off-grid taps interpolate four. The branch is uniform across the dispatch — it is a property of the
/// parameters, not of the pixel — so it costs nothing and saves the common case four reads a tap.
static inline float4 blur1D(texture2d<float, access::read> source, constant EffectParams &params,
                            constant float *weights, uint2 gid) {
    uint taps = params.taps;
    if (taps == 0u) { return source.read(gid); }

    float2 step = float2(params.offsetX, params.offsetY);
    bool onGrid = step.x == round(step.x) && step.y == round(step.y);
    int2 position = int2(gid);
    float4 sum = source.read(gid) * weights[0];
    for (uint tap = 1u; tap <= taps; ++tap) {
        float2 delta = step * float(tap);
        float4 forward, backward;
        if (onGrid) {
            int2 offset = int2(round(delta));
            forward = texelClamped(source, position.x + offset.x, position.y + offset.y);
            backward = texelClamped(source, position.x - offset.x, position.y - offset.y);
        } else {
            forward = sampleBilinear(source, float2(position) + delta);
            backward = sampleBilinear(source, float2(position) - delta);
        }
        sum += (forward + backward) * weights[tap];
    }
    return sum;
}

/// Bloom's bright pass: the whole premultiplied texel scaled by how far its `Lum` sits above the
/// threshold.
///
/// Scaling the premultiplied vector — rather than the colour — is what puts the brightness into
/// *coverage*, so the blur that follows spreads a dim pixel less than a bright one without either
/// kernel knowing that is what it is doing. `Lum` is read from the unpremultiplied colour, because how
/// bright a pixel is, is a question about its colour and not about how much of it is there.
static inline float4 bloomThreshold(texture2d<float, access::read> source,
                                    constant EffectParams &params, uint2 gid) {
    float4 texel = source.read(gid);
    if (!(texel.a > 0.0f)) { return float4(0.0f); }
    float weight = saturate((lum(saturate(texel.rgb / texel.a)) - params.threshold)
                            / max(1.0f - params.threshold, 1e-4f));
    return texel * weight;
}

/// Bloom's combine: the original image plus the blurred bright pass, additively, in premultiplied space.
///
/// `rgb` is re-clamped against the summed alpha afterwards. Addition can push a channel above the
/// coverage carrying it, which is not a representable premultiplied colour and would surface much later
/// as an unpremultiply above 1 in whatever read the texture next.
static inline float4 bloomCombine(texture2d<float, access::read> glow,
                                  texture2d<float, access::read> original,
                                  constant EffectParams &params, uint2 gid) {
    float4 base = original.read(gid);
    float4 light = glow.read(gid);
    float alpha = saturate(base.a + light.a * params.intensity);
    return float4(min(saturate(base.rgb + light.rgb * params.intensity), alpha), alpha);
}

/// The 3×3 Sobel gradient magnitude of `Lum`, read on the **premultiplied** texel — never
/// unpremultiplied, the same convention `blur1D` follows — so a coverage edge and a colour edge are the
/// same kind of gradient to this kernel. Clamp-to-edge at the border, matching every other gather here.
///
/// Output is `(m, m, m, m)`: trivially a valid premultiplied colour (`rgb == a`), which is why Sobel is
/// one of the effects `Effect.reshapesCoverage` names rather than a grade.
static inline float4 sobel(texture2d<float, access::read> source, constant EffectParams &params, uint2 gid) {
    int x = int(gid.x), y = int(gid.y);
    float tl = lum(texelClamped(source, x - 1, y - 1).rgb);
    float tc = lum(texelClamped(source, x,     y - 1).rgb);
    float tr = lum(texelClamped(source, x + 1, y - 1).rgb);
    float ml = lum(texelClamped(source, x - 1, y    ).rgb);
    float mr = lum(texelClamped(source, x + 1, y    ).rgb);
    float bl = lum(texelClamped(source, x - 1, y + 1).rgb);
    float bc = lum(texelClamped(source, x,     y + 1).rgb);
    float br = lum(texelClamped(source, x + 1, y + 1).rgb);
    // Gx = [[-1,0,1],[-2,0,2],[-1,0,1]], Gy = [[-1,-2,-1],[0,0,0],[1,2,1]] (y downward).
    float gx = (tr - tl) + 2.0f * (mr - ml) + (br - bl);
    float gy = (bl + 2.0f * bc + br) - (tl + 2.0f * tc + tr);
    float magnitude = sqrt(gx * gx + gy * gy);
    float m = saturate(magnitude * params.amount);
    return float4(m, m, m, m);
}

/// Sharpen's combine: `original + amount · (original − blur)`, on the full premultiplied vector —
/// **exactly `bloomCombine`'s shape**, with the blurred pass standing in for the glow and `amount` for
/// the intensity. The difference can be negative as well as positive, so — like an additive bloom — the
/// sum can overshoot `[0, 1]` in either direction (the halo), and is clamped and re-imposed the same way.
static inline float4 sharpenCombine(texture2d<float, access::read> blurred,
                                    texture2d<float, access::read> original,
                                    constant EffectParams &params, uint2 gid) {
    float4 base = original.read(gid);
    float4 blur = blurred.read(gid);
    float4 diff = base - blur;
    float4 out = base + diff * params.amount;
    float alpha = saturate(out.a);
    return float4(min(saturate(out.rgb), alpha), alpha);
}

/// Outline, outside mode: a pixel already in the shape (`alpha > threshold`) is returned unchanged —
/// the containment rule. A pixel outside it becomes fully opaque `(colorR, colorG, colorB, 1)` if some
/// in-shape pixel lies within `amount` (the resolved fractional width — carried here rather than in
/// `taps`, which is a uint and would truncate it) Euclidean pixels away, and is returned unchanged
/// otherwise.
///
/// A direct `O((2r+1)²)` search, not a distance transform — see `Effect.maxOutlineRadius` for why its
/// cost is capped separately from a blur's.
static inline float4 outline(texture2d<float, access::read> source, constant EffectParams &params, uint2 gid) {
    float4 src = source.read(gid);
    if (src.a > params.threshold) { return src; }

    int width = int(source.get_width()), height = int(source.get_height());
    int x = int(gid.x), y = int(gid.y);
    float radius = params.amount;
    float radiusSquared = radius * radius;
    int searchRadius = int(ceil(radius));

    bool found = false;
    for (int dy = -searchRadius; dy <= searchRadius && !found; ++dy) {
        for (int dx = -searchRadius; dx <= searchRadius; ++dx) {
            if (float(dx * dx + dy * dy) > radiusSquared) { continue; }
            int nx = x + dx, ny = y + dy;
            if (nx < 0 || nx >= width || ny < 0 || ny >= height) { continue; }
            if (source.read(uint2(uint(nx), uint(ny))).a > params.threshold) { found = true; break; }
        }
    }
    if (!found) { return src; }
    return float4(params.colorR, params.colorG, params.colorB, 1.0f);
}

/// One pass of one effect over one texture — the kernel both §4.4 wrappers reach, and the only one they
/// need whether the effect runs once or four times.
///
/// `original` is the effect's own input, unchanged by any earlier pass, and equals `source` on pass 0.
/// Only `kEffectBloomCombine` reads it, but it is bound for every pass so the binding contract does not
/// vary by kind — the same rule `lut` follows.
///
/// Dispatched with `dispatchThreads` like every kernel above, so out-of-bounds threads are never
/// launched and there is no bounds check to pay for.
kernel void applyEffect(texture2d<float, access::read>  source   [[texture(0)]],
                        texture2d<float, access::write> result   [[texture(1)]],
                        texture2d<float, access::read>  original [[texture(2)]],
                        constant uint                  &kind     [[buffer(0)]],
                        constant EffectParams          &params   [[buffer(1)]],
                        constant uchar4                *lut      [[buffer(2)]],
                        constant float                 *weights  [[buffer(3)]],
                        uint2 gid [[thread_position_in_grid]])
{
    // The kernels that read a neighbourhood, or a second texture, need the alpha of texels other than
    // this one — so they answer for the whole pixel rather than fitting the unpremultiply / regrade /
    // re-premultiply wrapper below.
    if (kind == kEffectChromaticAberration) {
        result.write(chromaticAberration(source, params, gid), gid);
        return;
    }
    if (kind == kEffectBlur1D) {
        result.write(blur1D(source, params, weights, gid), gid);
        return;
    }
    if (kind == kEffectBloomThreshold) {
        result.write(bloomThreshold(source, params, gid), gid);
        return;
    }
    if (kind == kEffectBloomCombine) {
        result.write(bloomCombine(source, original, params, gid), gid);
        return;
    }
    if (kind == kEffectSobel) {
        result.write(sobel(source, params, gid), gid);
        return;
    }
    if (kind == kEffectSharpenCombine) {
        result.write(sharpenCombine(source, original, params, gid), gid);
        return;
    }
    if (kind == kEffectOutline) {
        result.write(outline(source, params, gid), gid);
        return;
    }

    float4 src = source.read(gid);
    float alpha = src.a;
    // A fully transparent pixel has no colour to unpremultiply, and both backends have to give the
    // same non-answer.
    if (!(alpha > 0.0f)) { result.write(float4(0.0f), gid); return; }

    float3 colour = saturate(src.rgb / alpha);
    float3 graded = saturate(effectChannels(kind, params, lut, colour, gid));
    result.write(float4(graded * alpha, alpha), gid);
}

// MARK: - The projective warp
//
// ADD_TEXT.md §3 stage 5's bake. One dispatch, one destination pixel per thread, the inverse
// homography and a `1/w` divide — "the same function shape as the existing `sampleBilinear()` /
// `texelClamped()` helpers".
//
// **A compute kernel doing its own perspective divide is the only thing that fits this codebase, and
// it fits cleanly.** ADD_TEXT.md §1: there are zero `MTLRenderPipelineState` and zero
// `drawPrimitives` in the tree and 29 `MTLComputePipelineState` hits, so there is no rasteriser to
// hand a quad to and no vertex stage to interpolate `1/w` for us. §2 records why Core Image's
// `CIPerspectiveTransform` was rejected rather than adopted: it would bring a `CIContext` with its
// own device, queue, kernel cache and intermediate pool, unbudgeted and invisible to
// `CompositorBudget.hasHeadroom`, into a process sized against 192 MiB on a 3 GB device where jetsam
// rather than `makeTexture` is the failure mode.

/// The nine floats of the inverse homography, destination texels to source texels.
///
/// The destination's origin and its scale are folded in on the Swift side (`ImageWarp.inverseTexelMap`)
/// rather than passed separately, so there is exactly one place the composition can be wrong and both
/// backends read the same nine numbers. Layout must match `WarpParams` in `Engine/ImageWarp.swift`.
struct WarpParams {
    float m0, m1, m2;
    float m3, m4, m5;
    float m6, m7, m8;
};

/// Bilinear, **transparent** outside the source rather than clamped to its edge, on premultiplied
/// texels.
///
/// The one place this departs from `sampleBilinear` above, and it is not a preference: the source of
/// a text warp is a glyph bitmap that a sized box has clipped, so its edge texels can be opaque ink.
/// Clamping would smear that ink outwards as an infinite skirt across the whole destination. A sprite
/// warp wants nothing at all outside its own rectangle.
///
/// `position` is already offset by −0.5, i.e. it is in "texel index" space where index `i` sits at
/// the centre of texel `i`.
static inline float4 sampleBilinearTransparent(texture2d<float, access::read> source, float2 position) {
    int width = int(source.get_width()), height = int(source.get_height());
    float2 base = floor(position);
    float2 fraction = position - base;
    int x = int(base.x), y = int(base.y);

    float4 t00 = float4(0.0f), t10 = float4(0.0f), t01 = float4(0.0f), t11 = float4(0.0f);
    bool x0 = x >= 0 && x < width, x1 = (x + 1) >= 0 && (x + 1) < width;
    bool y0 = y >= 0 && y < height, y1 = (y + 1) >= 0 && (y + 1) < height;
    if (x0 && y0) { t00 = source.read(uint2(uint(x), uint(y))); }
    if (x1 && y0) { t10 = source.read(uint2(uint(x + 1), uint(y))); }
    if (x0 && y1) { t01 = source.read(uint2(uint(x), uint(y + 1))); }
    if (x1 && y1) { t11 = source.read(uint2(uint(x + 1), uint(y + 1))); }

    float4 top = mix(t00, t10, fraction.x);
    float4 bottom = mix(t01, t11, fraction.x);
    return mix(top, bottom, fraction.y);
}

/// One destination pixel of a projective warp.
///
/// The rule, stated identically in `ImageWarp.warp`'s doc comment so the two implementations can be
/// checked against one sentence rather than against each other's code:
///
/// 1. The destination pixel's **centre** is `(x + 0.5, y + 0.5)`.
/// 2. `w = m6·x + m7·y + m8`; **discard where `w <= 0`** — the far side of the vanishing line, which
///    has no source at all. Writing transparent there rather than sampling something is what keeps a
///    corner dragged past the horizon from producing plausible-looking garbage.
/// 3. `(u, v)` is the numerator over `w`, in source texel coordinates.
/// 4. Bilinear over the four texels around `(u − 0.5, v − 0.5)`, transparent outside.
kernel void warpHomography(texture2d<float, access::read>  source [[texture(0)]],
                           texture2d<float, access::write> result [[texture(1)]],
                           constant WarpParams &params [[buffer(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= result.get_width() || gid.y >= result.get_height()) { return; }
    float2 p = float2(gid) + 0.5f;
    float w = params.m6 * p.x + params.m7 * p.y + params.m8;
    if (!(w > 0.0f)) { result.write(float4(0.0f), gid); return; }
    float inv = 1.0f / w;
    float u = (params.m0 * p.x + params.m1 * p.y + params.m2) * inv;
    float v = (params.m3 * p.x + params.m4 * p.y + params.m5) * inv;
    result.write(sampleBilinearTransparent(source, float2(u, v) - 0.5f), gid);
}
