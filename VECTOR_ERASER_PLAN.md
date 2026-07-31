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

**Resolution as originally planned — superseded, kept because the phasing below refers to it.**
Decide per erase, at commit time, by measuring coverage: walk each touched stroke, find maximal
spans covered full-width at full alpha, split those out as *clean cuts*, and retain whatever
eraser footprint is left over as a `.erase` element. The expectation was that a hard-round eraser
at full opacity would produce **only** clean cuts and retain nothing.

### What shipped instead, and why (Phase 4c, measured; split restored in Phase 4d)

Both halves of that expectation were false, and `RasterVectorParityLogicTests` /
`VectorEraserHybridLogicTests` are the measurements. Against a raster layer erased identically, at
zero tolerance:

1. **A retained punch is byte-identical to raster erasing** — every pixel, across hard/soft
   brushes, full/partial opacity, three gesture shapes, over a stroke, a fill and a placed image.
   The fallback is exactly as strong as this section claimed.
2. **A geometric split was not**, for two independent reasons, both traced to
   `BrushStamper.stampStroke` anchoring its **dab lattice** at `samples[0]`:
   - A cut stroke's surviving piece was re-stamped as a *new* stroke, so the anchor moved to the
     cut and its ink landed somewhere new along its **whole length** — most visibly at its far tip,
     which is the end the punch cannot cover. Measured on a 24pt line cut by a 48pt nib:
     divergence across x ∈ [41, 115] where the punch covers only x ∈ [40, 88], leaving 118 stray
     pixels at up to 183/255. A wider eraser moves the artefact further away rather than covering
     it, because its size is set by the *stroke's* spacing and width.
   - Separately, a cut end is a round cap of the stroke's half-width while the eraser removed ink
     along a straight band edge. Those differ by a lens of area ≈ `0.43·w²` however the boundary is
     placed. `conservativeCuts` solves *this* one by insetting; it does not touch the first.

   Phase 4c shipped without any partial cutting on the strength of that. Phase 4d fixed the first
   reason — `DabLattice`, below — and with both fixed the split is exact and is wired in.
3. **The pressure ramp, anchored at `samples[0]` alongside the lattice, was never a problem.**
   `splitStroke` interpolates the boundary sample's pressure and pressure interpolates linearly, so
   a piece already reported the parent's pressure at every position. Only the lattice moved. Worth
   recording because two sessions of notes name both anchors as defects.

So the resolution that ships is:

1. **Punch, always.** The eraser's gesture is retained whole as a `.erase` element at the
   z-position where it was drawn. Mode 1 is pixel-exact by construction rather than by a threshold.
   The decision to retain is a **bit** — is there anything under any part of the gesture — not a
   set of spans: trimming the punch to the spans that have a backdrop re-phases the same lattice
   and costs 4–27/255 over tens of pixels.
2. **Delete a stroke the eraser covers end to end** (`VectorEraser.isEntirelyCovered`: every
   cross-section, *plus* both round end caps, which no cross-section test can see). This produces
   no new geometry, so nothing re-stamps and nothing can move — it is exact — and it is what keeps
   "scribble a stroke out and it costs nothing" true.
3. **Cut a stroke where the eraser covers its full width**, at that span inset by the stroke's own
   half-width (`conservativeCuts`), into pieces that render on the parent's dab lattice
   (`DabLattice`). Both parts are required and neither is sufficient: the inset keeps the ink a cut
   loses inside the span the punch removes, and the shared lattice keeps the surviving dabs where
   they already were. `testTheSplitIsExactOnlyBecauseThePiecesShareTheParentsLattice` pins both.

### `DabLattice` — how a piece reproduces its parent's dabs

The two candidate shapes were arclength-anchored dab positions and a parametric visible range on
`VectorStroke`. **The visible range shipped**, and the deciding argument is exactness rather than
elegance: arclength anchoring *recomputes* where each dab goes, through a different sequence of
floating-point operations from the one that placed the original dabs, and §8 is asserted at zero
tolerance. The visible range does not recompute anything — the renderer walks the **parent's**
samples with the same spacing arithmetic and the same carry, and routes the dabs outside the range
to a sink that draws nothing (`BrushStamper.stampStroke(…, visibleRange:)`,
`DiscardedDabTarget`). The dabs that land are the same calls with the same arguments.

Two details that make it hold up:

