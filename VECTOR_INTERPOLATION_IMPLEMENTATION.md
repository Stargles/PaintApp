# Vector Interpolation — Implementation Plan

The ordered build plan. **Why** anything is shaped this way lives in
[VECTOR_INTERPOLATION_PLAN.md](VECTOR_INTERPOLATION_PLAN.md); **where the work currently is** lives in
[VECTOR_INTERPOLATION_HANDOFF.md](VECTOR_INTERPOLATION_HANDOFF.md). This file is *what to build, in
what order, and how to know it is done*.

Every phase ends at a **committable, buildable, test-passing state that leaves the app fully working.**
The feature is inert or hidden until Phase 4.

---

## Conventions for every phase

- **Vector layers only.** `.raster` layers must behave identically before and after every phase.
- **Backward-compatible persistence.** Every new persisted field uses the repo's established
  hand-written `init(from:)` + `decodeIfPresent` pattern (see `VectorStroke` in
  [VectorLayer.swift:134](PaintSoftware/Engine/VectorLayer.swift:134)). An old project must load
  unchanged, and a project with no interpolation data must encode byte-identically to before.
- **Purity discipline** for engine code: CoreGraphics (+ Accelerate) types only, no UIKit, no drawing.
  This is what lets it compile into the test target and be unit-tested without a simulator, and it is
  what `StrokeGeometry` / `StrokeSpatialIndex` / `VectorEraser` already do.
- **Tests go in the fast tier where possible.** Pure-logic test classes run in ~2s; XCUITests are
  99.3% of suite runtime. Add each new logic class to the fast filter in `HANDOFF.md` §4.
- **Do not touch `renderLocalContent()`'s isolation rules** without reading its full doc comment
  ([VectorLayer.swift:1307](PaintSoftware/Engine/VectorLayer.swift:1307)). Phase 3 is deliberately
  designed to avoid changing it.

---

## Phase 0 — Onion-skin seam and the vector onion-skin bug

**Goal.** Fix a real, shipping bug, and put the abstraction in place that standing constraint B
requires — all before any interpolation code exists.

**Why first.** It is small, independently valuable, touches nothing else, and Phase 4 depends on the
seam. It also warms up a session on the codebase cheaply.

### Work items

1. **Fix the bug.** [CanvasView.swift:739](PaintSoftware/Views/CanvasView.swift:739) renders
   `cels[celIdx].raster.renderToUIImage()` unconditionally, so a `.vector` cel onion-skins **blank**.
   Route through the same cel-rasterisation path the rest of the app uses (`PixelOps.rasterize(cel:)`
   handles both tiers) rather than reading `.raster` directly.
2. **Introduce the seam.** A small protocol describing *what to show as onion skin*, so interpolate
   mode can later say "these two specific reference cels" instead of "±1 frame":

   ```swift
   /// What the onion-skin layer should display. The current implementation answers "the previous
   /// cel on the current layer"; interpolate mode answers "the two reference keyframes". Kept as a
   /// protocol because the whole onion-skin feature is provisional and will be replaced — see
   /// VECTOR_INTERPOLATION_PLAN.md §10 constraint B.
   protocol OnionSkinSource {
       func frames(for manager: CanvasManager) -> [OnionSkinFrame]
   }

   struct OnionSkinFrame {
       let image: UIImage
       let opacity: CGFloat
       let tint: UIColor?   // nil = untinted; interpolate mode tints past/future differently
   }
   ```

   `CanvasView`'s coordinator holds an `OnionSkinSource` and asks it, instead of computing the cel
   itself. Default implementation reproduces today's exact behaviour.

3. Note in the code that the multi-frame/tint capability is *plumbing for later* — today's view shows
   one frame untinted.

**Files.** `PaintSoftware/Views/CanvasView.swift`, new
`PaintSoftware/Views/OnionSkinSource.swift`, `PaintSoftware/Services/PixelOps.swift` (read only).

**Tests.** New `OnionSkinLogicTests`: a `.vector` cel with one stroke produces a non-blank onion-skin
image (this is the regression test for the bug); the default source returns exactly the previous cel;
an empty cel returns nothing.

**Acceptance.** Fast suite green. Onion skin visibly works on a vector layer where it previously
showed nothing.

**Definition of done.** `OnionSkinLogicTests` passes; `CanvasView` no longer references
`cel.raster` for onion skin; the default source is behaviour-identical to today for raster layers.

**Estimate.** Well under one session.

---

## Phase 1 — Lattice and ARAP engine (pure logic)

**Goal.** The deformation engine, standalone, fully unit-tested, with no knowledge of keyframes, cels
or interpolation.

**Why here.** This is **the project's main technical risk** (`PLAN.md` §11). It must land early and be
verifiable in isolation, before anything is built on top of it. It is also the piece standing
constraint A requires be reusable for future liquify/mesh-distort work.

### Work items

