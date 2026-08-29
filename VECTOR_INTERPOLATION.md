# Vector Interpolation

Keyframe in-betweening on vector layers. **Feature complete** (Phases 0–7, Sessions 1–19). This file
replaces the former PLAN / IMPLEMENTATION / HANDOFF trio: it is the architecture map, the settled
decisions, and — the part worth keeping longest — **§4, the future upgrades**.

## 1. What it does

Mark two cels as references, press **Generate**, and the cels between them become *derived*: they
store an `InterpolationRecipe`, not ink, and are evaluated at their own `t` on every draw. Scrub the
timing slider to see the motion. **Reproject** is the other entry point — it poses an already-drawn
cel between two references instead of inventing one.

The artist can draw and erase *at* an in-between (edits ride `localEdits` and warp with the motion),
tag strokes into **motion groups** so limbs move independently, draw **guide strokes** whose shape
bends the trajectory and whose stylus speed becomes the easing, and finally **Commit** an in-between
to ordinary static content.

## 2. Architecture

Engine, app-type-free (`Accelerate` + `CoreGraphics` + `Foundation` only) — `PaintSoftware/Engine/Deform/`:

| file | what |
|---|---|
| `Lattice.swift` | rest vs current configuration; `embedInRest`/`warp`, `embedInCurrent` (inverse bilinear), `expanded(toContain:)`. **A lattice's rest space *is* canvas space** — growing it only extends which part of the plane is covered. |
| `DeformFactorization.swift` | `Matrix2x2` + polar decomposition, Accelerate sparse Cholesky, the ARAP normal equations. One factorisation per topology; every *t* is two back-substitutions. |
| `ARAPInterpolation.swift` | per-triangle polar interpolation + one global reconciling solve. `t = 0` reproduces A and `t = 1` reproduces C **to the last bit**, through the general path. |
| `ARAPRegistration.swift` | `PointCloudIndex`, `Similarity`, ICP, the ARAP fit with positional constraints, and **tier 0** (`StrokeCorrespondence`, the 1:1 arc-length match). |
| `MotionGrouping.swift` | coarse-to-fine residual splitting; one algorithm, two seeds (automatic, or the artist's tags). |

App layer:

- **Model** — `InterpolationRecipe.swift` (`CelRef`, `InterpolationReference`, `InterpolationMode`,
  `SpacingCurve`, `MotionGroupBinding`, `LocalEdit`), `MotionGroup.swift`, `GuideStroke.swift`,
  and `CanvasManager+Interpolation.swift` (every mutation with its undo bracket, plus render-cache
  eviction). `Cel.interpolation` is where a recipe lives.
- **The seam** — `CelContentProvider.swift` (`DerivedCelContent`, `CelContentProvider`) plus
  `CanvasManager.derivedCelContent(for:atFrame:)`. **What a cel *shows* when that is not what it
  *stores*.** `PixelOps.rasterize(cel:canvasSize:derived:)` takes one, so thumbnails, the ordinary
  onion skin, the composite an export will walk, and `rasterizeLayer`'s bake all see an in-between as
  the frame it displays instead of as nothing. Passed in, never a back-reference from `Cel`. It is
  **frame-aware** for the derivation that comes next (a cel spans frames; a pose key varies across
  them) even though interpolation's own `t` does not read the frame.
- **Evaluation** — `InterpolationEvaluator.swift`: `evaluate(recipe:at:content:)` →
  forward/backward/local-edit display lists plus blend weights; `composite`, `render`, `flattened`
  (Commit), `planLocalEdit` (the inverse map an edit at *t* travels back through).
- **Guides** — `Engine/GuidePath.swift` (`GuidePath`, `GuideHandles`, `SpacingChart`). Geometry read
  by **arc length**, timing by **stylus clock**, never mixed.
- **UI** — `InterpolateBar.swift` (slider row + command row + `MotionGroupRow` + `GuideRow`),
  `InterpolatePanel.swift` (the popover), `GuideOverlayView.swift`, plus the interpolate button on
  the animation timeline's top bar. `CanvasView` memoizes the preview against `InterpolationPreviewKey`.

Tests: `LatticeLogicTests`, `ARAPLogicTests`, `InterpolationModelLogicTests`,
`InterpolationRenderLogicTests`, `InterpolationWorkflowLogicTests`,
`InterpolationMotionGroupLogicTests`, `InterpolationGuideLogicTests`,
`InterpolationEngineDiagnosticsLogicTests`, plus one XCUITest
(`testInterpolateModeEndToEndFromGestureToScrub`). Last full run: **665 tests, 664 passed, 0 failed,
1 skipped by design.**

## 3. Settled decisions and hard-won facts

Things that are cheap to break and expensive to relearn.

1. **An eraser is a stroke.** It warps and fades like any other, with no eraser-specific code
   anywhere in interpolation. At an in-between it is pinned to eraser Mode 1, because Modes 2 and 3
   cut *stored* geometry and an in-between has none.
2. **Generate onto a blank frame, Reproject onto a drawn one — never conflated.** A `.reproject`
   recipe with no bindings is malformed where a `.generate` one is legal; Reproject does not inherit
   `.alreadyInterpolated`.
3. **`icpRestarts: 1` and `allowScale: false`, together and only together.** The multi-start was what
   *created* the 180° flip; the free scale bought a good residual by collapsing the drawing to 15%.
   Either alone is a different wrong answer, and a test pins the half-fix so it cannot be applied by
   accident. `MotionGrouping` keeps 8 restarts with its own reasoning — grouping is where the
   multi-start earns its keep.
4. **Tier 0 (1:1 arc-length correspondence) is what makes a line bend into a C.** It *replaces* the
   point-cloud data rows rather than joining them; the direction bit is scored with each direction
   **self-aligned**; its margin is a fraction of the stroke's **arc length**. `N:M` falls back to the
   point-cloud path, which also refuses any frame holding a fill or a placed image.
5. **Mean residual is a lying metric.** Distance-to-nearest *rewards* piling the source up: a case
   scoring 3.6 covered a quarter of the target. **Coverage** is the measure that catches it (see §4,
   items 32/36/37 — they all want it and it exists only in test-local form).
6. **The root group is matched `.bidirectional`; a part is matched `.sourceToTarget`.** At the root
   the two clouds are the same content drawn twice. Applying the part rule to the root over-split a
   single hand-drawn body into individual strokes — one line, and it cost the answer twice over.
7. **Never assert the 180° flip's outcome in a test.** The two solutions genuinely tie, so it varies
   by build. Assert a property both branches share.
8. **A liquify at *t* is a rest-space displacement gesture in its own field on the recipe** — never
   per-vertex offsets (indices do not survive lattice expansion or re-registration) and never inside
   `localEdits` (content is warped *by* the lattice; a liquify *is* the lattice). The field is not
   built; answering the question is what let `LocalEdit` stay strokes-only.
9. **Commit trades exactness for vectors.** No display list can express an in-between at an interior
   *t* — an `.erase` stroke reaches everything beneath it and `VectorElement` has no group case to
   hold a per-set alpha — so Commit concatenates and accepts the drift. One-way by design.
10. **A guide's constraint is chord-relative** (`chordDeviation`), which is why the endpoint
    invariant survives — and why a guide drawn in an empty corner works as well as one drawn over the
    character (§4 item 46).
11. **`DerivedCelContent.identity` must carry every input the evaluation reads — and it is now the
    only list that has to.** The rule bit three times as `InterpolationPreviewKey`, a hand-maintained
    field list in `CanvasView` enumerating dependencies that live in `CanvasManager`; the last was a
    local edit, which lives on the `Cel` while every version in that key belonged to a `VectorCanvas`
    the edit never touches. **Four caches key on the evaluation now** — `PixelOps.RasterizeKey`,
    `LayerContentVersion`, `OnionSkinRasterCache.Key` and the preview — and as of 2026-08-29 all four
    carry the identity, which is minted beside the closure whose inputs it enumerates so the two
    cannot drift. The preview key is the identity plus the render quality and nothing else. When it
    was replaced its own list was **still** three fields short (`mode`, `spacing`, the groups' fitted
    lattices) plus a fourth nobody had named — `.reproject`'s subject version, which is that mode's
    entire content — and it had got away with all four only because today's UI happens to move a
    reference cel's `version` alongside. `CelContentProviderLogicTests`'
    `testEveryEvaluationInputMovesTheDerivationIdentity` sweeps one mutation per field and is what
    fails when the next one is missed.
12. **Experiment before believing a fix.** `Engine/Deform` compiles standalone with `swiftc` (~5 s a
    loop vs ~90 s through `xcodebuild test`); one session refuted three plausible fixes that way, one
    of which the literature positively recommended.
13. **Registration is independent of stored sample density; the deformation is not.**
    `ARAPRegistration` resamples every stroke to `samplesPerStroke` (16) by arc length before it
    scores anything, so how finely a stroke was recorded cannot move the fit. `InterpolationEvaluator`
    then warps the stroke by mapping **each stored sample**, so density *is* the resolution of the
    bend. That asymmetry is what constrains `StrokeSampleGate`: its threshold is radial, which can
    only push two stored samples one threshold further apart than the input already had them — so a
    slow stroke becomes as coarse as a fast one already is, and no coarser. A deviation-based
    simplifier (Douglas-Peucker and relatives) was rejected for exactly this: it collapses a straight
    run to two points, and two points bend as a straight line under a warp that should curve them.

### What the papers say

[MoStyle/frite](https://github.com/MoStyle/frite) (the code was the useful half) and
[Inria RR-9559](https://inria.hal.science/hal-04797216/file/RR-9559.pdf).

- **RR-9559 is not a registration paper** — it propagates layout from *already registered* drawings.
- **frite has no multi-start rotation search at all** — CPD or centre-of-mass pre-registration, then
  alternating push + ARAP regularisation. Its push phase is per-quad and rigid (ours was per-point
  and translational), and scale is factored out rather than fitted.
- **Neither solves N→M stroke matching. The artist does it**, with a lasso — frite ships
  `CorrespondenceTool`, `directmatchingtool`, `registrationlassotool`, `pickstrokestool`. A fully
  automatic stroke matcher would be past the state of the art, not catch-up. Our motion-group UI is
  the same mechanism.
- **The paper's answer to unmatched content is to fade it out**, farthest-from-target first, via
  per-vertex temporal thresholds. `VectorStroke.visibilityThreshold` and
  `.sampleVisibilityThresholds` exist and **nothing sets them** (§4 item 34).

Standing permission from the product owner: fork those repos and experiment on the forks.

## 4. Future upgrades — the deferred list

**Nothing here is a defect and nothing here is scheduled.** These are improvements noticed during
implementation and deliberately not built; each is the product owner's call. Numbering is the
original's, so older commit messages and code comments still resolve.

### The big one — engine upgrade candidates

**36. Messy/sketchy lineart: match ink to ink, not stroke to stroke.** *The product owner's own
proposal, and the most substantive future upgrade on this list.*

Stop trying to pair strokes at all. Instead fit the warp so the **overlap between the deformed
drawing's ink and the target drawing's ink is maximised**, while **minimising each stroke's
displacement from where the uncorresponded fit already puts it** — i.e. today's rotate-and-translate
answer becomes the regulariser rather than the answer. With the qualifier that is the sharpest part
of the idea: **a higher local density of strokes must not read as more overlap** — many overlapping
strokes of the same colour are the same ink as one stroke, so the objective is over the *ink
footprint*, not over samples.

Three reasons to take it seriously:

- **It dissolves the N:M problem instead of solving it.** No stroke identities in the objective, so
  "two strokes become one" stops being a question. That is the right shape for sketchy lineart, where
  the stroke count is an artefact of how the artist scribbled and carries no meaning.
- **It is the same metric the diagnosis independently arrived at** — coverage (§3 fact 5). Items 32,
  36 and 37 all want it; three separate needs converge on building one thing.
- **There is literature, and it is the literature frite already leans on:** Sýkora et al.,
  *"As-rigid-as-possible image registration for hand-drawn cartoon animation"* — an **image**-based
  ARAP registration. **Get that paper before the brainstorming session.**

Open questions so that session does not start cold: at what resolution is the footprint rasterised,
and does the objective stay differentiable enough for the existing solver or does it become a search;
how colour factors in (the "same colour counts once" rule needs a definition when colours are merely
close); whether it replaces the point-cloud tier or becomes a third tier beneath it; and how it
interacts with the eraser, whose ink is *negative*. It is a per-*group* objective, so it composes
with motion groups rather than competing with them.

**When to build it: as a later pass — it is modular.** The evidence is that adding tier 0 (the
structurally identical thing: a whole new correspondence tier ahead of the existing two) touched one
file plus a call site. Registration already has the seam — `ARAPRegistration.fit`'s data-row
construction, where something decides what pulls where — and the output contract is one type:
everything downstream consumes `MotionGroupBinding`'s fitted `Lattice` per keyframe and knows nothing
about how it was obtained. **The one standing constraint, and it is a product constraint:** keep a
motion group's membership *"which ink is in this group"*, never *"which stroke pairs with which"*. If
pairwise stroke identity gets written into the document model and its undo, item 36 stops being a new
tier and becomes a migration. (This constraint has been honoured — nothing anywhere records that
stroke *X* pairs with stroke *Y*.)

**34. Temporal visibility thresholds — the honest answer to unmatched content.** The paper fades
unmatched strokes out progressively, farthest-from-the-target first, via per-vertex thresholds
diffused from a seed set. `VectorStroke.visibilityThreshold` / `.sampleVisibilityThresholds` have
existed since Phase 2 and nothing sets them. This is the closest correspondence between our model and
the paper's, it is the honest answer to "two lines become one" (one line *retracts* rather than
merging), and it is what finally gives the thickness-fade toggle unmatched strokes to act on. Cheap
relative to its value; depends on tier 0 to know which strokes are unmatched.

**37. Coverage-gated rotation escalation.** How to get large-rotation registration back without
reintroducing the 180° tie: try the local fit first, and widen the rotation search **only** when the
result fails a coverage test, rather than running an unconditional 8-way search every time. Needs the
coverage metric first, then it is cheap.

**33. N→M needs a UI, not an algorithm — and that is the literature's answer, not a shortcut.** The
motion-group UI is already most of that mechanism. What should *not* happen is a speculative
automatic stroke matcher. The complement, for content with genuinely no partner, is item 34.

**1. Automatic grouping cannot separate an attached limb from its torso.** Splitting a spatially
connected group has to come from residuals, and a stroke's residual is its true motion minus the
group's fitted motion — so as soon as that fit contains a rotation, residuals inside one rigid part
vary systematically across it and clustering cuts in the wrong place. Spatially separate bodies split
reliably; a swinging arm does not. **Product owner's steer: expected, not a defect to chase** — the
boundary between limbs is genuinely vague and two reference frames is the minimum possible
information. The intended mitigation is the artist distinguishing limbs by colour, which is Tag by
Colour and is already built. They expect better approaches exist in the literature and may revisit.

**44. A *part* that is itself a hand-drawn body can still over-split.** The same disease as fact 6 one
level down: a part's in-place seed plus eight restarts picks a spurious rotation on jittered content.
Not the same fix — a part genuinely cannot be matched bidirectionally, since the target holds the
other parts' ink. Measured so it need not be re-measured: sweeping `icpRestarts` over 1, 2, 4, 8, 12
gives part counts `3,3,3,2,2` on the two-clean-bodies fixture and `3,3,3,3,2` on the jittered one;
12 gets every fixture right and 1 breaks an existing test — moving the dial on that evidence would be
tuning noise. A real fix needs a per-part prior better than "it has not moved": a coarse flow field,
matching tags, or item 37's coverage-scored restart selection. Over-splitting is the safe direction
and merging is one tap, so this is quality, not correctness.

### Performance

**24 / 14. Scrubbing runs at ~10 fps with four vector strokes, and `ScrubSession` is the designed
fix.** Every slider tick re-embeds both keyframes' geometry (`embedInCurrent` builds a deformed-cell
index) and re-runs the ARAP factorisation — both are *constants across a drag*.
`ARAPInterpolation.Interpolator` exists precisely to be held for the lifetime of a slider drag, and
nothing holds it. Its home is `CanvasView.Coordinator`, alongside the preview key. Measured on the
iPad at four strokes, far below the >1000-object layers the standing constraint anticipates — so this
is the per-tick cost, not the scale problem. Profile before assuming it is the whole story.

**20. Registration cost is untested at scale.** The lattice is ~150 vertices whatever the drawing, but
the *point cloud* is every stroke sample at both keyframes. `maxRegistrationSamples` (250) caps what
drives the fit, so cost is flat in the sample count — what is untested is a >1000-object layer.

**42. `motionGroupChips` walks both keyframes' display lists on every SwiftUI pass.** The ink count is
the genuinely useful part of a chip, but it is O(elements) per pass. Fix if it ever matters is the
same shape as `InterpolationPreviewKey`: memoize against the keyframes' `version`s.

**3. `ARAPRegistration.fit` has no early-out on a converged ICP tier.** Harmless while registration
happens once per keyframe pair; first place to look if it ever runs interactively.

**4. Grouping's pairwise "furthest residual poles" search is O(n²) in strokes per group.** Fine at a
few hundred; >1000-object layers would notice.

**8 / 9. `evictDistantVectorRenderCaches` counts cels, not bytes** — a limit of 12 canvas-sized images
is ~190 MB at 2048² and ~770 MB at 4000². And eviction only runs on a frame or layer change, so a
bulk render (export, thumbnail sweep) never triggers it.

### Model and correctness gaps

**6. A local edit can only be a stroke.** `LocalEdit` carries a `VectorStroke`, so drawing and erasing
at an in-between are covered but a *fill* made there is not. Widening to an element enum later costs
one `decodeIfPresent`. Placed images are a further step again (file management).

**11 / 41. A fill cannot belong to a motion group.** `motionGroupID` is a field on `VectorStroke`
only, so every fill and every placed image rides the recipe's first binding — and, visibly, the group
overlay cannot tint them, so flats stay their own colour while lineart goes red and blue. Fix is the
same field on `VectorFillElement` (cheaper) or a group lookup by geometry; check the overlay in the
same pass.

**10. Fills are not corresponded, so their colours cross-fade instead of lerping.** Two differently
coloured fills go through a muddy half-transparent middle. **Product owner's steer: acceptable for
now, instructions to follow after user testing.** Two things that steer settles — the *base*
capability (handling fills sensibly when both references have filled sections) is in scope and
valuable; and "easy filling across multiple frames" may want to be an **entirely separate tool**, so
do not widen the recipe to chase it. Do not build the matcher speculatively.

**12. A placed image only travels — it does not deform.** One bitmap under one affine, so a lattice
that rotates or shears will visibly slide past it. The real fix is a mesh draw (Core Image or Metal).

**13. `.preview` under-inks a translucent brush.** Overlapping dabs accumulate alpha along a stroke, so
preview reads lighter than full for low-opacity brushes — shape and position right, weight not. A
saturation curve `1 − (1 − a)^k` would fix it; invisible for the opaque brushes most linework uses.

**7 / 19. Nothing prunes a recipe (or a transient reference) whose cel has been deleted.** Detectable
via `referencedCels`/`isWellFormed`, and the evaluator answers "not yet" rather than crashing, so the
effect is accumulation and a silently-shrinking keyframe count, not a crash.

**26. A vector cel still carries `fillImage` and `bakedImage`, so raster features allocate
canvas-sized bitmaps on a vector layer.** Select+move, Clear and bucket fill all go through the raster
path even on a `.vector` layer. **The product owner wants vector fully divorced from raster
features.** It reaches well past interpolation (it is really about what a vector layer *is*).

Item 18's seam was expected to constrain this and **does not** — checked when the seam was built. The
seam's currency is *pixels*, forced by fact 9 rather than by anything item 26 decides, and none of the
four destructive raster paths can reach a derived cel today: Move refuses an in-between outright
(`TopToolbar.toggleMove`, `CanvasManager.activeVectorMoveTarget`), and recolour and clear take their
vector arm on a vector layer. Only the magic wand's read-only flatten was reachable, and it now goes
through the provider. So item 26 can be designed whenever the owner wants it, with no migration owed
to the seam.

**2. No turn-count control for rotations past 180°.** The lattice cannot tear, but the global branch
always takes the short way round, because nothing in two keyframes distinguishes a 200° turn from a
−160° one. Standard remedy is an artist-set turn count per group; the per-triangle angles are already
exposed.

**5. `MotionGrouping` never re-merges.** Over-splitting is the safe direction and merging is one tap,
but a final "merge groups whose fitted motions agree" pass would tidy the automatic result.

### UI and workflow

**45. Transforming at an in-between — two jobs.** (a) **A vector lasso** — selecting a subset of a
vector drawing's strokes and transforming only those does not exist anywhere in the app; this is
really item 26 wearing a smaller name. (b) **The whole-content transform at *t*, currently refused** —
it is a *deformation*, so its home is fact 8's displacement field, an affine being the degenerate
case. The refusal costs the artist nothing they had: the operation was a silent no-op before it was
refused.

**46. A guide does not have to be drawn near the drawing, and the product owner should be told.** The
chord-relative constraint reads only the guide's *shape*, so an arc drawn in an empty corner moves the
character exactly as one drawn over it. A real ergonomic gain — no fighting for space over the
linework — and a *consequence* of making the endpoint invariant survive, not something anyone asked
for. Worth a minute on an iPad: if they want the guide anchored to the motion, the absolute reading
can be offered as an option **on top of** this, not instead of it.

**47. Guides are never deleted, only unbound.** `removeGuideStroke` is built and strips the id from
every recipe; nothing calls it, so an artist who draws a bad arc can only undo. Now one control on
`GuideRow`: Delete, and probably Unbind beside it — different acts on a shared guide.

**48. A second guide on the same frame averages with the first**, which is the least surprising rule.
`GuideRow` says "averaged" when there is more than one. The stronger fix, if it matters on real art,
is drawing the two guides in different colours and the effective path in a third.

**49. `visibleGuideStrokes` shows only the guides of the frame under the playhead.** Correct — a scene
accumulates guides — but the artist cannot see a guide while looking at the keyframe it was drawn
between. The link menu exposes the gap: entries read "Guide from elsewhere 1, 2, 3…" because **a guide
has no name and no thumbnail**. The fix when it bites is a thumbnail on the menu row, not a naming
scheme.

**50. A guide's stylus timing is silently discarded the moment a spacing dot is dragged.**
`binding.spacing` outranks the derived easing by design — that precedence is what makes the chart work
— but there is no way back and nothing says why. A "Use the guide's own timing" reset would close it.

**51. A handle drag on a *shared* guide moves every frame that uses it**, and the only warning is the
link glyph on the chip, while the artist is looking at the canvas. Cheap answer: draw a shared guide's
dashed path in a distinct colour.

**38. A motion group cannot be renamed.** `displayName` is a plain `var` and `addMotionGroup` takes a
name, so the model is done — what is missing is an affordance, left out because a text field in a
context menu brings an iPad keyboard up over the timeline the artist is looking at.

**39. An eraser cannot be tagged, and rides the recipe's first binding.** Right as a default — the
alternative is a group made of every eraser on the drawing — but wrong once a character's erased
highlight has to travel with the arm it is on. The right answer is for an eraser to **inherit the
group of the ink it overlaps**, which `VectorEraser`'s coverage test already computes. Wants a
decision about overlapping two groups.

**40. Auto-grouping can no longer look inside a group the artist tagged**, knowingly accepted — but
there is no "split this group" action, so the artist retags stroke by stroke. A **Split** item on the
chip's context menu, running `MotionGrouping` on that group's members alone, gives the discovery back
*explicitly*, which is the distinction that matters. The algorithm is already there.

**15. A reference on another layer looks identical to one on this layer.** Both are the same yellow;
`CelRef` carries the layer, so a second tint or a badge is all it takes.

**16. The slider does not show where neighbouring in-betweens sit**, so spacing is judged in isolation.
Same information as the spacing chart, in a second place; wants the recipes on the cels between the
two references, which nothing gathers.

### Explicitly deferred — do not build without being asked

- **Spline interpolation across 4+ keyframes.** Pairwise only; the data model allows it.
- **Range interpolation.** Architecture must not preclude it.
- **The liquify / mesh-distort tool** (fact 8 is where it would be stored) and **lasso resize**.
- **The GPU dab rasteriser.** Separate pre-existing project; the polyline preview tier is this
  project's answer.
- **Break-link.** Commit exists and is one-way; break-link does not.

## 5. Open judgement calls for the product owner

Both need an iPad and neither is a test's to make:

1. **The velocity→easing mapping has never met a real stylus.** It is built and pinned by tests, and
   was always expected to feel twitchy before it feels good. Tuning it is a judgement.
2. **Item 46** — whether a guide should be anchored to the motion or stay chord-relative.
