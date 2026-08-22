#include <metal_stdlib>
using namespace metal;

// Shared parameter block for every fill kernel. Field order/padding is mirrored exactly by
// `MetalFillEngine.FillParams` on the Swift side (SIMD4 forces 16-byte alignment → seedColor at
// offset 32, fillColor at 48, total size 64).
struct FillParams {
    uint  width;
    uint  height;
    uint  seedX;
    uint  seedY;
    float threshold;    // 0..1 normalized colour distance above which a pixel is a wall
    float gapRadius;    // px, disk radius for the morphological close (gap bridging)
    float edgeOverlap;  // px, disk radius the filled region grows under the walls
    /// px the *artwork rect* is inset from this buffer on all four sides — `CanvasManager.canvasPadding`
    /// when "Canvas Edge Is a Boundary" is on, and 0 when it is off or there is no padding. 0 means the
    /// artwork rect and the buffer coincide, which is the pre-padding world: every rule keyed off this
    /// then reduces algebraically to the buffer rim it used to name. Occupies the slot that used to be
    /// `_pad0`, so the struct layout is unchanged on both sides.
    float edgeInset;
    float4 seedColor;   // straight RGBA 0..1 sampled at the seed
    float4 fillColor;   // premultiplied RGBA 0..1 painted into the region
};

static inline uint pixelIndex(uint x, uint y, uint w) { return y * w + x; }

// Normalized RGBA distance in 0..1 (max possible distance is sqrt(4) = 2, so halve).
static inline float colourDistance(float4 a, float4 b) {
    float4 d = a - b;
    return sqrt(dot(d, d)) * 0.5;
}

// MARK: - Walls

// A pixel is a wall when its colour differs from the seed colour by more than `threshold`. This is
// what makes the fill stop at colour borders (and recolour a flat-filled region: its interior is
// uniform → not walls → floods, while its border differs → walls).
//
// **One reference colour per dispatch, deliberately, even though the lasso fill has up to two.**
// LASSO_FILL.md §6 step 3 defines the reached set as the union over `c ∈ C` of *per-colour*
// reachability — a path may not switch reference colours halfway — so the lasso runs this kernel
// (and the close, and the flood) once per reference against its own buffers, rather than widening
// the test here to "passable under any `c`". Merging them into one passability field would let a
// collar walk paper → flat → paper and hold out an interior pocket the spec says to fill.
kernel void computeWalls(const device uchar4* reference [[buffer(0)]],
                         device uchar*        wall      [[buffer(1)]],
                         constant FillParams& params    [[buffer(2)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    float4 c = float4(reference[i]) / 255.0;
    wall[i] = colourDistance(c, params.seedColor) > params.threshold ? 1 : 0;
}

// MARK: - Jump Flooding Algorithm (approximate Euclidean distance transform)

// Seed each pixel whose mask equals `seedValue` with its own coordinate; everything else gets a
// far-away sentinel. seedValue = 1 seeds on the walls (for the dilate distance); seedValue = 0 seeds
// on the background (for the erode distance, i.e. distance to the nearest non-set pixel).
kernel void jfaInit(const device uchar*  mask      [[buffer(0)]],
                    device float2*        coord     [[buffer(1)]],
                    constant FillParams&  params    [[buffer(2)]],
                    constant uint&        seedValue [[buffer(3)]],
                    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    coord[i] = (uint(mask[i]) == seedValue) ? float2(gid) : float2(1e20);
}

// One JFA pass at the given step: adopt the nearest seed coordinate among the 8 neighbours at
// distance `step`. Repeated with step = W/2, W/4, ... 1 this converges to (near-)exact nearest-seed.
kernel void jfaStep(const device float2* inCoord  [[buffer(0)]],
                    device float2*        outCoord [[buffer(1)]],
                    constant FillParams&  params   [[buffer(2)]],
                    constant uint&        step     [[buffer(3)]],
                    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    float2 pos = float2(gid);
    float2 best = inCoord[i];
    float bestD = distance_squared(pos, best);
    int s = int(step);
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int nx = int(gid.x) + dx * s;
            int ny = int(gid.y) + dy * s;
            if (nx < 0 || ny < 0 || nx >= int(params.width) || ny >= int(params.height)) continue;
            float2 cand = inCoord[pixelIndex(uint(nx), uint(ny), params.width)];
            float d = distance_squared(pos, cand);
            if (d < bestD) { bestD = d; best = cand; }
        }
    }
    outCoord[i] = best;
}