1. **`Lattice`** — axis-aligned quad grid.

   ```swift
   struct Lattice: Equatable {
       let cols: Int, rows: Int
       let restOrigin: CGPoint
       let restCellSize: CGFloat
       /// (cols+1)*(rows+1) positions, row-major. In rest configuration these are the regular grid;
       /// a deformed lattice differs only here.
       var vertices: [CGPoint]
       /// Cells that actually contain geometry. Empty cells are carried for topology but ignored
       /// by the fit.
       var activeCells: Set<Int>
   }
   ```

2. **`LatticeEmbedding`** — where a point set sits inside a lattice.

   ```swift
   struct LatticeEmbedding {
       var cellIndex: [Int]
       var u: [CGFloat], v: [CGFloat]   // bilinear coords within the cell
   }
   ```

   `embed(points:)`, `warp(_:)` (embedding + lattice → points). **`warp` must be a pure function of
   the embedding and the lattice's vertices** — that is what makes evaluation at arbitrary *t* cheap.

3. **The inverse map.** Carrying a point drawn at deformed-time back to rest space:
   `embed(points:in: deformedLattice)` then `warp(that, in: restLattice)`. Embedding into a *deformed*
   (non-axis-aligned) lattice needs a point-in-quad test plus inverse bilinear interpolation — solve
   the quadratic, pick the root in [0,1]². This is the fiddliest math in the phase; test it hard.

4. **Lattice expansion** — `expanded(toContain:)`: add a ring of quads, deform each new quad by the
   affine transform of its neighbour, ARAP-relax, merge disconnected corners by averaging.

5. **Sparse solve wrapper.** Accelerate's `SparseFactor`/`SparseSolve` **is available on iOS —
   verified, see `HANDOFF.md` §5.** Wrap it thinly:

   ```swift
   /// Owns one factorised system matrix. The matrix depends only on lattice *topology*, so this is
   /// built once per lattice and reused for every solve — which is what makes per-t evaluation cheap.
   final class DeformFactorization { ... }
   ```

   Keep the wrapper narrow enough that swapping in a hand-rolled iterative solver later is local.

6. **`ARAPRegistration`** — fit a rest lattice to a target point cloud. Two tiers: least-squares
   similarity (rigid + uniform scale) first, then ARAP refinement initialised from it. Accepts
   positional constraints (used later by guide strokes and pinned points).

7. **`ARAPInterpolation`** — interpolate between two lattice configurations at *t*. Per-quad polar
   decomposition, interpolate rotation **as an angle** and scale/shear linearly, then one global
   solve to reconcile. **Never lerp the matrices directly** — that is the classic
   collapse-and-re-expand failure.

8. **Motion-residual grouping** (`PLAN.md` §5.3) — seed, fit, per-stroke residual, split on
   spatially-coherent high residual, recurse. Pure function over point sets; no app types.

**Files.** New directory `PaintSoftware/Engine/Deform/`: `Lattice.swift`,
`DeformFactorization.swift`, `ARAPRegistration.swift`, `ARAPInterpolation.swift`,
`MotionGrouping.swift`. **No existing file is modified in this phase** except the Xcode project's
file list.

**Tests.** New `LatticeLogicTests` and `ARAPLogicTests`:

- **`t=0` reproduces lattice A exactly; `t=1` reproduces lattice C exactly.** *The single most
  important invariant in the feature* — if this drifts, every downstream phase is built on sand.
- Inverse-warp round-trip is identity to within epsilon, including for a strongly deformed lattice.
- A pure rigid rotation between A and C interpolates as a rotation: every intermediate preserves
  edge lengths to within epsilon, and the midpoint is *not* a shrunken version.
- Pure translation interpolates as translation.
- Embedding is stable: a point on a cell boundary lands in exactly one cell.
- Expansion contains the requested points and leaves existing vertices untouched.
- Grouping: two rigid bodies moving in different directions split into exactly two groups; one rigid
  body does not split.
- Degenerate input: a group with <3 points, a collapsed lattice, an inverted quad — all return
  something sane rather than crashing or producing NaN. **Assert no NaN anywhere in the output.**

**Acceptance.** Fast suite green including the two new classes. Zero references to `Cel`, `Layer`,
`CanvasManager`, `VectorStroke` or UIKit anywhere under `Engine/Deform/` — grep for them as part of
the check.

**Definition of done.** All invariants above pass; the module imports only `CoreGraphics`,
`Foundation` and `Accelerate`.

**Estimate.** The largest engineering phase. Plan for 2–3 sessions with internal checkpoints:
(a) lattice + embed + warp + tests, (b) inverse map + expansion + tests, (c) solver + registration +
interpolation + tests, (d) grouping + tests. **Commit at each.**

---

## Phase 2 — Data model, persistence, undo (feature still inert)

**Goal.** Everything the recipe needs, persisted and undoable, with nothing yet consuming it.

### Work items

