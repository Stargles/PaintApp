# Vector Eraser — Design Plan

Three eraser modes on `.vector` layers, modelled on Clip Studio Paint, plus the vector-engine
foundations they need. Raster-layer erasing is untouched.

| Mode | CSP name | Behaviour | Representation |
|---|---|---|---|
| 1. **Erase** (default) | *Erase touched parts* | Indistinguishable from raster erasing: partial-width shaves, diagonal cuts, soft edges, `< 1` opacity fades | Hybrid — geometric split where clean, retained alpha-punch element where not |
| 2. **Cut points** | (no CSP equivalent) | Deletes stroke samples the eraser touches | Destructive sample removal (today's behaviour, rewritten) |
| 3. **Cut to intersection** | *Erase up to intersection* | Removes the stroke span between the two nearest crossings with another stroke in the same cel | Destructive sample removal |

Confirmed decisions: Mode 1 uses the hybrid representation; its punch erases **everything**
beneath (fills and placed images included); Mode 3 finds intersections **within the same cel
only**; `eraserOpacity < 1` gives a **real partial fade** in Mode 1.

---

## 1. The central problem

> *"When a line is physically cut the link between them breaks, but the integration should be
> seamless to a raster analog."*

Two representations are each right half the time:

- **Alpha punch** (the eraser as a stroke composited `.destinationOut`) is pixel-perfect for
  every case — soft edges, grain, partial-width shaves, diagonal cuts, `< 1` opacity — but the
  stroke is never actually cut. Grab one visual half with the Move tool and both halves move.
  And the elements accumulate forever, which fights the point-decimation goal.
- **Geometric split** (trim samples, emit two strokes) gives real separation, no growth, and
  clean input for interpolate/liquify/decimation — but cannot express a half-width shave or a
  feathered edge at all.

**Resolution: decide per erase, at commit time, by measuring coverage.** For each paint stroke
the eraser touched:

1. Walk the stroke's samples. For each one, compute how much of the *stroke's own width* at that
   point is covered by the eraser's capsule chain, and at what alpha.
2. A maximal contiguous span where coverage is **full width at full alpha** is a *clean cut*:
   delete those samples, interpolate exact boundary samples at both ends, split into two strokes.
   Subtract that span from the eraser's footprint.
3. Whatever eraser footprint remains — partial-width, feathered, `< 1` opacity, or overlapping a
   fill/image — is retained as a `.erase` element in the display list at the z-position where it
   was drawn.

Consequences worth stating plainly:

- A hard-round eraser at full opacity, used the way people normally erase (sweeping across a
  line), produces **only clean cuts**. Zero retained elements, zero growth, and Mode 1 collapses
  to something as cheap as Mode 2 but with exact cut boundaries.
- A soft-round eraser, or a grazing shave, or `opacity 0.4`, retains a punch. That's the price of
  the fidelity, and it's the user's own brush choice that sets it.
- The alpha-punch path is the fallback that guarantees the "indistinguishable from raster"
  promise; the geometric path is the optimisation that keeps files small. Neither alone works.

### Coverage test

`BrushStamper` already defines a stroke's rendered footprint as a chain of dabs. For the coverage
test we approximate both the eraser stroke and the paint stroke as **capsule chains** (segment +
per-end radius, radius = `size/2 × dynamics.sizeFraction(pressure)`); coverage at a paint sample
is the fraction of its cross-section interval `[-r, +r]` (perpendicular to the local tangent)
covered by the union of nearby eraser capsules. Cheap, closed-form, and pure `CGFloat` maths.

Two guards keep this honest rather than approximately-honest:
- **Alpha gate.** A soft eraser's edge alpha is `< 1` even at full geometric coverage, so a clean
  cut additionally requires `hardness ≥ ~0.95`, `grain.isEnabled == false`, and
  `eraserOpacity × flow ≈ 1`. Below that, everything is residue. Conservative on purpose: a false
  "clean" claim is a visible artefact, a false "residue" claim is only a retained element.
- **Margin.** Require coverage to exceed the stroke's half-width by a small epsilon before
  calling it clean, so anti-aliased fringe isn't left behind at the cut.

### Garbage collection

A retained `.erase` element is dropped when nothing beneath it in the display list still
intersects its bounding box (all such strokes deleted or moved away). Checked lazily against the
spatial index on commit, not every frame.

---

## 2. Data model

### 2.1 The eraser *is* a stroke

The single highest-leverage decision in the plan. Rather than a new `VectorEraseElement` type,
`VectorStroke` gains one field:

```swift
enum StrokeComposite: String, Codable { case paint, erase }

struct VectorStroke: Identifiable, Codable {
    // ...existing: brush, color, size, opacity, samples
    var composite: StrokeComposite = .paint   // decodes to .paint on legacy files
}
```

At render, `composite == .erase` routes to `BrushStamper.stampDab(..., isEraser: true)` — the
`.destinationOut` path that already exists and is already pixel-identical to live raster erasing.
No new rasterizer.

Everything downstream is then free, which is why this shape is chosen over a separate type:

- **Interpolate.** An eraser is a polyline with pressure and width, structurally identical to a
  paint stroke. The tween operates on one type, so an erased hole tweens along with the ink
  instead of popping. A separate eraser type would need a parallel correspondence-matching
  implementation.
- **Liquify.** Warping sample positions warps eraser and ink together, so the hole deforms with
  the line — exactly the raster behaviour.
- **Point decimation.** One `StrokeSimplifier` serves both. (Constraint: samples interpolated as
  *cut boundaries* by Modes 1–3 must be pinned, or the cut edge drifts under decimation. Add
  `isPinned: Bool` to `VectorSample`, or decimate only before cutting and never after.)

### 2.2 Unified display list

An eraser that "lowers the alpha of everything beneath it" needs z-order, which three parallel
arrays rendered in a fixed order cannot express — if erasers are appended last, a stroke drawn
after an erase gets eaten by it.

```swift
enum VectorElement: Identifiable {
    case stroke(VectorStroke)     // .paint or .erase
    case fill(VectorFillElement)
    case image(VectorImageElement)
}

final class VectorCanvas {
    private var _elements: [VectorElement]

    // Compatibility seam: every existing call site keeps working unchanged.
    var strokes: [VectorStroke] { get { filter } set { splice } }
    var fills:   [VectorFillElement] { ... }
    var images:  [VectorImageElement] { ... }
}
```

The computed accessors are what keeps this refactor small: `canvas.strokes = snapshot` (undo),
`cel.vector?.strokes.count`, `vector.images` and the rest are untouched. Setter contract: remove
all elements of that kind, insert the new list at the index of the first removed one. Order-stable
for the undo/redo snapshot round-trip, which is the only caller that reassigns wholesale.

`renderLocalContent()` becomes a single ordered walk. The existing transparency-layer isolation for
non-`.normal` blend modes stays, with one added rule: **an `.erase` element closes any open
isolation group before punching**, so it reaches the fills and images beneath rather than only the
strokes in the current group. That is what makes "everything beneath" true.

### 2.3 Persistence

`VectorCanvasData` gains `elements: [VectorElementData]`. Decode falls back to the legacy
`strokes`/`fills`/`images` arrays when `elements` is absent, reconstructing the order the old
renderer used (fills, then images, then strokes) — so existing projects open unchanged and gain a
correct display list on first save.

---

## 3. Shared geometry foundation

All three modes, plus future liquify and selection hit-testing, need the same two primitives.
Built once, pure (`CGPoint`/`CGFloat` only, no UIKit), unit-testable headless — matching the
convention `BrushGrain.noiseValue` already sets.

### 3.1 `StrokeGeometry` (pure functions)

- point→segment distance, capsule containment, capsule-chain coverage (§1)
- polyline↔polyline intersection, with a width tolerance so strokes that *visually* touch but
  don't mathematically cross still count as an intersection (Mode 3 needs this — CSP's behaviour
  is width-aware, not centerline-exact)