- A piece stores the parent's samples **and** the parameter each of its own samples sits at, not
  just a range. That is what lets a piece be cut *again*: the second cut's parameters are in the
  piece's domain and are mapped back through `DabLattice.parentParameter(of:)`, so a grandchild
  points at the original ancestor rather than at a chain of parents.
- `samples` remains the truth about a piece's **geometry** — bounds, spatial index, coverage,
  later cuts, hit-testing. The lattice is read in exactly one place, `VectorCanvas.stamp(stroke:…)`,
  and only to answer "where did the dabs go". That is what kept this change small: no geometric
  consumer needs to know pieces exist.
- Skipped dabs still run through `stampDab`, so the dab RNG stays in phase, and the lattice carries
  the parent's `seedID`. A piece is therefore replayable even for a scattering brush;
  `supportsSplitting` still refuses those, but now for the one remaining reason — the coverage test
  measures against a capsule chain that scattered ink does not respect.

Consequences worth stating plainly:

- Growth is one element per eraser gesture that touched something, exactly as N paint gestures cost
  N elements — plus GC, which drops a punch once nothing beneath it remains. A gesture over nothing
  costs nothing; a gesture that wholly resolves costs nothing.
- A cut *does* now give two independently addressable halves, which is what "grab one visual half
  with the Move tool" was waiting for. The Move tool itself is untouched by this phase: a layer-level
  transform moves everything, and per-element move is still to be built. Translating a piece will
  work without further changes, because translation does not change arclength and so does not move
  the lattice.
- A piece holds its parent's sample array. Two pieces of one parent share that storage (arrays are
  copy-on-write) until something mutates it, but a decoded project gives each its own copy. That is
  a persistence-size question, not a correctness one, and it is the natural thing for point
  decimation to clean up.
- Modes 2 and 3 clear the lattice on the pieces they produce. They delete geometry rather than
  hiding it, so a piece there really is a new stroke, and inheriting the lattice would keep drawing
  the dabs the user just cut away.

### Coverage test

`BrushStamper` already defines a stroke's rendered footprint as a chain of dabs. For the coverage
test we approximate both the eraser stroke and the paint stroke as **capsule chains** (segment +
per-end radius, radius = `size/2 × dynamics.sizeFraction(pressure)`); coverage at a paint sample
is the fraction of its cross-section interval `[-r, +r]` (perpendicular to the local tangent)
covered by the union of nearby eraser capsules. Cheap, closed-form, and pure `CGFloat` maths.

Two guards keep this honest rather than approximately-honest:
- **Alpha gate.** A soft eraser's edge alpha is `< 1` even at full geometric coverage, so removing
  ink outright additionally requires `hardness ≥ ~0.95`, `grain.isEnabled == false`,
  `eraserOpacity × flow ≈ 1`, `scatter == 0`, `rotationJitter == 0`, and a non-square shape. Below
  that, everything is residue. Conservative on purpose: a false "clean" claim is a visible
  artefact, a false "residue" claim is only a retained element.
  **`opacityPressure` is judged against the gesture's own minimum pressure, not against zero.**
  Against zero, `opacityFraction` bottoms out at `1 - opacityPressure` and the gate rejects every
  brush that reacts to pressure at all — `hardRound` ships with `0.1`, `pen` with `0.05`, so no
  built-in brush could pass and the whole geometric path was unreachable. That was a real bug, not
  conservatism.
- **Margin.** Require coverage to exceed the stroke's half-width by a small epsilon before
  calling it clean, so anti-aliased fringe isn't left behind at the cut.
- **Scallop.** Pull each eraser capsule's radii in by the deepest gap between consecutive dabs,
  `r − √(r² − (s/2)²)`, or a wide-spacing brush claims coverage through the gaps it left
  (`cleanCutCapsules`).

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

**Commit.** Run the §1 resolution *as shipped*: strokes the eraser covers end to end are deleted
outright, the gesture is retained whole as a `.erase` element appended to the display list whenever
anything is still under any part of it, and then GC. No partial cutting — see §1.

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

