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
    float _pad0;
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
    bool prev = false;
    for (uint x = 0; x < w; x++) {
        uint i = base + x;
        if (wall[i]) { prev = false; }
        else if (region[i]) { prev = true; }
        else if (prev) { region[i] = 1; atomic_fetch_or_explicit(changed, 1u, memory_order_relaxed); }
    }
    prev = false;
    for (int x = int(w) - 1; x >= 0; x--) {
        uint i = base + uint(x);
        if (wall[i]) { prev = false; }
        else if (region[i]) { prev = true; }
        else if (prev) { region[i] = 1; atomic_fetch_or_explicit(changed, 1u, memory_order_relaxed); }
    }
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
    bool prev = false;
    for (uint y = 0; y < h; y++) {
        uint i = y * w + x;
        if (wall[i]) { prev = false; }
        else if (region[i]) { prev = true; }
        else if (prev) { region[i] = 1; atomic_fetch_or_explicit(changed, 1u, memory_order_relaxed); }
    }
    prev = false;
    for (int y = int(h) - 1; y >= 0; y--) {
        uint i = uint(y) * w + x;
        if (wall[i]) { prev = false; }
        else if (region[i]) { prev = true; }
        else if (prev) { region[i] = 1; atomic_fetch_or_explicit(changed, 1u, memory_order_relaxed); }
    }
}

// MARK: - Edge overlap + paint

// Grow the region by a small disk so the fill slips under the anti-aliased wall pixels.
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
    for (int dy = -r; dy <= r; dy++) {
        for (int dx = -r; dx <= r; dx++) {
            if (float(dx * dx + dy * dy) > r2) continue;
            int nx = int(gid.x) + dx;
            int ny = int(gid.y) + dy;
            if (nx < 0 || ny < 0 || nx >= int(params.width) || ny >= int(params.height)) continue;
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