- sample interpolation at a parametric position along a stroke (position **and** pressure), for
  exact cut boundaries
- local subdivision: densify a stroke's samples where spacing exceeds the eraser radius
- `splitStroke(_:removing: [Range<parametric>]) -> [VectorStroke]` — one implementation of
  "delete spans and emit the surviving pieces", shared by all three modes

### 3.2 `StrokeSpatialIndex`

Uniform grid (≈64pt cells) over segment bounding boxes, built lazily per cel and invalidated on
`VectorCanvas.version`. Maps a query rect to candidate `(elementIndex, sampleIndex)` segments.

This is what keeps the engine off the performance-intensive path. Today's `erase` is
O(all samples × all eraser points) with a nested loop over every stroke on the layer; with the
index every mode becomes O(segments in the eraser's swept bbox). It also serves Mode 3's
intersection queries, Mode 1's coverage test and GC, and later liquify's affected-stroke query.

Also add a cached `bounds: CGRect` per stroke (maintained on mutation) so bbox rejection is free.

---

## 4. Per-mode implementation

### Mode 2 — Cut points (rewrite of what exists)

Today's version has four real defects, all fixed by §3 primitives:

| Defect | Fix |
|---|---|
| Point-to-point distance: a small eraser passing *between* two coarse samples does nothing | Point-to-**segment** distance against the eraser polyline |
| Cuts land at sample granularity, so edges are ragged and don't follow the eraser | Interpolate exact boundary samples at the eraser's edge |
| Coarse strokes over-erase (nearest sample is far outside the footprint) | Local subdivision where spacing > eraser radius |
| O(samples × eraserPoints) per stroke, per erase, over every stroke | Spatial-index query first |

After this, Mode 2 is visually close to Mode 1 **for cuts that cross a line squarely**. It still
cannot shave a side off a stroke or produce a soft edge — the structural reason Mode 1 needs the
alpha path.

### Mode 3 — Cut to intersection

1. Hit-test the eraser's first touch point → nearest stroke and parametric position on it.
2. Query the index for other strokes' segments near that stroke's bbox; compute intersections
   with width tolerance (§3.1).
3. Take the two intersections bracketing the hit position; clamp to the stroke's endpoints when
   there is none on a side.
4. `splitStroke(removing:)` that one span.

Falling out of step 3 for free: a stroke with no intersections at all is deleted entirely — CSP's
third mode, *erase whole line*, with no extra code.

Runs on touch-**down**, not on lift: CSP cuts immediately, and a drag across three lines should cut
three segments. Each cut re-queries, so accumulate the affected strokes and register one undo entry
for the whole drag.

### Mode 1 — Erase

**Live preview.** The current code deliberately skips preview for the eraser and shows the result
on lift, which will not do for a raster-feeling eraser. Instead, on touch-down copy the cel's
already-cached render into a scratch `RasterLayerTexture`, punch `.destinationOut` dabs into that
copy live through the existing `stampPath` path, and display it. This is literally the raster
eraser's code path, so live feedback is raster-identical by construction. One canvas-sized
allocation per eraser stroke, released on lift.

**Commit.** Run the §1 hybrid resolution: clean spans → `splitStroke`, residue → retained `.erase`
element inserted at the end of the display list. Then GC.

**Undo.** Snapshot the element list as today (`registerVectorUndo`), extended from `[VectorStroke]`
to `[VectorElement]`. Note this gets heavy — see §6.

---

## 5. Tool and UI plumbing

```swift
enum VectorEraserMode: String, Codable, CaseIterable {
    case erase          // Mode 1 — default
    case cutPoints      // Mode 2
    case cutToIntersection  // Mode 3
}
```

- `CanvasManager.vectorEraserMode`, persisted with project settings.
- A three-way segmented control in `EraserSettingsPanel`, shown **only when the active layer is
  `.vector`** — on a raster layer the eraser panel is unchanged.
- `StrokeCanvasView` keeps `isEraser` and gains `vectorEraserMode`, assigned in
  `CanvasView.updateActiveLayerAndTool` alongside the existing `host.strokeView.isEraser`.
- Stabilization: Mode 1 should be **smoothed like a brush** (it is a brush stroke, and jitter shows
  in the erased edge). Modes 2 and 3 stay unsmoothed — they cut where the finger goes. This
  reverses today's blanket `isEraser ? raw : stabilized` for Mode 1 only.

---

## 6. Performance

Explicit targets, since `PerfBaselineTests.testVectorLayerRenderCostAndMemory` already measures
this tier and the numbers land in `REFACTOR_BASELINE.md`.

**Dirty-rect render cache.** The dominant cost today isn't the eraser, it's that any mutation nulls
`cachedImage` and re-stamps every stroke on the layer. Since strokes and erase elements are both
*appended*, keep the backing `CGContext` alive for the **cel currently being edited** and draw only
the new element's bbox into it; other cels keep the current `UIImage`-only caching. Live drawing
becomes O(dirty rect) instead of O(all strokes).

This trades memory back for speed — one extra canvas-sized bitmap (~16 MB at 2048², ~64 MB at
4000²) for the active cel only, released when the cel loses focus. `renderLocalContent`'s existing
`format.preferredRange = .standard` pin must be preserved on this context or the 2.2× extended-range
regression documented there comes straight back.

**Point decimation** (your future feature, pulled forward because the eraser makes it matter):
pressure-aware Ramer–Douglas–Peucker with tolerance scaled to stroke width, run on commit for both
`.paint` and `.erase` strokes. Pinned cut-boundary samples are exempt.

**Delta undo.** Snapshotting the whole element list per erase stroke is O(n) memory per operation
and gets expensive on a dense layer. Replace with append/remove-at-index deltas. Deferred to a
later phase — the existing snapshot approach is correct, just heavy.

---

## 7. Phasing

Ordered so each phase is independently mergeable and testable, and so the cheap machinery that the
expensive mode depends on exists first.

| Phase | Content | Behaviour change |
|---|---|---|
| **0** | `StrokeGeometry` + `StrokeSpatialIndex` + cached stroke bounds. Pure, headless-testable. | None |
| **1** | `VectorElement` display list, `StrokeComposite`, compatibility accessors, persistence migration. | None (render output byte-identical) |
| **2** | `VectorEraserMode` enum + UI + plumbing. Rewrite Mode 2 on §3 primitives. | Mode 2 becomes accurate |
| **3** | Mode 3, cut-to-intersection. | New mode |
| **4** | Mode 1: live preview, hybrid commit, residue elements, GC. | New default mode |
| **5** | Dirty-rect cache, decimation, delta undo; refresh perf baseline. | Faster |

Phase 1 is the risky one — it touches every `VectorCanvas` call site — which is why it ships alone,
with byte-identical render output as its acceptance criterion.

## 8. Testing

- **Headless logic tests** (`PaintSoftwareUITests/…LogicTests.swift` pattern, no simulator needed):
  every `StrokeGeometry` primitive, spatial-index correctness against brute force, split/boundary
  interpolation, RDP with pinned samples, persistence round-trip and legacy decode.
- **The acceptance test for Mode 1:** draw an identical stroke on a raster layer and a vector layer,
  erase both with an identical gesture, compare the rendered images within a small per-pixel
  tolerance. This is what "indistinguishable from raster" means operationally, and it's the only
  test that can actually prove it. Run it across the matrix: hard/soft brush, full/partial opacity,
  square cut / diagonal cut / partial-width shave, over a stroke / over a fill / over an image.
- **Perf**: extend `testVectorLayerRenderCostAndMemory` with an erase-heavy scenario (200 strokes,
  50 erase gestures) and record before/after in `REFACTOR_BASELINE.md`.

## 9. Brush-side findings

The eraser *is* a brush (same `BrushStamper` pipeline, `.destinationOut` instead of the brush's own
blend mode), so defects on the brush side land in the eraser too. Found while auditing:

**Fixed — non-replayable dab randomness.** `applyScatter` and rotation jitter called `CGFloat.random`
inside `stampDab`, while `VectorCanvas.renderLocalContent` re-runs `stampStroke` over every stored
stroke on every invalidation. Any brush with `scatter > 0` or `rotationJitter > 0` therefore landed
its dabs somewhere new on each render — draw a second stroke and the first visibly jumps. This
contradicts `VectorStroke`'s own contract (geometry re-rasterized losslessly on demand), applies to
an eraser stroke identically (its hole would crawl), and makes §8's raster-vs-vector pixel comparison
impossible. Replaced with a seeded splitmix64 `DabRNG`; replayable callers pass `seed(for: stroke.id)`,
live raster drawing correctly stays unseeded. **Remaining:** wire the seed at the `VectorCanvas`
render site once Phase 1 lands.

**Fixed — pressure staircase.** Every dab bridging two input samples took the *destination* sample's
pressure. One segment spans many dabs at the sample rate a fast drag produces, so a smooth press came
out as visible steps in width and opacity. `advance()` now reports each dab's position along the
segment and `stampStroke` interpolates.

**Candidate, not taken — square/custom brush cost.** `stampApproximateSquare` approximates one square
dab with a grid of ~16 circles, so a square brush does ~16× the gradient-fill work per stamp of a
round one. `DabGradientCache` memoizes the gradients (measured 2635 hits / 1 miss), so this is fill
cost rather than allocation cost — moderate, not pathological. A real rotated-rect fill with a
hardness gradient would be strictly better, but it changes the `DabTarget` protocol and this
codebase's perf decisions are measured rather than assumed. Wants a measurement first; deferred to
Phase 5.

## 10. Open items (not blocking Phase 0–1)

- Mode 1 over a **placed image**: the punch works at render time, but a later liquify or transform of
  that image won't carry the hole with it. Probably acceptable; revisit with liquify.
- Should Mode 1 residue elements be included in interpolation between animation blocks, or should
  interpolation force a resolve-to-geometry pass first? Leaning toward forcing the resolve — decide
  when building interpolate.
- SVG/PDF export of a residue punch has no clean representation; would need a mask or a flatten.