| Phase | Content | Behaviour change | Status |
|---|---|---|---|
| **0** | `StrokeGeometry` + `StrokeSpatialIndex` + cached stroke bounds. Pure, headless-testable. | None | **Done** (S2) |
| **1** | `VectorElement` display list, `StrokeComposite`, compatibility accessors, persistence migration. | None (render output byte-identical) | **Done** (S2) |
| **2** | `VectorEraserMode` enum + UI + plumbing. Rewrite Mode 2 on §3 primitives. | Mode 2 becomes accurate | **Done** (S3) |
| **3** | Mode 3, cut-to-intersection. | New mode | **Done** (geometry S3, touch-down driver S3) |
| **4** | Mode 1: live preview, punch commit, GC. | New default mode | **Done** (S4–S5); driven through the real UI S6; geometric split restored S7 (`DabLattice`) |
| **5** | Dirty-rect cache, decimation, delta undo; refresh perf baseline. | Faster | |
| **6** | GPU rasterizer for both tiers — see §11. | Faster; scales past ~500 strokes/layer | |

Phase 1 is the risky one — it touches every `VectorCanvas` call site — which is why it ships alone,
with byte-identical render output as its acceptance criterion.

Phase 3 was partly pulled into Phase 2: the geometry (`VectorEraser.cutToIntersection`, plus the
canvas-level driver that finds the target stroke and its neighbours) was written and tested there,
because otherwise Phase 2 would have shipped a three-way segmented control with a dead third option.
Phase 3 proper added the *gesture* semantics — cut on touch-**down** and re-query per crossing
(`VectorEraser.IntersectionDriver`), so one drag across three lines cuts three spans under a single
undo entry.

## 8. Testing

- **Headless logic tests** (`PaintSoftwareUITests/…LogicTests.swift` pattern, no simulator needed):
  every `StrokeGeometry` primitive, spatial-index correctness against brute force, split/boundary
  interpolation, RDP with pinned samples, persistence round-trip and legacy decode.
- **The acceptance test for Mode 1:** draw an identical stroke on a raster layer and a vector layer,
  erase both with an identical gesture, compare the rendered images **at zero tolerance**. This is
  what "indistinguishable from raster" means operationally, and it's the only test that can actually
  prove it. Run it across the matrix: hard/soft brush, full/partial opacity, square cut / diagonal
  cut / partial-width shave, over a stroke / over a fill / over an image.

  Zero, not "a small per-pixel tolerance" as this said first: both tiers rasterize through the same
  `BrushStamper`, so they agree byte for byte, and the harness demonstrates it. Any tolerance here
  would hide a regression rather than absorb noise — every defect Phase 4c found showed up as a
  delta of 4–27/255 over tens of pixels, which is exactly the band a "small" tolerance would have
  swallowed.

  Two files, deliberately: `RasterVectorParityLogicTests` builds display lists by hand and tests the
  *representation*; `VectorEraserHybridLogicTests` drives the real `VectorCanvas.erase` and tests
  the *decision*. The first passing does not imply the second — for three sessions it did not.

  A third thing the split needs pinned, because it is a claim about the *stamper* rather than about
  the eraser: two complementary `visibleRange`s of one stroke must lay exactly the dabs the uncut
  stroke laid (`BrushEngineLogicTests.testComplementaryVisibleRangesReproduceTheWholeStrokeExactly`).
  That is the property `DabLattice` is built on, and it is worth failing on its own rather than only
  as a pixel delta three layers away.
- **Through the real UI** (`VectorEraserUITests`, XCUITest). The two tiers above both call the
  engine directly, so between them they cannot see any of the plumbing between a finger and
  `VectorCanvas.erase` — the segmented control, `CanvasManager.vectorEraserMode`,
  `CanvasView.updateActiveLayerAndTool`, `StrokeCanvasView`'s scratch role and its Mode 3 driver.
  For three sessions that plumbing had never been run at all. What this tier covers: the picker is
  hidden on raster layers and offers three segments on vector ones; the segment you tap is the mode
  that commits (Mode 2 cuts and retains nothing where Mode 1 punches and keeps the stroke whole);
  Mode 1 leaves ink either side of the gesture and blank paper under it; a stroke covered end to end
  is deleted with nothing retained; Mode 3 acts on every line one drag crosses, under one undo, and
  otherwise removes only the span between the two nearest crossings.

  Two things this tier needed that did not exist. **`LayerRowModel` now reports paint strokes and
  `.erase` punches as separate counts** — against a single total, "cut in two" and "punched over"
  are the same number, and telling those apart is the whole point. (One older test had been asserting
  `strokes == 2` after a Mode 1 erase and passing on the punch.) And **`StrokeCanvasView` records
  `lastVectorGestureTrace`**, surfaced on `canvas.host`, because a live preview is observable only
  while a finger is down and an XCUITest cannot look: `press(forDuration:thenDragTo:)` asserts
  main-thread, so the test thread is blocked inside the gesture and every screenshot it can take is
  post-lift, where the commit has erased the same pixels. Moving the gesture to a background queue
  crashes the runner — that assertion is there to stop exactly this. The app therefore counts the
  preview frames it published and the test reads the count afterwards.
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