1. **The recipe**, stored on `Cel`:

   ```swift
   /// Non-nil makes this cel an *interpolated* cel: its content is computed from `references` at
   /// time `t` rather than stored. See VECTOR_INTERPOLATION_PLAN.md §4.
   var interpolation: InterpolationRecipe? = nil
   ```

   `Cel` is a struct inside `Layer.cels`, and `StructureSnapshot` copies `[Layer]` cheaply because
   the heavy tiers are class references — so putting the recipe here means **undo covers it for
   free**, which is the whole reason for this placement.

2. **`InterpolationRecipe`** — references, `t`, group bindings, guide refs, local edits, spacing.

   **Shape it for the deferred spline (`PLAN.md` §10 item 7).** `references` must be an *ordered
   list*, not a `(previous, next)` pair, and `t` must be a position within that list's span. A
   two-element list is today's pairwise case; a four-element list is the spline later, with no model
   change. **This is load-bearing — do not simplify it to two fields.**

3. **`MotionGroup` registry** on `CanvasManager` (document-level, per `PLAN.md` §5.1), so groups can
   span layers.

4. **Stroke → group tag: a field on `VectorStroke`**, not a side table.

   ```swift
   var motionGroupID: UUID? = nil
   ```

   Decoded with `decodeIfPresent`, encoded only when non-nil, so existing payloads stay byte-identical
   and old files load. **Reasoning for the field over a side table:** membership must survive copy,
   duplicate, split, and undo snapshot. A side table would have to be mirrored at every one of those
   sites, and the eraser work is a standing demonstration that mirroring an invariant across many call
   sites is where the bugs live. The cost is a nil `UUID?` on strokes that have none.

5. **`GuideStroke` + `TimedSample`** — a *new* sample type with a timestamp. **Do not add a timestamp
   to `VectorSample`**: it is in every saved project and on the hot path, and guides are not stamped
   by `BrushStamper` at all, so they share nothing.

6. **Per-vertex visibility thresholds** — stored as a sparse `[Int: CGFloat]` (or a parallel array
   only when present) on the stroke, absent for the overwhelmingly common case.

7. **Persistence.** Extend `ProjectManifest` / `ProjectStore` for all of the above. Guides and motion
   groups are document-level, so they need a home in the manifest, not the cel.

8. **Undo mapping.** Slider drag → `beginStructureGesture` / `commitStructureGesture`
   (**one step per drag, never per tick** — see
   [CanvasManager+Timeline.swift:171](PaintSoftware/Models/CanvasManager+Timeline.swift:171)).
   Group retag, mode change, reference set, guide edit → `withStructureUndo`. Strokes drawn at *t* →
   existing `registerVectorUndo`.

   > **Correction, found while building this (see `HANDOFF.md` §5).** `withStructureUndo` is right
   > for the mode change, the reference set and the guide edit, but **not** for the group retag:
   > `StructureSnapshot` copies `[Layer]`, and `Cel.vector` is a class reference, so the snapshot
   > shares each `VectorCanvas` and restoring it restores nothing about the strokes inside — while
   > the tag is a field on `VectorStroke`. Retagging needs the display list snapshotted too.
   > `CanvasManager.withInterpolationUndo(name:touching:)` does both tiers in one step; the slider
   > drag's structure bracket is unaffected, because `t` lives in the `Cel` struct.

