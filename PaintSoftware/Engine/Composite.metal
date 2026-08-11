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

/// Source-over of one layer onto a backdrop, at `opacity`.
///
/// Dispatched with `dispatchThreads`, so out-of-bounds threads are never launched and the kernel
/// needs no bounds check — the same assumption `Fill.metal`'s kernels make.
kernel void compositeOver(texture2d<float, access::read>  backdrop [[texture(0)]],
                          texture2d<float, access::read>  layer    [[texture(1)]],
                          texture2d<float, access::write> result   [[texture(2)]],
                          constant float                 &opacity  [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]])
{
    float4 dst = backdrop.read(gid);
    float4 src = layer.read(gid) * opacity;
    result.write(fma(dst, 1.0f - src.a, src), gid);
}

/// Fills a texture with a constant premultiplied colour — the canvas background, and the initial
/// clear when there is none.
kernel void compositeFill(texture2d<float, access::write> result [[texture(0)]],
                          constant float4                &color  [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]])
{
    result.write(color, gid);
}
