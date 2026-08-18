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

// The lasso fill's seed: **every** open pixel the drawn loop encircles, instead of the one pixel a
// tap lands on. That single substitution is the whole of the lasso mode's flood.
//
// Two consequences, and they are the owner's two sentences about the tool. Seeding the loop's whole
// interior means a loop spanning several compartments seeds each of them, so they all flood at once
// — "the flood lasso fills two compartments". And because the flood grows outward from those seeds
// through open pixels, its edge lands on the artwork's own silhouette wherever the artwork is what
// stops it, so gap closing does its usual work exactly there and nowhere else — "it bridges gaps
// only on the outermost encirclement".
//
// Walls are still walls to the *flood*; what makes the interior lines vanish is the union with the
// loop mask after the flood converges (see `MetalFillSession.fill`), which paints every pixel inside
// the loop, artwork included. So a line between two encircled compartments is filled, while the same
// line outside the loop still bounds the region.
kernel void floodInitFromLasso(const device uchar* wall   [[buffer(0)]],
                               device uchar*        region [[buffer(1)]],
                               constant FillParams& params [[buffer(2)]],
                               const device uchar*  lasso  [[buffer(3)]],
                               uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    region[i] = (lasso[i] != 0 && wall[i] == 0) ? 1 : 0;
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