9. **Cache eviction.** `VectorCanvas.cachedImage` has no eviction and interpolation multiplies live
   cels. Add a simple bound (evict non-visible cels' cached images beyond N).

**Files.** `Cel.swift`, `VectorLayer.swift` (VectorStroke coding), `CanvasManager.swift`,
`ProjectManifest.swift`, `ProjectStore.swift`; new `PaintSoftware/Models/InterpolationRecipe.swift`,
`MotionGroup.swift`, `GuideStroke.swift`.

**Tests.** New `InterpolationModelLogicTests`:

- A project saved before this phase loads with `interpolation == nil` and no error.
- A `VectorStroke` with no `motionGroupID` **encodes byte-identically** to the pre-change encoding.
- Full round-trip: recipe + groups + guides + visibility thresholds survive save→load unchanged.
- A recipe with four references round-trips (proving the spline-ready shape persists).
- Undo of a group retag restores the previous assignment.

**Acceptance.** Fast suite green; full suite green at phase end (persistence touches a lot).

**Definition of done.** Round-trip tests pass; byte-identity test passes; the app builds and behaves
exactly as before, because nothing reads the recipe yet.

**Estimate.** One session, maybe two.

---

## Phase 3 — Evaluation, isolated compositing, preview tier (headless)

**Goal.** Turn a recipe into pixels, correctly, verified by image tests with no UI.

### Work items

1. **`InterpolationEvaluator`** — `evaluate(recipe:at:) -> (forward: [VectorElement], backward: [VectorElement])`.
   Warps A's elements forward and C's elements backward through each group's interpolated lattice,
   applies visibility thresholds, and applies thickness cross-fade.

   > **Two corrections, found while building this (see `HANDOFF.md` §5).**
   >
   > (a) The result is **three** lists, not two: `localEdits` joins neither set. A stroke drawn *at*
   > the in-between is not a keyframe's content being faded in or out, and an `.erase` local edit has
   > to reach both keyframes' ink — which only works if it is drawn after they are blended.
   >
   > (b) **Thickness cross-fade is implemented but off by default.** Thinning is right for a stroke
   > with no counterpart at the other keyframe; without correspondence every stroke looks like that,
   > so defaulting it on thins every mid-frame. It is one option away once a matcher lands.

2. **The isolation requirement (`PLAN.md` §5.6) — the most important correctness item in the phase.**
   Forward and backward sets **must not** be concatenated into one display list: an `.erase` stroke
   lowers the alpha of everything beneath it, so A's eraser would punch holes in C's strokes.

   **Decision: render two `VectorCanvas` instances and blend their images at (1−t)/t.** Not a new
   element kind, not a two-pass change inside `renderLocalContent()`.

   *Why:* it is provably correct by construction, it requires **zero changes** to the renderer's
   carefully documented and heavily-commented isolation rules, and it reuses the existing render path
   whole. The cost is two renders instead of one — acceptable given the preview tier below, and
   optimisable later into a `.group` element **if** measurement shows it matters. Do not pre-optimise
   this.

3. **Polyline preview tier** (`PLAN.md` §8, standing constraint C):

   ```swift
   enum RenderQuality { case full, preview }
   func render(quality: RenderQuality = .full) -> UIImage
   ```

   `.preview` strokes warped polylines as `CGPath`s with a width instead of stamping dabs — roughly
   two orders of magnitude cheaper than the measured ~3.2 ms/stroke. Cache `.preview` and `.full`
   separately so releasing the slider does not discard the preview and vice versa.

   *Budget arithmetic, stated honestly:* at 3.2 ms/stroke a 16 ms frame affords **five strokes** at
   full fidelity, and interpolation renders **two** canvases. Preview mode is not a nicety; scrubbing
   is unusable without it.

4. **Fill warping.** `VectorFillElement`'s path is archived `Data`. Extract control points
   (`CGPath.applyWithBlock`), warp, rebuild. Colour lerps between matched fills.

   > **Partially deferred (see `HANDOFF.md` §8 item 10).** The warping is built; the colour lerp is
   > not, because "matched" needs a correspondence matcher and that is engine D, which
   > `MotionGroup.mode` already defers to a later phase. Fills cross-fade meanwhile. The warp carries
   > each fill's `id` across so a matcher has something to key on.

5. Respect `VectorCanvas`'s lock discipline — private helpers never take the lock; `static` is how
   that is enforced. Read the comment at [VectorLayer.swift:276](PaintSoftware/Engine/VectorLayer.swift:276).

**Files.** New `PaintSoftware/Engine/InterpolationEvaluator.swift`; `VectorLayer.swift`
(add `render(quality:)`, preview drawing, fill point access).

**Tests.** New `InterpolationRenderLogicTests`:

- **Evaluating at `t=0` renders pixel-identical to keyframe A**; at `t=1`, to keyframe C. The
  end-to-end version of Phase 1's invariant.
- **The eraser isolation test:** A contains a paint stroke and an eraser; C contains a paint stroke
  where A's eraser was. At `t=0.5`, C's stroke is **not** punched through. This is the regression
  test for the §5.6 rule and it must exist.
- An eraser present in A and absent in C fades out progressively rather than popping.
- `.preview` and `.full` produce visually similar output (compare downsampled, loose tolerance) and
  `.preview` is measurably faster.
- Evaluation is deterministic: same recipe and *t* → identical bytes.
- The existing raster/vector pixel-parity tests still pass untouched.

**Acceptance.** Fast suite green; the isolation test in particular.

**Definition of done.** All the above pass; no change to `renderLocalContent()`'s element-walking
logic.

**Estimate.** One to two sessions.

---

## Phase 4 — Interpolate mode UI, references, slider, Generate — *first usable milestone*

**Goal.** An artist can do the real workflow end to end, with **one automatic whole-layer motion
group**. Groups become artist-controllable in Phase 5.

### Work items

1. **Mode state** on `CanvasManager` (`isInterpolateMode`), plumbed the way `VectorEraserMode` is
   (`Tool.swift` → `CanvasManager` → `StrokeCanvasView`). Follow that precedent rather than inventing
   a new pattern. Registration runs when **Generate or Reproject** is pressed — it is the expensive
   step, and it needs both keyframes, which mode entry does not have; show progress while it runs.
2. **"Set as Reference"** on the interpolate bar, highlighting the block **yellow** (brief step 2).
   It acts on the block under the playhead. References must be settable across multiple layers
   (requirement 5). **Not a timeline gesture** — press-and-hold there already means drag-reorder, and
   overloading it takes re-timing away exactly while the artist is working on timing.
3. **"Interpolate" action** on a selected block → creates the recipe. Surface **Generate** and
   **Reproject** as *separate* commands (`PLAN.md` §5.5); default to the likely one based on whether
   the cel is empty, but never conflate them. *Reproject may be stubbed to "not yet" in this phase if
   scope demands — say so in the handoff if you stub it.*
4. **The `t` slider** — the timing bar — with live preview wired to `.preview` quality during drag
   and `.full` on release, and undo bracketed per drag.

5. **A thickness-fade toggle in the panel.** `InterpolationEvaluator.Options.thicknessFade` is built
   and defaults to `.none`; `.weighted(exponent: 1)` is the other setting. **Product owner's steer
   (2026-07-31): expose it as a toggle so the ergonomics of each can be assessed on real drawings.**
   It is not a persisted per-recipe setting yet — a view-level toggle feeding `Options` is enough to
   judge it, and where it eventually lives (global preference, per-recipe, per-group) is a decision to
   take after looking at it, not before.
6. **Onion skin in interpolate mode** — supply an `OnionSkinSource` (Phase 0) that shows the two
   reference keyframes, tinted differently.

**Files.** `CanvasManager.swift`, `Tool.swift`, `TimelineTrackView.swift`, `AnimationTimeline.swift`,
`CanvasView.swift`; new `PaintSoftware/Views/InterpolatePanel.swift` (the mode switch and its
settings) and `PaintSoftware/Views/InterpolateBar.swift` (the commands, pinned above the timeline).

**Tests.** Logic tests for mode state, reference selection and recipe creation. **One** XCUITest for
the end-to-end gesture path (enter mode → set references → interpolate → drag slider → content
changes) — one, not a suite; they cost ~20s each.

**Acceptance.** The workflow in `PLAN.md` §0 steps 1–4 works on a real device/simulator.

**Definition of done.** An artist can generate an in-between between two hand-drawn vector keyframes
and scrub it. Undo returns to the pre-interpolation state in one step.

**Estimate.** Two sessions.

### Phases 4.5 and 4.6 — the UI passes *(done)*

Two follow-up passes driven by the product owner's iPad sessions. The layout below is **settled** —
Phase 5 hangs group controls off this bar, so start from it rather than re-deriving it.

- **The entry point is the animation timeline's own top bar**, next to onion skin and loop
  (`AnimationTimeline.interpolateButton`) — not the canvas toolbar. Two-stage like the paint tools:
  first tap enters the mode, a second tap once it is on opens the options popover
  (`InterpolatePanel`: thickness fade, Clear References, Exit Interpolate Mode). There is no mode
  switch inside the popover — the button *is* the switch. `ActivePanel.interpolate` no longer exists.
- **`InterpolateBar`, pinned above the timeline, in two rows.** Top row: the timing (`t`) slider,
  shown only once a recipe exists — it is the most-touched control, so it takes the edge nearest the
  eye. Bottom row, as a `ZStack` so the centre group is centred on the *bar* rather than on the room
  the sides leave: reference counter / refusal message far **left**, Set as Reference · **Generate** ·
  Reproject centred on Generate, Remove Interpolation far **right**.
- **Generate acts on the playhead, not on a cel index** (`interpolateAtPlayhead`). Standing on an
  empty slot between two references and pressing Generate creates the block and attaches the recipe
  as **one** undo step.
- **Generate refuses on a cel that already has a recipe** (`.alreadyInterpolated`), which greys the
  button out. Reproject deliberately does *not* inherit this — re-posing a frame more than once is
  meaningful in a way that re-deriving it is not.

---

## Phase 4.7 — Engine correctness: what the deformation actually does — ***DONE (Session 12)***

**Why this comes before Phase 5.** Motion groups are a *refinement* of the correspondence the engine
produces: they let the artist say "these strokes move together" when the automatic answer is wrong.
Built on top of a correspondence that is wrong in the base case, they become a workaround rather than
a control, and every Phase 5 acceptance test would be written against output that already looks
wrong. The product owner's four test drawings (2026-08-01, `HANDOFF.md` §8 items 27–30) are all
single-group cases — no amount of grouping fixes them.

**What was observed.** Each of these is a two-keyframe drawing of a few strokes; all four are the
simplest possible cases the feature has to get right.

1. A short vertical line → a large offset C. The line **rotated 180°** instead of bending across.
   Suspected: rigid-motion cost is a lower minimum than deformation cost, so the fit prefers to spin.
2. A vertical line → a C **encompassing** it. Registration froze for ~1 minute.
3. The same pair: the line **grew and faded out** while the C **appeared and scaled up**, rather than
   one bending into the other. This is the fade path, not the warp path — meaning the correspondence
   effectively failed and the evaluator degraded to a cross-fade.
4. Two vertical lines → one vertical line. The expected merge did not happen; the transform did
   another 180° and did not resolve. Messy lineart will hit this constantly.

**Approach.** Analysis first, code second — this is a "read and measure before changing" phase.

1. **Reproduce all four as pure-logic tests** with pass criteria that describe the *motion*, not just
   "the pixels differ": e.g. sample the warped path at several `t` and assert monotone progress and
   bounded rotation. Today's render tests would pass on all four broken outputs.
2. **Instrument the ARAP fit** — per-restart ICP residual, final rigid component, iteration count,
   wall time. Items 1/4 are a hypothesis about the objective's minima; confirm it before changing the
   objective.
3. **Go back to the papers.** The product owner will supply PDFs and any public code. Compare what
   they do at exactly the failure points: correspondence initialisation, how rotation is penalised or
   factored out, whether a rigid pre-alignment is subtracted before the elastic fit, and how
   topology changes (two strokes → one) are handled. **If their methods hit the same limits, say so
   and brainstorm rather than reimplementing a known-limited method faithfully.**
4. **Performance is in scope, not a separate concern** — one minute to register four strokes and
   <10 fps to scrub means the engine cannot be *evaluated* artistically, let alone shipped. `HANDOFF.md`
   §8 item 14's `ScrubSession` (hoist the per-drag constants out of the per-tick path) is the designed
   fix and is now measured rather than speculative.

### Status after Session 10 — steps 1–3 done, and what they found

**Step 1 done.** `InterpolationEngineDiagnosticsLogicTests` — three acceptance tests pinned as
`XCTExpectFailure` plus four characterisations that pass. **Item 28 is deliberately not a test:** the
tier builds unoptimised, so a 121-sample fit that takes 0.6s optimised took 598s there.
`deploy/interp-registration-benchmark/run.sh` measures it instead, in seconds.

**Steps 2 and 3 done, and the hypothesis in item 1 above is wrong in an important way.** Rotation is
not a *lower* minimum than deformation — for a straight line the two are **exactly equal**, because a
segment maps onto itself under a 180° turn. It is a tie broken by arithmetic noise, so no rotation
penalty can fix it. Full diagnosis in `HANDOFF.md` §5 ("From Phase 4.7"), paper comparison in §5.11.

**Three plausible fixes were refuted by experiment**, one of them recommended by the reading: a
tangent/drawing-direction term (it breaks the one case the engine currently gets right), lowering
rigidity (the bend ceiling is correspondence, not stiffness), and locking the scale on its own.
`Engine/Deform` compiles standalone with `swiftc`, so an experiment loop is ~5s — **use it before
believing any fix, including one from the papers.**

**Step 4: the performance half is solved and verified.** `PointCloudIndex.nearest` degenerates on a
line-shaped cloud; walking only the ring's own cells gives bit-identical output at 60–78× (94s → 1.5s
at 1000 samples). This is registration, not scrubbing — §8 item 14's `ScrubSession` is still the
separate fix for item 24's 10 fps and is untouched.

