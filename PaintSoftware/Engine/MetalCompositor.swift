import UIKit
import Metal

// MARK: - The GPU backend
//
// §5.1's argument for Metal is per-pixel blend math over 4.2M pixels at 2048² (16.8M at 4000²), per
// node, per frame — which CoreGraphics cannot do at interactive rates. None of that math exists yet:
// phase 2's job is the substrate and the flag, phases 5 and 7 are the blend modes that need the GPU,
// and phase 9 the effects.
//
// **One correction to the plan's framing, recorded because it changes what this file costs.** §5.1
// says "the infrastructure already ships: MetalFillEngine owns a device, queue, and nine compute
// pipelines" and calls the compositor "a second consumer of an existing dependency". The device,
// queue and library loading are indeed reusable patterns — but `MetalFillEngine` is built entirely on
// `MTLBuffer`, and there is no `MTLTexture` anywhere in this codebase, nor a `texture2d` parameter in
// `Fill.metal`. The texture pool, the version-keyed upload cache, and the readback path §5.1 and §5.3
// describe are new machinery, not a second consumer of old machinery. The conventions that *do*
// carry over are the pixel ones, and they carry over exactly: device RGB, premultiplied-last, 8 bits
// per component, row-major, scale 1 — shared by `PixelOps`, `RasterLayerTexture`, `MetalFillEngine`
// and the fill's byte round-trip alike.

enum MetalCompositor {

    /// Composites `request` on the GPU, or returns nil if it cannot — no device, no shader library,
    /// or a command buffer that failed. `Compositor.composite` treats nil as "use the CPU reference",
    /// so every nil here is a slow frame rather than a missing one.
    ///
    /// **Returns nil unconditionally today: the kernel is not written yet.** This file exists now,
    /// ahead of its shader, so the flag, the fallback, and the seam they hang off are real and
    /// exercised by the parity tests rather than being introduced later alongside GPU code that would
    /// then be the only suspect when something disagreed.
    static func composite(_ request: RenderRequest) -> CGImage? {
        nil
    }
}