// Threshold a JFA distance field into a binary mask. `keepInside` picks the morphology op:
//   dilate → out = (distanceToSeed <= radius)      (keepInside = 1)
//   erode  → out = (distanceToSeed  > radius)      (keepInside = 0)
kernel void thresholdDistance(const device float2* coord      [[buffer(0)]],
                              device uchar*         out        [[buffer(1)]],
                              constant FillParams&  params     [[buffer(2)]],
                              constant float&       radius     [[buffer(3)]],
                              constant uint&        keepInside [[buffer(4)]],
                              uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    float d = distance(float2(gid), coord[i]);
    bool inside = d <= radius;
    out[i] = (keepInside ? inside : !inside) ? 1 : 0;
}

// MARK: - The canvas edge as a boundary
//
// **"The canvas edge" is the edge of the artwork rect, not the edge of this buffer, and with padding
// those are different rectangles.** `CanvasManager.setCanvasPadding` grows `canvasSize` itself by
// 2*delta and re-places the content, so the buffer rim is the outer edge of the grey margin while the
// border the artist draws across sits `edgeInset` px inside it. Everything below is written against
// the artwork rect `[inset, width-inset) x [inset, height-inset)`; at `inset == 0` the two rectangles
// coincide and each formula collapses to the buffer-rim one it replaced.

/// The artwork rect's inset in whole pixels. Swift already clamps it to `0 <= 2*inset < min(w, h)`;
/// the `max` here is belt-and-braces against a float that arrived negative.
static inline uint insetPixels(constant FillParams& params) {
    return uint(max(params.edgeInset, 0.0f) + 0.5f);
}

/// Whether a pixel is inside the artwork rect (as opposed to out on the padding margin).
static inline bool insideArtworkRect(uint x, uint y, constant FillParams& params) {
    uint inset = insetPixels(params);
    return x >= inset && y >= inset && x + inset < params.width && y + inset < params.height;
}

// Distance from a pixel to the ring one pixel *outside* the artwork rect. With no padding that ring
// is one pixel beyond the buffer: column 0 is 1 away from the ring at x = -1, and so on — the
// original formula, which this reduces to term for term at `inset == 0`. With padding the ring moves
// inward to x = inset-1 / x = width-inset, and the absolute value lets a pixel out on the margin
// measure to the same ring from the other side, so gap-closing seals against the paper edge from
// whichever side the artwork approaches it.
static inline float distanceToCanvasEdge(uint2 gid, constant FillParams& params) {
    float inset = max(params.edgeInset, 0.0f);
    float x = float(gid.x), y = float(gid.y);
    float dx = min(fabs(x - inset + 1.0f), fabs(float(params.width)  - inset - x));
    float dy = min(fabs(y - inset + 1.0f), fabs(float(params.height) - inset - y));
    return min(dx, dy);
}