### Status after Session 12 — the fixes applied, and the phase closed

Both product decisions were made on 2026-08-01 and built. **The `.clean` correspondence path is
un-deferred for the 1:1 case only** (`HANDOFF.md` §8 item 31), which changes this document's
"Explicitly deferred" list: `N:M` correspondence stays deferred, and a keyframe pair whose stroke
counts differ — or that holds a fill or a placed image — falls back to the point-cloud path exactly
as before. **`icpRestarts: 1` and `allowScale: false` are the defaults** (item 32), together and
only together.

| case | before | after |
|---|---|---|
| 1 — line spins instead of bending | bend 0.16, coverage 0.31 | bend **0.907**, coverage **0.96** |
| 2 — ~1 minute registration | 1000 samples = 94 s | **77 ms**, and *flat* in the sample count |
| 3 — warp degrades to grow-and-fade | bend 0.17, arc length ×3 | bend **0.985** of the C's 1.072 |
| 4 — two strokes will not merge | span 51 of 200 | span **194.6** of 200 |

Case 4's *merge* is still not solved, and 4.7 was never going to solve it: it is the N:M case, whose
answer in both papers is a UI rather than an algorithm (`HANDOFF.md` §8 item 33) — which is Phase 5.
What changed is that it is now watchable instead of a collapsing smudge.