---

## 11. Moving vector rendering to the GPU

Raised while Phase 2 was in flight: thousands of strokes per layer, several layers, several
animation blocks — does the vector tier need a GPU renderer, and should raster layers or the whole
canvas composite go with it?

### What is already on the GPU

The per-frame layer composite is. Layers are `UIImageView`s inside `LayerHostView`; Core Animation
blends them, with their opacity and blend modes, on the GPU every frame. A frame in which nothing
changes costs the CPU nothing at all, whatever the stroke count, and adding layers or animation
blocks does not add per-frame CPU work.

So the "recalculating an insane number of layers each frame" cost is not the one to worry about. The
cost that is real is narrower and worse: **re-rasterizing one layer's content when that layer
changes.** `VectorCanvas.render()` caches by `version`, and any mutation nulls the cache and
re-stamps every element on the layer through `BrushStamper` into a Core Graphics context.

### The number

`REFACTOR_BASELINE.md` measures `testVectorLayerRenderCostAndMemory` at **63.6 ms for a 20-stroke
vector layer** — about 3.2 ms per stroke, essentially all of it Core Graphics radial-gradient fills,
one per dab. Linear in stroke count, so extrapolating:

| Strokes on the layer | Full re-render |
|---|---|
| 20 | 64 ms |
| 500 | ~1.6 s |
| 2000 | ~6.4 s |

A GPU rasterizer stamping dabs as instanced quads with the hardness falloff in the fragment shader
is the difference between "milliseconds" and "seconds" here — two to three orders of magnitude, not
a tuning win. **At the target scale the vector tier does need one.** The question is only when, and
what else moves with it.

### Why not now

1. **It would break the acceptance test the eraser is being built against.** §8's Mode 1 criterion is
   that an identical stroke, erased identically, produces the same pixels on a raster layer and a
   vector layer. That is only meaningful while both go through one `BrushStamper`. Port the vector
   tier alone and the criterion becomes "a Metal shader matches Core Graphics' gradient
   interpolation per pixel", which is a different and much nastier project — and it would be blocking
   the eraser rather than being verified by it.
2. **Which means "only the vector layer" is the wrong scope.** Both tiers have to move together, or
   they drift. That is a large project on its own, and it is not the eraser's.
3. **Sequencing it after Phase 4 makes the pixel test the port's regression net.** That is exactly the
   safety a rasterizer rewrite wants, and it does not exist yet. Doing the port first throws it away.
4. **Some of the win is available much more cheaply.** Phase 5's dirty-rect cache removes the
   dominant case — appending a stroke re-stamping the whole layer — without touching the renderer.
   Two smaller ones sit next to it: `renderLocalContent()`'s result could be cached separately from
   the transformed output, so moving a layer stops re-stamping it; and `cachedImage` currently has no
   eviction, so N cels each retain a canvas-sized bitmap forever.

### What Phase 2 did to keep the door open

- **The geometry never touches Core Graphics.** `StrokeGeometry`, `StrokeSpatialIndex` and
  `VectorEraser` are `CoreGraphics`-types-only, no drawing, no UIKit — so the eraser's decisions
  survive a renderer swap untouched. `VectorCanvas.erase` is a thin adapter over them.
- **The display list stays a pure data model.** Nothing in Phase 2 assumes how it is drawn.
- **The spatial index is the shape a GPU renderer wants anyway** — it answers "what is in this rect",
  which is tile binning under a different name.

### The z-order optimisation, when it is needed

Worth writing down now because it is renderer-agnostic and it is the real answer to "don't
recompute the whole stack":

Source-over is associative, so a **run of consecutive `.normal` paint elements can be flattened into
one texture and re-composited as a unit**. Only two things force an ordered boundary: an element with
a non-`.normal` blend mode (already isolated in a transparency layer today) and an `.erase` element,
which by definition must see everything beneath it. Everything else is free to batch.