// **The canvas edge bounds a fill through two separate mechanisms, and this kernel is the second,
// smaller one.** They are kept apart on purpose:
//
//   1. **The barrier** (`floodHoriz`/`floodVert` below). The artwork rect's boundary is a limit on
//      where the flood may *travel*, exactly the way the buffer rim already was. It is
//      unconditional — independent of the gap slider — and it is what stops a fill escaping onto the
//      padding margin. This is the mechanism the artist means by "the canvas is a border".
//   2. **The bridge** (this kernel). Gap-closing may reach *to* that edge, so a stroke that stops a
//      few pixels short of it still seals instead of letting the fill run around its tip. Scoped to
//      the gap radius, and needed even with the barrier in place: the barrier stops a fill leaving
//      the paper, not one running around the end of a bar that never reached the paper's edge.
//
// **The barrier is deliberately not ink in the wall mask.** Adding the rect's boundary to the walls
// before the morphological close would contain the same scenes and would silently cost what the
// paragraph below measures: a closed r-disk cannot reach into a rectangle's interior corner, so every
// corner grows an unfillable notch. Measured on this engine, a 1 px wall ring left 92 px of a blank
// 128x128 canvas unfillable, 23 per corner. A barrier lives *between* pixels instead — it consumes no
// pixel, never enters the dilate/erode, and grows no notch: a blank canvas still fills every pixel of
// its artwork rect.
//
// Wall in the sliver between artwork and the canvas edge, so a boundary stroke that stops just short
// of the border seals against it instead of letting the fill run around its end.
//
// A pixel joins the wall when the nearest artwork *and* the canvas edge are together within the
// gap-closing radius of it — `distanceToWall + distanceToCanvasEdge <= radius`. Walking the straight
// line from the artwork's tip to the border, that sum is the width of the gap the whole way across,
// so the test seals a gap of up to `radius - 1` px and nothing wider, and the sealed patch is a thin
// lens spanning exactly that gap.
//
// **This is deliberately not the same thing as adding the outside of the canvas to the wall set and
// closing that, which was the first implementation and is wrong for the product even though it is
// right for the mathematics.** A true close of "everything outside is wall" rounds off the interior
// corners of the canvas — a disk of radius r that has to stay inside the rectangle can never cover
// the corner pixel — so every corner grows an unfillable notch r px deep *with no artwork present at
// all*, scaling with the slider up to 40 px. Measured: 92 px of a blank 128x128 canvas became
// unfillable, 23 per corner. Keying the bridge off the distance to real artwork removes that
// entirely: with nothing drawn near a border, nothing is added.
//
// It is also purely **additive** — it only ever turns a background pixel into a wall, never the
// reverse — so switching the option on cannot break a fill that already worked *inside* the artwork
// rect. What the option does now take away is the margin: with it on, a fill started on the paper
// stops at the paper's edge rather than spilling onto the grey. That is the reported bug, not a
// regression, and it is the barrier's doing rather than this kernel's.
kernel void edgeBridge(const device float2* wallCoord [[buffer(0)]],
                       device uchar*         out       [[buffer(1)]],
                       constant FillParams&  params    [[buffer(2)]],
                       constant float&       radius    [[buffer(3)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    // The JFA seeds unreached pixels with a 1e20 sentinel rather than an infinity, so a canvas with
    // no walls at all gives a huge finite distance here and simply fails the test.
    float toWall = distance(float2(gid), wallCoord[i]);
    out[i] = (toWall + distanceToCanvasEdge(gid, params) <= radius) ? 1 : 0;
}

// `dst |= src`, for folding the edge bridge into the closed wall mask after the erode has run.
kernel void unionMask(const device uchar* src   [[buffer(0)]],
                      device uchar*        dst   [[buffer(1)]],
                      constant FillParams& params [[buffer(2)]],
                      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    if (src[i]) dst[i] = 1;
}

// MARK: - Flood fill (parallel scanline / span propagation)

kernel void floodInit(const device uchar* wall   [[buffer(0)]],
                      device uchar*        region [[buffer(1)]],
                      constant FillParams& params [[buffer(2)]],
                      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    bool isSeed = (gid.x == params.seedX && gid.y == params.seedY);
    region[i] = (isSeed && wall[i] == 0) ? 1 : 0;
}

// The lasso fill's seed: the passable pixels of the loop's **ring** — the one-pixel collar just
// inside the fence the artist drew — and nothing else. See LASSO_FILL.md §6 step 3.
//
// **This is the reported bug's fix, and it is one line.** The kernel this replaced seeded *every*
// open pixel inside the loop, so a loop drawn *around* a shape (which is what "circle something"
// means) seeded the paper between the fence and the drawing, and the flood ran from there across the
// whole page — the shipped defect, characterized in `LassoFillLogicTests`. Seeding only the ring, and
// confining the flood to the loop (see `lassoBarrier`), makes the flood's extent depend on the loop
// the artist controls rather than on canvas connectivity they do not.
//
// **A stretch of ring lying on ink contributes no seed, and that is not an error condition**
// (LASSO_FILL.md §4 case 1) — it just means the collar has zero width there, which is exactly right:
// the artist drew their fence through the drawing.
//
// The seeds are what the flood grows *from*, and the flood marks what must **not** be filled: the
// paper the fence can walk to. `lassoInvert` then keeps the loop minus everything the flood reached.
// So the loop is emphatically **not** added to the wall set — the flood has to be able to enter the
// ring in order to exclude it — and anyone "simplifying" this by making the loop a wall breaks the
// tool completely: the ring would be unreachable, nothing would be reached, and every loop would
// paint a solid slab of its own shape over the artwork.
kernel void floodInitFromRing(const device uchar* wall   [[buffer(0)]],
                              device uchar*        region [[buffer(1)]],
                              constant FillParams& params [[buffer(2)]],
                              const device uchar*  ring   [[buffer(3)]],
                              uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    region[i] = (ring[i] != 0 && wall[i] == 0) ? 1 : 0;
}

// The wall set the collar flood actually runs against: the artwork's walls, **plus everything
// outside the loop**. LASSO_FILL.md §6 step 3: *"the flood must never leave `loopMask` — that single
// constraint is the whole leak fix."*
//
// A separate buffer rather than a union into the wall set, and the distinction is the one a later
// reader is most likely to collapse. The loop is *not* a wall: its ring pixels are inside `lasso`,
// so they stay floodable and the flood enters them. What the barrier blocks is the pixel *beyond*
// the fence. "The loop is a wall" is a property of the finished result — it comes out of the final
// intersect in `lassoInvert`, not out of the passability field.
kernel void lassoBarrier(const device uchar* closed [[buffer(0)]],
                         const device uchar*  lasso  [[buffer(1)]],
                         constant FillParams& params [[buffer(2)]],
                         device uchar*        out    [[buffer(3)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    out[i] = (closed[i] != 0 || lasso[i] == 0) ? 1 : 0;
}

// One contiguous run of the sweep: forward then backward over `k` in `[k0, k1)`, filling every open
// pixel connected through non-walls to an already-filled one. `stride` is 1 along a row and `width`
// along a column. `prev` starts false at each end, so **splitting a line into runs is exactly what
// makes a barrier**: the flood cannot carry across a run boundary in either direction, and the
// boundary consumes no pixel of its own.
static inline void sweepRun(device uchar* region, const device uchar* wall,
                            uint base, uint stride, uint k0, uint k1,
                            device atomic_uint* changed) {
    if (k1 <= k0) return;
    bool prev = false;
    for (uint k = k0; k < k1; k++) {
        uint i = base + k * stride;
        if (wall[i]) { prev = false; }
        else if (region[i]) { prev = true; }
        else if (prev) { region[i] = 1; atomic_fetch_or_explicit(changed, 1u, memory_order_relaxed); }
    }
    prev = false;
    for (uint k = k1; k-- > k0; ) {
        uint i = base + k * stride;
        if (wall[i]) { prev = false; }
        else if (region[i]) { prev = true; }
        else if (prev) { region[i] = 1; atomic_fetch_or_explicit(changed, 1u, memory_order_relaxed); }
    }
}

// **The barrier, and it is a rectangle rather than four full-width cuts.** A row only crosses the
// artwork rect's left and right edges if the row itself is beside the paper — a row up in the top
// margin crosses no edge of the rect at all, and cutting it would slice the margin into corner
// pieces instead of leaving it the single continuous ring the artist sees. So the split is decided
// **once per line, from the thread's own coordinate**, and the inner loop keeps exactly the cost it
// had: no per-pixel branch, no extra compare.
//
// At `inset == 0` the guard is always true and the cuts land on k == 0 and k == extent, which no
// sweep ever crossed anyway — so the three runs collapse to the one full-line run this used to be,
// and a padding-0 fill is byte-identical to the old code.
static inline uint2 runSplit(uint alongExtent, uint acrossPos, uint acrossExtent,
                             constant FillParams& params) {
    uint inset = insetPixels(params);
    // A degenerate inset leaves no artwork rect to bound anything, so sweep the line whole rather
    // than fence the flood into nothing. Swift already rejects this case; the two agree deliberately.
    if (2u * inset >= alongExtent || 2u * inset >= acrossExtent) return uint2(0u, alongExtent);
    bool crossesTheRect = acrossPos >= inset && acrossPos + inset < acrossExtent;
    return crossesTheRect ? uint2(inset, alongExtent - inset) : uint2(0u, alongExtent);
}

// One thread per row: fill every open pixel in the row that is horizontally connected (through
// non-wall pixels) to an already-filled pixel, sweeping both directions. Whole horizontal spans
// fill in a single pass; the vertical pass then seeds new rows.
kernel void floodHoriz(device uchar*        region  [[buffer(0)]],
                       const device uchar*  wall    [[buffer(1)]],
                       constant FillParams& params  [[buffer(2)]],
                       device atomic_uint*  changed [[buffer(3)]],
                       uint y [[thread_position_in_grid]]) {
    if (y >= params.height) return;
    uint w = params.width;
    uint base = y * w;
    uint2 split = runSplit(w, y, params.height, params);
    sweepRun(region, wall, base, 1u, 0u, split.x, changed);
    sweepRun(region, wall, base, 1u, split.x, split.y, changed);
    sweepRun(region, wall, base, 1u, split.y, w, changed);
}

// One thread per column: the vertical analogue of floodHoriz.
kernel void floodVert(device uchar*        region  [[buffer(0)]],
                      const device uchar*  wall    [[buffer(1)]],
                      constant FillParams& params  [[buffer(2)]],
                      device atomic_uint*  changed [[buffer(3)]],
                      uint x [[thread_position_in_grid]]) {
    if (x >= params.width) return;
    uint w = params.width;
    uint h = params.height;
    uint2 split = runSplit(h, x, params.width, params);
    sweepRun(region, wall, x, w, 0u, split.x, changed);
    sweepRun(region, wall, x, w, split.x, split.y, changed);
    sweepRun(region, wall, x, w, split.y, h, changed);
}

// MARK: - Edge overlap + paint

// Grow the region by a small disk so the fill slips under the anti-aliased wall pixels.
//
// The disk respects the barrier too: a pixel on the padding margin is never grown from a filled
// pixel on the paper, nor the reverse. Without that, edge overlap would paint up to `edgeOverlap` px
// of grey around a fill that the flood had correctly stopped at the paper's edge. At `inset == 0`
// every pixel is inside the artwork rect, so the test is always true and this is the old kernel.
kernel void edgeDilate(const device uchar* region [[buffer(0)]],
                       device uchar*        out    [[buffer(1)]],
                       constant FillParams& params [[buffer(2)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    if (region[i]) { out[i] = 1; return; }
    int r = int(round(params.edgeOverlap));
    if (r <= 0) { out[i] = 0; return; }
    float r2 = params.edgeOverlap * params.edgeOverlap;
    bool onPaper = insideArtworkRect(gid.x, gid.y, params);
    for (int dy = -r; dy <= r; dy++) {
        for (int dx = -r; dx <= r; dx++) {
            if (float(dx * dx + dy * dy) > r2) continue;
            int nx = int(gid.x) + dx;
            int ny = int(gid.y) + dy;
            if (nx < 0 || ny < 0 || nx >= int(params.width) || ny >= int(params.height)) continue;
            if (insideArtworkRect(uint(nx), uint(ny), params) != onPaper) continue;
            if (region[pixelIndex(uint(nx), uint(ny), params.width)]) { out[i] = 1; return; }
        }
    }
    out[i] = 0;
}

kernel void paintRegion(const device uchar* region [[buffer(0)]],
                        device uchar4*       out    [[buffer(1)]],
                        constant FillParams& params [[buffer(2)]],
                        uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    if (region[i]) {
        out[i] = uchar4(clamp(params.fillColor * 255.0 + 0.5, 0.0, 255.0));
    } else {
        out[i] = uchar4(0);
    }
}

// MARK: - The lasso's invert, coverage and empty check (LASSO_FILL.md §6 steps 4–6)

// **`fill = loopMask ∧ ¬reached`, and this single expression is where three separate promises of the
// tool come from.** Read it three times:
//
//  * *"the fill shouldn't even touch the loop"* — nothing outside `lasso` is ever written, so the
//    fence bounds the result absolutely. That is the wall property, and it lives **here**, in the
//    intersect, not in the passability field. Making the loop a wall instead would leave the ring
//    unreachable and paint a slab (see `floodInitFromRing`).
//  * *"all inner lines are filled over"* — the complement includes ink, because ink is not
//    *reached*: the collar flood cannot walk through it. §6 step 4 says so in one line.
//  * *a face's eyes fill with the face* (§4 case 5) — the eyes' interiors are walled off by their own
//    outlines, so the collar never reaches them either. **This is the same line of code**, which is
//    why the spec forbids a connected-component filter on the result: dropping components with no
//    passable pixel would un-fill the eyes and contradict the owner's ruling. An earlier proposal to
//    add one was withdrawn for exactly that reason.
//
// Coverage (§6 step 6) is the second half. A pixel the collar *did* reach is not simply blank: it
// carries `k = clamp((d_min − sT) / (T − sT), 0, 1)`, which is 0 on clean paper and rises to 1 at
// the wall threshold. So the filled silhouette inherits the artwork's own antialiasing — the outer
// fringe of a soft line fades from fill colour to paper exactly as the line faded to paper — instead
// of ending on a hard polygon edge. `spread` is Krita's *Spread*; it is 0 today, which gives the
// plain ramp, and it is an argument rather than a constant so the knob exists if the owner asks for it.
//
// `filled` counts only the unreached pixels — the artist-visible fill — and is the empty check of
// §6 step 5. Counting the coverage ramp too would make a leaked fill (which is *all* collar) look
// non-empty and defeat the whole §7 signal.
kernel void lassoInvert(const device uchar4* reference  [[buffer(0)]],
                        const device uchar*   lasso      [[buffer(1)]],
                        constant FillParams&  params     [[buffer(2)]],
                        const device uchar*   reachedA   [[buffer(3)]],
                        const device uchar*   reachedB   [[buffer(4)]],
                        device uchar*         alphaOut   [[buffer(5)]],
                        device atomic_uint*   filled     [[buffer(6)]],
                        constant float4&      reference2 [[buffer(7)]],
                        constant uint&        refCount   [[buffer(8)]],
                        constant float&       spread     [[buffer(9)]],
                        uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    if (lasso[i] == 0) { alphaOut[i] = 0; return; }

    bool reached = (reachedA[i] != 0) || (refCount > 1u && reachedB[i] != 0);
    if (!reached) {
        alphaOut[i] = 255;
        atomic_fetch_add_explicit(filled, 1u, memory_order_relaxed);
        return;
    }

    float4 c = float4(reference[i]) / 255.0;
    float d = colourDistance(c, params.seedColor);
    if (refCount > 1u) d = min(d, colourDistance(c, reference2));
    float t  = params.threshold;
    float lo = spread * t;
    // A zero-width ramp (threshold 0, or spread 1) degenerates to a step, which is what the limit of
    // the expression is; dividing by it would give a NaN and paint garbage.
    float k = (t > lo) ? clamp((d - lo) / (t - lo), 0.0, 1.0) : (d > lo ? 1.0 : 0.0);
    alphaOut[i] = uchar(clamp(k * 255.0 + 0.5, 0.0, 255.0));
}

// `paintRegion`'s coverage-aware twin: the fill colour scaled by the 8-bit coverage `lassoInvert`
// wrote. `fillColor` is premultiplied, so scaling all four channels by the same `k` keeps it
// premultiplied and the result composites correctly without a second pass.
// **Edge Overlap for the lasso, and it is the same operation as `edgeDilate` rather than its
// opposite** (LASSO_FILL.md §6 step 7). The owner, on device 2026-08-21: *"edge overlap does not work
// on lasso flood fill, and thus the fill bleeds through the anti-aliased edges... moving the edge
// overlap up means the fill gets bigger."*
//
// **What "bleeds through" is, measured rather than reasoned about.** `lassoInvert` paints every
// unreached pixel solid and gives the reached ones `k = d / T`, so along an outer ramp of a=64/160
// against T=0.15 the coverage runs 0, 213, 255 while the artist's line runs 0, 64, 160 — the table in
// `testTheFillsSoftEdgeComesFromTheArtworksOwnAntialiasing`. The fill therefore stops exactly at the
// artwork's own silhouette and never reaches clean paper, which sounds right and is the bug: the fill
// composites *underneath* the line, so at that fringe pixel the stack is 64 over 213 and comes out at
// alpha 223, not 255. The background shows through the drawing's soft edge. That is the identical
// halo Edge Overlap exists to close on a bucket fill; only the side it faces is different, because
// this algorithm is the complement.
//
// So the correction is not to invert the operation. **A max over the disk is a dilate on a greyscale
// mask exactly as `edgeDilate`'s "any neighbour set" is on a binary one**, and it walks the whole
// coverage profile outward by `edgeOverlap` px — full opacity lands where the ramp used to start, and
// the ramp lands on the paper beyond it. Bigger slider, bigger fill, halo gone.
//
// `lasso` is still consulted, and it is not belt-and-braces: growing the result is the one thing that
// could push paint across the fence, and *"the fill shouldn't even touch the loop"* is absolute (see
// `lassoInvert`). The dilate may spread only inside the stencil.
//
// The pixel count for §6 step 5 is deliberately **not** retaken here. It is `lassoInvert`'s answer to
// "what did the loop enclose", and a max over an all-zero neighbourhood is zero, so an empty result
// stays empty however far this is asked to grow it — §7.1's no-undo-entry rule is untouched.
kernel void lassoEdgeDilate(const device uchar* alphaIn  [[buffer(0)]],
                            const device uchar*  lasso    [[buffer(1)]],
                            device uchar*        alphaOut [[buffer(2)]],
                            constant FillParams& params   [[buffer(3)]],
                            uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    if (lasso[i] == 0) { alphaOut[i] = 0; return; }
    uchar best = alphaIn[i];
    int r = int(round(params.edgeOverlap));
    if (r <= 0 || best == 255) { alphaOut[i] = best; return; }
    float r2 = params.edgeOverlap * params.edgeOverlap;
    // The padding rule `edgeDilate` uses, for its reason: the artwork rect's boundary is a boundary,
    // so coverage may not be dragged across it in either direction.
    bool onPaper = insideArtworkRect(gid.x, gid.y, params);
    for (int dy = -r; dy <= r; dy++) {
        for (int dx = -r; dx <= r; dx++) {
            if (float(dx * dx + dy * dy) > r2) continue;
            int nx = int(gid.x) + dx;
            int ny = int(gid.y) + dy;
            if (nx < 0 || ny < 0 || nx >= int(params.width) || ny >= int(params.height)) continue;
            if (insideArtworkRect(uint(nx), uint(ny), params) != onPaper) continue;
            uchar a = alphaIn[pixelIndex(uint(nx), uint(ny), params.width)];
            if (a > best) { best = a; if (best == 255) { alphaOut[i] = 255; return; } }
        }
    }
    alphaOut[i] = best;
}

kernel void paintRegionAlpha(const device uchar* alpha  [[buffer(0)]],
                             device uchar4*       out    [[buffer(1)]],
                             constant FillParams& params [[buffer(2)]],
                             uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    uchar a = alpha[i];
    if (a == 0) { out[i] = uchar4(0); return; }
    float k = float(a) / 255.0;
    out[i] = uchar4(clamp(params.fillColor * k * 255.0 + 0.5, 0.0, 255.0));
}