**Definition of done.** All four product-owner cases produce motion an animator would accept, each
pinned by a test that fails on today's engine. Registration on a few strokes is well under a second;
scrubbing holds a usable frame rate at a stroke count the product owner can actually draw with.

**Amendment after Session 10:** "each pinned by a test that fails on today's engine" is met, with one
documented exception — item 28's pin is a benchmark, for the reason above. And **do not assert the
180° flip's outcome in any test**: it varies by build, because the two solutions tie. Assert the
margin between them.

**Met after Session 12, with one part explicitly carried forward.** All three `XCTExpectFailure`
wrappers are off and their tests pass on Session 10's own thresholds — none was loosened.
Registration is 77 ms on iPad-sized strokes, well under the bar. **The scrubbing clause is not met
and is not this phase's**: `HANDOFF.md` §8 item 24's ~10 fps is a per-tick evaluation cost, a
different code path from registration, and item 14's `ScrubSession` remains the designed fix. It is
recorded rather than quietly counted as done.

One amendment to the amendment, learned by applying it: **`testCase27`'s "assert the margin" is
right in spirit but was unsatisfiable as literally written**, because the margin between the two
tied fits is not merely small but provably zero. The rule that survives is the one behind it — never
assert something a tie can flip — and the test now asserts a property both branches share, checked
with keyframe C recorded in both directions. See `HANDOFF.md` §5.

