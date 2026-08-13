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
// of the fourteen through both backends, and a code that disagreed would show up there as one mode
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

/// Fills a texture with a constant premultiplied colour — the canvas background, the initial clear
/// when there is none, and the transparent start of every buffered group's scratch texture.
kernel void compositeFill(texture2d<float, access::write> result [[texture(0)]],
                          constant float4                &color  [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]])
{
    result.write(color, gid);
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
