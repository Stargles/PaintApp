#include <metal_stdlib>
using namespace metal;

// Shared parameter block for every fill kernel. Field order/padding is mirrored exactly by
// `MetalFillEngine.FillParams` on the Swift side (ten scalars, then SIMD4 forces 16-byte
// alignment → seedColor at offset 48, fillColor at 64, total size 80).
struct FillParams {
    uint  width;
    uint  height;
    uint  seedX;
    uint  seedY;
    float threshold;    // 0..1 normalized colour distance above which a pixel is a wall
    // px, disk radius. **Its direction is the algorithm's, not the field's**: the bucket path grows
    // the filled region under the walls (`edgeDilate`), the lasso path erodes the painted *coverage*
    // back inside the artwork's outer silhouette (`lassoEdgeErode`). Those are the same operation
    // seen from either side of the invert — except on the coverage ramp, which is why the lasso's
    // runs where it does; see `lassoEdgeErode`. 0 is identity in both.
    float edgeOverlap;
    /// The *artwork rect* in this buffer's pixels, `[minX, maxX) x [minY, maxY)` — the paper's own
    /// edge, which is where "Canvas Edge Is a Boundary" fences the flood. A rect rather than one
    /// inset because the buffer is a **window** of the canvas (`FillWindow`, TODO (86)): the paper
    /// can sit anywhere relative to it, including entirely around it. When the option is off the
    /// rect is the buffer itself, and every rule keyed off it reduces algebraically to the buffer rim
    /// it used to name. May extend past the buffer; every reader clamps.
    float artworkMinX;
    float artworkMinY;
    float artworkMaxX;
    float artworkMaxY;
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
// (and its domain and gap closing's basins) once per reference against its own buffers, rather than widening
// the test here to "passable under any `c`". Merging them into one passability field would let a
// collar walk paper → flat → paper and hold out an interior pocket the spec says to fill.
//
// **`pathWall` is TODO (46): a stroke's centre line, drawn in the colour the stroke paints.**
// Premultiplied-last RGBA from `StrokeWallMask.mask` — the same layout as `reference` — non-zero
// alpha along the path of every paint stroke on a vector reference layer, and zero everywhere on a
// raster document. A segmented brush paints a dotted line, so pixel-wise there is no wall between the
// dabs and the flood walks through the gaps; the path is continuous by construction and closes them
// with no radius to guess.
//
// **The path takes the same threshold test the pixels take, and that is not a detail.** Treating it
// as an unconditional wall made a vector layer's **Threshold** slider unable to release a border —
// caught by `FillLiveAdjustUITests.testAdjustingThresholdAfterFillReappliesToUncommittedFill`. With
// the colour carried, the rule is exactly "the path behaves as if the stroke had painted a continuous
// line of its own colour", which is the literal statement of the ask and leaves every control
// downstream meaning what it meant.
//
// Folded in *here* rather than anywhere later because this is the one place the wall set is defined,
// so gap closing, the bucket flood and the lasso's collar flood all obey it without knowing it exists.
kernel void computeWalls(const device uchar4* reference [[buffer(0)]],
                         device uchar*        wall      [[buffer(1)]],
                         constant FillParams& params    [[buffer(2)]],
                         const device uchar4* pathWall  [[buffer(3)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    float4 c = float4(reference[i]) / 255.0;
    float4 p = float4(pathWall[i]) / 255.0;
    bool pathIsWall = p.w > 0.0 && colourDistance(p, params.seedColor) > params.threshold;
    wall[i] = (pathIsWall || colourDistance(c, params.seedColor) > params.threshold) ? 1 : 0;
}

// MARK: - Jump Flooding Algorithm (approximate Euclidean distance transform)

// Seed every wall pixel with its own coordinate; everything else gets a far-away sentinel. The
// jump flood then carries each pixel the coordinate of its nearest wall, which `gapLevels` turns into
// the distance map gap closing is cut from.
kernel void jfaInit(const device uchar*  wall   [[buffer(0)]],
                    device float2*        coord  [[buffer(1)]],
                    constant FillParams&  params [[buffer(2)]],
                    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    coord[i] = wall[i] != 0 ? float2(gid) : float2(1e20);
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

// MARK: - The canvas edge as a boundary
//
// **"The canvas edge" is the edge of the artwork rect, not the edge of this buffer, and the two are
// different rectangles twice over.** With padding, `CanvasManager.setCanvasPadding` grows
// `canvasSize` itself and re-places the content, so the paper's border sits inside the canvas; and
// this buffer is a *window* of that canvas (`FillWindow`), so the paper's border can sit anywhere
// relative to the buffer — inside it, through it, or entirely around it. Everything below is written
// against `[artworkMinX, artworkMaxX) x [artworkMinY, artworkMaxY)` in buffer pixels; when Swift
// hands the buffer itself as the rect each formula collapses to the buffer-rim one it replaced.

/// Whether a pixel is inside the artwork rect (as opposed to out on the padding margin).
static inline bool insideArtworkRect(uint x, uint y, constant FillParams& params) {
    float fx = float(x), fy = float(y);
    return fx >= params.artworkMinX && fx < params.artworkMaxX
        && fy >= params.artworkMinY && fy < params.artworkMaxY;
}

// Distance from a pixel to the ring one pixel *outside* the artwork rect — the paper's edge as gap
// closing's distance map sees it. From inside the rect that is the nearest of its four sides: with the
// rect at the buffer, column 0 is 1 away from the ring at x = -1, and so on. From out on the margin it
// is the distance to the ring's outline, so the paper's edge reads as ink from whichever side the
// artwork approaches it — and the lines the paper's sides run along do not carry on across the
// margin, which they would if the inside formula were used there and would cut the ring into pieces.
static inline float distanceToCanvasEdge(uint2 gid, constant FillParams& params) {
    float x = float(gid.x), y = float(gid.y);
    float left = params.artworkMinX - 1.0f, right = params.artworkMaxX;
    float top = params.artworkMinY - 1.0f, bottom = params.artworkMaxY;
    if (x > left && x < right && y > top && y < bottom) {
        return min(min(x - left, right - x), min(y - top, bottom - y));
    }
    float dx = max(max(left - x, x - right), 0.0f);
    float dy = max(max(top - y, y - bottom), 0.0f);
    return sqrt(dx * dx + dy * dy);
}

// **The canvas edge bounds a fill through two separate mechanisms, and they are kept apart on
// purpose:**
//
//   1. **The barrier** (`fillDomain` below). The artwork rect's boundary is a limit on where a fill
//      may *travel*, exactly the way the buffer rim already was. It is
//      unconditional — independent of the gap slider — and it is what stops a fill escaping onto the
//      padding margin. This is the mechanism the artist means by "the canvas is a border".
//   2. **Ink for gap closing** (`gapLevels`). The paper's edge counts as ink in the distance map gap
//      closing is cut from, so a stroke that stops a few pixels short of it leaves an *opening*
//      between its tip and the edge, sealed like any other once the slider is that wide. Needed even
//      with the barrier in place: the barrier stops a fill leaving the paper, not one running around
//      the end of a bar that never reached the paper's edge.
//
// **The barrier is deliberately not ink in the wall mask.** It lives *between* pixels — it consumes no
// pixel and the flood simply cannot carry across it — so a blank canvas still fills every pixel of its
// artwork rect. And counting the edge as ink in the distance map costs no corner either: gap closing
// seals *openings between two open areas* (`FillBasins`), and a corner of the paper is not one.

// Each open pixel's distance to the nearest ink, in quarter pixels — the distance map `FillBasins`
// partitions the plain fill by (TODO (158)) — capped at `ceiling` (`FillBasins.ceiling`), above which
// no cut the session will be asked for looks. `wallCoord` is the jump flood seeded on the walls; with
// the canvas edge a boundary, the ring one pixel outside the artwork rect is ink too, from whichever
// side the pixel lies. Walls write 0. The JFA's 1e20 sentinel (no walls at all) clamps to the
// ceiling, so an empty canvas is one flat plateau and one basin.
kernel void gapLevels(const device float2* wallCoord        [[buffer(0)]],
                      device ushort*        levels           [[buffer(1)]],
                      constant FillParams&  params           [[buffer(2)]],
                      constant uint&        canvasEdgeIsInk  [[buffer(3)]],
                      constant uint&        ceiling          [[buffer(4)]],
                      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    float d = distance(float2(gid), wallCoord[i]);
    if (canvasEdgeIsInk != 0u) d = min(d, distanceToCanvasEdge(gid, params));
    levels[i] = ushort(clamp(round(d * 4.0), 0.0, float(ceiling)));
}

// The region for one slider value: every pixel whose basin the cut joined to the seed. `labels` is
// `FillBasins`' watershed (−1 outside the plain fill) and `reached` its table for this gap width.
kernel void basinRegion(const device int*   labels  [[buffer(0)]],
                        const device uchar* reached [[buffer(1)]],
                        device uchar*       region  [[buffer(2)]],
                        constant FillParams& params [[buffer(3)]],
                        uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    int basin = labels[i];
    region[i] = basin < 0 ? 0 : reached[basin];
}

// `dst = max(dst, src)`: folds the mend into a fill's coverage. Flags (0 or 1) and coverage (0 to 255)
// are both held to "non-zero is set, and the larger is the stronger".
kernel void unionMask(const device uchar* src   [[buffer(0)]],
                      device uchar*        dst   [[buffer(1)]],
                      constant FillParams& params [[buffer(2)]],
                      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    dst[i] = max(dst[i], src[i]);
}

// MARK: - Where a fill may go

// **The open pixels a fill may cover, each tagged with the compartment it lies in** — the input
// `FillBasins` partitions, which is the whole of the flood: a fill is the basins its seeds reach, and
// a basin is made of open pixels that are neighbours *and* carry the same tag.
//
//   * 0 — a wall, or, for a lasso, a pixel outside the loop the artist drew. Never part of a fill's
//     reach. LASSO_FILL.md §6 step 3: *"the flood must never leave `loopMask` — that single
//     constraint is the whole leak fix."*
//   * 2 — open paper inside the artwork rect; 1 — open paper out on the padding margin. **This is the
//     barrier**, and it is why the canvas edge costs no pixel: the rect's boundary lies *between* two
//     pixels that carry different tags, so nothing walks across it, in either direction, and nothing is
//     consumed. With the option off the rect is the buffer and every pixel is a 2.
//
// **The loop is not a wall.** Its ring pixels lie inside it, so they are open and tagged, and the
// lasso's collar starts from them (`MetalFillSession`'s ring seeds) — anyone "simplifying" this by
// making the loop a wall breaks the tool completely: the ring would be unreachable, nothing would be
// reached, and every loop would paint a solid slab of its own shape over the artwork. "The loop is a
// wall" is a property of the finished result, from the final intersect in `lassoInvert`. A stretch of
// ring lying on ink is simply not open, so it seeds nothing, which is right (LASSO_FILL.md §4 case 1):
// the artist drew their fence through the drawing.
//
// `loop` is bound to `wall` when there is none (`hasLoop` 0), because Metal has no unbound argument.
kernel void fillDomain(const device uchar* wall    [[buffer(0)]],
                       const device uchar* loop    [[buffer(1)]],
                       device uchar*       domain  [[buffer(2)]],
                       constant FillParams& params [[buffer(3)]],
                       constant uint&      hasLoop [[buffer(4)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    bool open = wall[i] == 0 && (hasLoop == 0u || loop[i] != 0);
    domain[i] = open ? (insideArtworkRect(gid.x, gid.y, params) ? 2 : 1) : 0;
}

// MARK: - Edge overlap + paint

// Grow the region by a small disk so the fill slips under the anti-aliased wall pixels. **The
// bucket fill's alone.** The lasso's Edge Overlap is `lassoEdgeErode`, on the far side of the invert,
// and §6 step 7 records why running this one on the collar instead — which is algebraically the same
// operation — is not the same picture.
//
// The disk respects the barrier too: a pixel on the padding margin is never grown from a filled
// pixel on the paper, nor the reverse. Without that, edge overlap would paint up to `edgeOverlap` px
// of grey around a fill that the flood had correctly stopped at the paper's edge. With the rect at the buffer
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
//    unreachable and paint a slab (see `fillDomain`).
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
// **This kernel does not count, and that is deliberate.** §6 step 5's empty check is taken by
// `lassoEdgeErode`, which runs after it on every fill — see that kernel for why the count has to be
// downstream of Edge Overlap and why it is dispatched unconditionally.
kernel void lassoInvert(const device uchar4* reference  [[buffer(0)]],
                        const device uchar*   lasso      [[buffer(1)]],
                        constant FillParams&  params     [[buffer(2)]],
                        const device uchar*   reachedA   [[buffer(3)]],
                        const device uchar*   reachedB   [[buffer(4)]],
                        device uchar*         alphaOut   [[buffer(5)]],
                        constant float4&      reference2 [[buffer(6)]],
                        constant uint&        refCount   [[buffer(7)]],
                        constant float&       spread     [[buffer(8)]],
                        uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    if (lasso[i] == 0) { alphaOut[i] = 0; return; }

    bool reached = (reachedA[i] != 0) || (refCount > 1u && reachedB[i] != 0);
    if (!reached) { alphaOut[i] = 255; return; }

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

// **Edge Overlap for the lasso: an erosion of the coverage, and it is the owner's own algorithm
// written on the side of the invert where the coverage exists.** They described it as growing the
// collar before inverting it — *"before it inverts the fill, the edge overlap should expand that
// fill, so that lower values make the fill expand further into the lines. Then it inverts it"* — and
// that is exactly right: dilating a set and eroding its complement are the same operation, so the
// two forms agree wherever the thing being operated on is a *set*.
//
// **They part company on step 6's ramp, because the fill is not a set — it is an alpha.** The collar
// is a bit per pixel; the fill's soft edge is 8 bits of coverage that only exists after the invert.
// A *binary* dilation of the collar therefore cannot see the fade and leaves it behind. Measured
// 2026-08-22 on `rampWalledBox` along y = 60, artwork 0/64/160/255, slider 4:
//
//     erode the coverage:      0,   0,   0, 213, 255, 255, 255
//     dilate the binary collar: 0, 213,   0,   0, 255, 255, 255
//
// The second strands the artwork's own fringe one pixel outside the line with bare ink between it
// and the fill, which reads on screen as a detached halo. Eroding the coverage carries the 213
// inward with the boundary, which is what an artist means by the colour tucking under the line.
// `testLoweringEdgeOverlapTucksTheColourUnderTheLine` pins both the profile and the shape property
// ("one contiguous run"), and the halo fails the second at every setting below the top.
//
// **The slider did not change direction; its range moved.** Up is still more colour. What moved is
// where the top of the range sits: `CanvasManager.fillEdgeRadius(lasso:)` hands this kernel
// `fillExpandRange.upperBound - v`, so v = 6 is radius 0 — byte-identical to the old v = 0 — and
// v = 0 is a 6 px retreat. No setting can put paint outside the artwork's silhouette, which is the
// owner's ruling of 2026-08-21.
//
// **The fence is exempt from the erosion; the ink is not.** An out-of-loop neighbour is *skipped*
// rather than counted as zero, so a pixel with no in-loop neighbour keeps its own coverage. The
// asymmetry is the whole point: ink is something the artist drew and can watch the colour retreat
// under, while the fence is a gesture that vanishes on lift (§6 step 1) and has nothing to tuck
// beneath. Letting it erode left an unfilled sliver wherever the fill legitimately reached the loop
// — a lasso drawn through a filled area, where the ring pixels on ink are not passable and so are
// never reached — which is the pale seam this whole setting exists to remove.
// `testALoopDrawnThroughAFilledAreaLeavesNoSliverAlongTheLoop` is the regression. Exempting the
// fence cannot violate §3's *"the fill shouldn't even touch the loop"*: shrinking never pushes paint
// across a boundary, and out-of-loop pixels are still written 0 by the stencil on the first line.
//
// The `insideArtworkRect` guard stays as it was and is a different rule: coverage may not be dragged
// across the artwork rect's boundary in either direction, so a fill correctly stopped at the paper's
// edge does not erode against the padding margin.
//
// **The pixel count for §6 step 5 is taken here and nowhere else, and this kernel is dispatched on
// every fill including at radius 0**, where it is an identity copy. Both halves matter:
//
//  * *Downstream*, because an erosion can turn a non-empty result **empty** — lasso a 5 px hatch line
//    with the slider at the bottom and every painted pixel goes. A count taken before it would commit
//    an invisible fill and eat an undo slot, which §7.1 forbids.
//  * *Unconditional*, because the version that shipped on 2026-08-21 dispatched this only at radius
//    ≥ 1 and kept a second counter slot for the radius-0 case. The Swift side then chose between the
//    two slots — and read slot 1 while this kernel's atomic wrote slot 0, so every radius ≥ 1
//    reported an empty fill. That is what reached the owner's iPad as *"it gives an error for nothing
//    enclosed … and refuses to fill anything"*. One kernel that always runs and always counts has
//    nowhere for that bug to live. `testTheEmptyCheckIsNonZeroAtEveryEdgeOverlapSetting` is the
//    regression, and it fails against the shipped code at every setting except the top.
kernel void lassoEdgeErode(const device uchar* alphaIn  [[buffer(0)]],
                           const device uchar*  lasso    [[buffer(1)]],
                           device uchar*        alphaOut [[buffer(2)]],
                           constant FillParams& params   [[buffer(3)]],
                           device atomic_uint*  filled   [[buffer(4)]],
                           uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    if (lasso[i] == 0) { alphaOut[i] = 0; return; }
    uchar least = alphaIn[i];
    int r = int(round(params.edgeOverlap));
    // Radius 0 is exactly identity, which is what makes the top of the slider provably the old zero
    // — and it still counts, because this kernel is the only thing that does.
    if (r <= 0 || least == 0) {
        alphaOut[i] = least;
        if (least == 255) atomic_fetch_add_explicit(filled, 1u, memory_order_relaxed);
        return;
    }
    float r2 = params.edgeOverlap * params.edgeOverlap;
    bool onPaper = insideArtworkRect(gid.x, gid.y, params);
    for (int dy = -r; dy <= r; dy++) {
        for (int dx = -r; dx <= r; dx++) {
            if (float(dx * dx + dy * dy) > r2) continue;
            int nx = int(gid.x) + dx;
            int ny = int(gid.y) + dy;
            if (nx < 0 || ny < 0 || nx >= int(params.width) || ny >= int(params.height)) continue;
            if (insideArtworkRect(uint(nx), uint(ny), params) != onPaper) continue;
            uint n = pixelIndex(uint(nx), uint(ny), params.width);
            // The fence is exempt: skip the neighbour rather than let its 0 pull the minimum down.
            if (lasso[n] == 0) continue;
            uchar a = alphaIn[n];
            if (a < least) { least = a; if (least == 0) { alphaOut[i] = 0; return; } }
        }
    }
    alphaOut[i] = least;
    if (least == 255) atomic_fetch_add_explicit(filled, 1u, memory_order_relaxed);
}

// `paintRegion`'s coverage-aware twin: the fill colour scaled by the 8-bit coverage `lassoInvert`
// wrote and `lassoEdgeErode` then pulled back. `fillColor` is premultiplied, so scaling
// all four channels by the same `k` keeps it premultiplied and the result composites correctly
// without a second pass.
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

// MARK: - Mending the gap to a neighbouring fill (TODO (113))
//
// **The seam, and why it exists at all.** A flood stops at the antialiased edge of the line it meets,
// on whichever side it started. Two fills either side of one line therefore each stop at their own
// side's edge, plus the few pixels Edge Overlap tucks under it — and the strip under the line's core
// belongs to neither. A lasso pair has the same strip for the same reason: each loop's fence stops at
// the line's near side. The mend is the third thing a fill can do about it, after Edge Overlap's
// uniform disk: grow *only* where the colour on the other side of the line already is.
//
// **The rule: a pixel is mended when, along some straight line through it, ink runs unbroken from
// this fill to the neighbour — and no wider than the reach.** That is the seam, exactly: the
// divider's own pixels between two cells qualify, and nothing else does. A radius cannot say it — a
// dilation by half the reach leaves a strip against each side of a seam wider than that — and neither
// can a distance to the nearest fill, which paints the outline of a shape whose far side is *paper*
// because a fill happens to be 14 px away across it, or the stretch of a frame's edge that runs on
// past a divider with the neighbour only ever beside it. In each of those the run meets paper, or the
// wrong end of a corner, so no line through the pixel joins the two. "Never onto open paper" is the
// same fact: paper is not ink, so no run crosses it.
//
// Four axes, each walked both ways, find a crossing at whatever angle the line was drawn: some axis is
// within 22.5 degrees of square on to it, so the run is at most 8% longer than the line is thick.
//
// **The reach counts from the fill as Edge Overlap leaves it.** The mend runs after the overlap has
// tucked each fill under the line, so the two add: a fill's own overlap never eats into the reach, and
// a seam the overlap already closed is simply one with nothing left to mend.
//
// **The neighbour is not painted over.** Its pixels end a run and are never mended themselves.

/// Whether the mend may walk through here: ink under every reference. `wall2` is only read when the
/// lasso has a second reference colour (`refCount > 1`), where a pixel is paper if it is passable
/// under *either*.
static inline bool mendIsInk(uint i, const device uchar* wall, const device uchar* wall2, uint refCount) {
    return wall[i] != 0 && (refCount < 2u || wall2[i] != 0);
}

/// Where a walk from a pixel ends, as `(what, steps)`: bit 1 of `what` is this fill, bit 2 the
/// neighbour (a pixel can be both, where Edge Overlap tucked this fill over the neighbour's edge), and
/// 0 means the walk met paper, the barrier or the buffer's rim first. `steps` counts to the pixel the
/// walk ended on.
static inline uint2 mendRun(uint2 from, int dx, int dy, int limit, bool onPaper,
                            const device uchar* painted, const device uchar* neighbour,
                            const device uchar* wall, const device uchar* wall2,
                            constant FillParams& params, uint refCount) {
    for (int k = 1; k <= limit; k++) {
        int nx = int(from.x) + dx * k;
        int ny = int(from.y) + dy * k;
        if (nx < 0 || ny < 0 || nx >= int(params.width) || ny >= int(params.height)) break;
        // The barrier lies between pixels: a run that crossed it would join colour on the paper to
        // colour on the margin, which `edgeDilate` and `lassoEdgeErode` do not do either.
        if (insideArtworkRect(uint(nx), uint(ny), params) != onPaper) break;
        uint n = pixelIndex(uint(nx), uint(ny), params.width);
        uint what = (painted[n] != 0 ? 1u : 0u) | (neighbour[n] != 0 ? 2u : 0u);
        if (what != 0) return uint2(what, uint(k));
        if (!mendIsInk(n, wall, wall2, refCount)) break;
    }
    return uint2(0, 0);
}

// Writes 255 where the pixel is to be mended and 0 everywhere else, into a buffer of its own: the walks
// read `painted` at every other pixel, so mending in place would make each answer depend on which
// thread had run first. `unionMask` folds the result in. `reach` is in pixels.
kernel void mendGap(const device uchar* painted   [[buffer(0)]],
                    const device uchar* neighbour [[buffer(1)]],
                    const device uchar* wall      [[buffer(2)]],
                    const device uchar* wall2     [[buffer(3)]],
                    device uchar*       mended    [[buffer(4)]],
                    constant FillParams& params   [[buffer(5)]],
                    constant float&      reach    [[buffer(6)]],
                    constant uint&       refCount [[buffer(7)]],
                    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) return;
    uint i = pixelIndex(gid.x, gid.y, params.width);
    mended[i] = 0;
    if (painted[i] != 0 || neighbour[i] != 0 || !mendIsInk(i, wall, wall2, refCount)) return;
    bool onPaper = insideArtworkRect(gid.x, gid.y, params);
    const int2 axes[4] = { int2(1, 0), int2(0, 1), int2(1, 1), int2(1, -1) };
    for (int a = 0; a < 4; a++) {
        float stride = (axes[a].x != 0 && axes[a].y != 0) ? 1.41421356f : 1.0f;
        int limit = int(reach / stride);
        uint2 ahead = mendRun(gid, axes[a].x, axes[a].y, limit, onPaper, painted, neighbour, wall, wall2, params, refCount);
        if (ahead.x == 0) continue;
        uint2 behind = mendRun(gid, -axes[a].x, -axes[a].y, limit, onPaper, painted, neighbour, wall, wall2, params, refCount);
        bool joins = ((ahead.x & 1u) != 0 && (behind.x & 2u) != 0) || ((ahead.x & 2u) != 0 && (behind.x & 1u) != 0);
        // The two steps both land on a painted pixel, so the ink between them is one pixel fewer than
        // the steps: a seam of `reach` pixels is mended, which is what the slider's number says.
        if (joins && float(ahead.y + behind.y - 1u) * stride <= reach) { mended[i] = 255; return; }
    }
}