**Estimate.** Two to three sessions — one of which is mostly reading. *Two spent.*

---

## Phase 5 — Motion groups: tagging, auto-grouping, visualisation

1. Residual-split auto-grouping (Phase 1's algorithm) wired in, replacing the single whole-layer group.
2. Tagging UI: lasso/tap strokes → assign to a group; group swatch; **"Tag by stroke colour"** bake
   action (a one-shot populate, *not* a live binding — `PLAN.md` §5.1.1).
3. Per-group `.auto` / `.clean` / `.crossFade` badge. `.clean` degrades to `.crossFade` with a visible
   "could not match" state until Phase 8 — **never silently**.
4. The "what did it decide?" legibility pass: tinted per-group overlay, plus solo/mute.

**Definition of done.** Auto-grouping produces sensible groups on a two-limb test drawing; the artist
can retag and see the result immediately; group state persists and undoes.

> **Signed off (Session 15).** Session 14 held the phase open on one regression — auto-grouping
> over-split a single hand-drawn body into its individual strokes, which then fit as the 180° tie.
> `HANDOFF.md` §8 item 43 is closed: the whole-drawing group is now matched bidirectionally, because
> at that level the two clouds are the same content drawn twice. The pinned test lost its
> `XCTExpectFailure` and two `ARAPLogicTests` were added for the fixture class that was blind to it.

**Estimate.** Two sessions.

### What Phase 5 actually built (Sessions 13–14)

All four items. The engine and model half landed in Session 13 (`2870773`); Session 14 wrote the
tests, took two decisions off the back of them, and built every piece of UI.

- **Item 1 — auto-grouping.** `CanvasManager.registerGroups` replaces the single whole-frame binding
  with one per part: `MotionGrouping` seeded by the artist's tags, measured against the **last**
  keyframe, each part fitted to its own counterpart. **Phase 4's whole-frame answer is preserved bit
  for bit** — a drawing with one part takes the old path, mints no group and tags nothing, which is
  why every Phase 4 test stayed green untouched. Registration **writes the tags back onto both
  keyframes' strokes**, which is what makes the partition visible and correctable, and is also what
  makes group ids stable across re-registration.
- **Item 2 — tagging.** `MotionGroupRow` is the bar's third row: a chip per group (swatch, name, ink
  count), tap to arm, tap a stroke on the canvas to assign, tap the chip again to disarm. Tag by
  Colour is the one-shot populate of §5.1.1. The gesture is `StrokeCanvasView.consumeAsMotionGroupTap`,
  which consumes the touch even on a miss.
- **Item 3 — the mode badge.** On the chip, in its context menu. `.clean` never degrades silently: it
  renders with a warning glyph and the word "fade", because the matcher is deferred and it is
  cross-fading every time, not occasionally.
- **Item 4 — legibility.** `motionGroupOverlayImage` repaints a keyframe's strokes in their groups'
  tag colours, through `setInterpolationImage`; untagged strokes go grey. Solo/mute is
  `InterpolationEvaluator.Options.hiddenGroups`, gated on the mode so it cannot follow the artist out.

**Two decisions taken during the phase** (product owner, 2026-08-05), both recorded in `PLAN.md` §10:

1. **Generate writes motion-group tags onto the reference drawings.** Kept. Without it the partition
   lives only in the recipe, where nothing can show it or correct it.
2. **An artist's tag is a constraint, not a seed.** `MotionGrouping.group` no longer splits a seeded
   group; only the untagged leftover is refined. This was a *test* finding: a stroke deliberately
   moved into a group whose motion it did not share was splintered back out and given a third group.
   What it gives up is auto-grouping discovering a second part inside a group the artist tagged.

---

## Phase 6 — Reproject and editing at an intermediate frame

1. **Reproject** in full (if stubbed in Phase 4): B's own strokes get their own lattice, and `t` slides
   B's pose along the A→C path without replacing linework.
2. **Editing at *t*** (`PLAN.md` §5.4): strokes drawn at *t* are embedded in the deformed lattice,
   carried back to keyframe space by the inverse map, stored as `localEdits`, and given visibility
   threshold τ = *t*. Lattice expansion when a stroke falls outside.
3. Erase at *t*, and lasso transform at *t*.

**Product owner, 2026-08-01:** the artist should be able to draw, erase, **liquify** (a tool not yet
built) and so on at an in-between while it is still transient, and go on adjusting the slider after
each. That is this phase, and items 2–3 are most of it — the eraser needs nothing special, because
an eraser *is* a stroke (`VECTOR_ERASER_PLAN.md` §2.1) and rides the same `localEdits` path. Two
things it adds. **Liquify is a deformation, not an element**, so it does not fit `LocalEdit`'s
"carry a stroke back to keyframe space" shape at all — a liquify at *t* is a warp composed with the
interpolation's own warp, and where it is stored (a per-recipe displacement field? a second lattice?)
is an open design question, not a wiring job. And every editable-at-*t* tool widens `LocalEdit`
beyond a stroke, which is §8 item 6.