That gives a prefix/suffix cache: for the element being edited, keep "everything below it" and
"everything above it" as two flattened textures and only redraw the one element between them. Editing
cost stops scaling with layer content, on either backend — and on the GPU each run is one draw call.
This is the thing to build with Phase 5's dirty-rect cache, and it is why the `.erase` composite flag
is worth tracking as an explicit boundary rather than as just another element.

---

## 12. Open work

> Rescued from `VECTOR_ERASER_HANDOFF.md` when that file was deleted (2026-07-31). The eraser feature
> is finished and its session state was dead, but this backlog was not — it is unstarted work with
> measurements attached, and nothing else records it. §10 above is the older, smaller list; this is
> what the last eraser session left.

### Per-element Move

What the split was the unlock for — §1's "grab one visual half with the Move tool". Nothing in
`DabLattice` obstructs it: translation does not change arclength, so a translated piece keeps its
lattice unchanged.

**Not started, and bigger than it sounds** — scope it before writing code:

- There is **no per-element move today at all.** Moving is either a layer-level `LayerTransform` or
  `FloatingPiece` in `SelectionModels.swift`, and `FloatingPiece` is *pixel*-based (`pieceImage:
  UIImage`, lifted and re-baked). Neither is a vector-element move, so this is a new subsystem.
- The `Tool` enum has no `move` case, so there is UI plumbing as well as engine work.
- The engine half is small and headlessly testable, and is the right first commit: hit-test a point to
  an element, translate that element's samples. Both belong next to `StrokeGeometry`/`VectorEraser` —
  pure `CGPoint`/`CGFloat`, in the test target, no lock and no render cache.
- Watch the display-list invariant:
  `testAPunchLeavesEachKindContiguousSoTheUndoAccessorsStillRoundTrip` pins that each kind occupies
  one contiguous run. A move must be a mutation in place, never a remove-and-append.

### The spatial index is rebuilt from scratch on every `invalidate()`

The largest single term left in an erase, measured: **7.2 ms to walk 11,800 segments and answer a
query returning 7 strokes**, paid two to three times per gesture. Both passes append and remove at
known indices, so the index could be patched rather than rebuilt.

This wants company: a dirty-rect render cache needs exactly the same "what changed where"
information. Do them together or the second re-derives the first.

Smaller and adjacent: `maxPaintReach()` is O(elements) and runs three times per gesture. It becomes
free the moment stroke bounds are cached, which §3 asks for and which still does not exist.

### GPU rendering

§11. Unblocked — §8's parity test is its regression net. One constraint it adds: the visible range is
a *filter over a walk*, so a GPU rasteriser has to reproduce it as one — bin the dabs and drop those
outside the range, never re-derive positions.

Note the interaction with `BRUSH_ENGINE_EXTENSIBILITY.md`: the parity test is the safety net for the
GPU port **and** for the brush-format overhaul, and it holds only while both tiers share one
`BrushStamper`. Doing both at once leaves neither with a net.

### Still open

1. **Two sub-spacing biases at stroke ends** (`advance` carries a remainder so the last dab falls
   short; the chain tapers where `stampStroke` ramps pressure). Less pressing than it was: a piece
   inherits the parent's biases rather than introducing its own.
2. **`addFill` inserts beneath existing strokes — still right?** Not a local choice about fills: it is
   a property of the kind-sorted display list. Changing it means letting `_elements` hold an arbitrary
   order and dropping the kind accessors' splice contract — the `strokes`/`fills`/`images` setters and
   both `registerVector*Undo` paths would move to `elements`. The invariant is pinned by
   `testAPunchLeavesEachKindContiguousSoTheUndoAccessorsStillRoundTrip`.
3. **The live-preview trace measures publication, not pixels.** `lastVectorGestureTrace` proves the
   punched copy reached the image view repeatedly during the drag; it does not prove a given pixel was
   clear at that moment. Low priority — the pixels are `RasterVectorParityLogicTests`' job.
4. **A piece holds its parent's whole sample array.** Two pieces share it (copy-on-write) until one
   mutates; a decoded project gives each its own copy. Point decimation is the natural place to settle
   it — it can rewrite a piece as a stroke of its own once nobody needs the parent's phase.