**The storage question is answered — `HANDOFF.md` §5.12, Session 16 — and the tool stays deferred.**
A liquify is a **rest-space displacement gesture in its own field on the recipe**: not per-vertex
offsets, because indices do not survive `Lattice.expanded(toContain:)` or a re-Generate (§5.7), and
not inside `localEdits`, because content is warped *by* the lattice while a liquify *is* the lattice.
The point of answering it first was to find out whether it constrained items 2–3, and it does not:
`LocalEdit` stays strokes-only and the field is purely additive whenever the tool is built.

**Tests.** Draw at *t*=0.5, move the slider, confirm the stroke **follows the motion** rather than
sitting still — this is the whole point of the inverse map and the test that proves it works.

**Definition of done.** Brief workflow step 5 works: edit at an in-between, keep sliding, seamless.

**Estimate.** Two sessions.

### Item 1 is done (Session 15, `93b7e02`)

`CanvasManager.registerReprojection` plus a `.reproject` branch in `InterpolationEvaluator.evaluate`.
The mechanism is one structural difference from Generate — **which drawing the rest lattice covers**:
Generate's is drawn over keyframe A and A's content rides it; a reprojection's is drawn over the
target cel's own cloud, and every entry in `lattices`, *including the first*, is a fit of that grid
to a reference. `lattices[0]` is the subject posed as A, `lattices[1]` posed as C, and interpolating
between them is the pose sliding. The subject embeds from **rest**, where it was drawn, so no
geometry is derived.

That first entry being a fit is the invariant Generate's array has and this one deliberately does
not: Generate reproduces keyframe A bit for bit at `t = 0` *because* `lattices[0]` is the rest grid
its content was embedded in, and a reprojected cel is neither keyframe.

Three decisions, all recorded in `HANDOFF.md` §5's Phase 6 entry: the subject reaches the evaluator
as a defaulted **parameter** rather than as a `CelRef` on the recipe; a `.reproject` recipe with no
bindings is **malformed** where a `.generate` one is the legal degenerate case; and Reproject does
**not** inherit `.alreadyInterpolated`, which answers the question Phase 4's comment left open.

**Items 2 and 3 — editing at *t* — are not started.** Item 1 was the self-contained half.

---

## Phase 7 — Guide strokes

1. **Timestamp capture.** `UITouch.timestamp` is currently discarded; add a capture path for guides
   only (`StrokeInput` / `StrokeGestureRecognizer`).
2. Guide tool: draw, render only in interpolate mode, edit geometry with handles.
3. **Geometry → trajectory constraint** on the bound group's lattice.
4. **Stylus velocity → spacing curve** (easing). Tune against real strokes; expect this to feel
   twitchy before it feels good.
5. Spacing chart drawn *as dots along the guide path*; drag a dot to retime that frame.
6. **Per-group binding**, plus a whole-frame option **if cheap** — if binding is a set of group IDs,
   "all groups" is nearly free. If it turns out not to be, drop it and say so.
7. Fetch a guide from another frame: **link** and **duplicate** (requirement 7).

**Definition of done.** Brief workflow step 6 and requirements 6 and 7 work.

**Estimate.** Two sessions.

---

## Feature definition of done

**The feature is DONE when all of the following hold. When they do, stop and report — do not look for
more work.** (See `HANDOFF.md` §3.3.)

1. Phases 0–7 complete, each meeting its own definition of done.
2. The brief's workflow (`PLAN.md` §0, steps 1–6) works end to end on a vector layer.
3. Requirements 1–9 are satisfied, except those explicitly deferred below.
4. Edge cases 1, 2, 3 and 5 behave as designed (`PLAN.md` §7).
5. Full undo across every interpolation action, one step per user action.
6. Old projects load; new projects round-trip.
7. Full test suite green, with no regression in the raster/vector pixel-parity tests.
8. `HANDOFF.md` §2 says "feature complete", and §8 lists any suggested follow-on work.

## Explicitly deferred — do not build these

Recorded so sessions do not scope-creep. Adding to this list is fine; *building* from it is not,
without the product owner's say-so.

- **The `.clean` correspondence path.** `.auto`/`.clean` degrade to cross-fade, visibly.
- **Spline interpolation across 4+ keyframes.** Pairwise only. The data model must *allow* it
  (Phase 2) but must not implement it.
- **Range interpolation** (edge case 4) — architecture must not preclude it; do not build it.
- **Break-link / Commit-to-static.** Frames stay linked indefinitely.
- **The GPU dab rasteriser.** Separate pre-existing project (`VECTOR_ERASER_PLAN.md` §11). The
  polyline preview tier is this project's answer.
- **The liquify / mesh-distort tool.** Phase 1's engine is built to serve it later; the tool is not
  in scope.
- **Compositing/effect layers** (edge case 3, future half).
