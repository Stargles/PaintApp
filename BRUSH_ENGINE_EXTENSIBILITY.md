# Is the brush engine ready for `.ABR` / Procreate brush import?

Written 2026-07-30 (Session 8), in answer to "there may be an overhaul of the paintbrush engine to
support `.ABR` and Procreate brush imports — is the architecture modular enough, and can we shape the
code with it in mind?"

**This is an assessment and a set of seams to preserve, not a plan to build anything.** Nothing here
is scheduled. It exists so the next few sessions do not accidentally close a door.

---

## Verdict

**Mostly yes, and the parts that are right are the expensive parts to get right.** Three decisions
already made — the eraser is a brush, both render tiers go through one `BrushStamper`, and dab
randomness is seeded and replayable — are exactly the ones that make an imported brush behave
correctly everywhere without per-feature work. An imported brush inherits erasing, vector replay,
persistence, and the zero-tolerance parity test **for free**.

There is **one real blocker**, and it is narrow and structural rather than diffuse:

> `DabTarget` can only draw a **circle**. Its entire drawing surface is
> `stampCircle(at:radius:color:alpha:hardness:blendMode:)` ([RasterLayerTexture.swift:14](PaintSoftware/Engine/RasterLayerTexture.swift:14)).

`.ABR` and Procreate brushes are, at bottom, **stamp-image** brushes: a grayscale alpha bitmap
placed per dab with its own rotation, roundness and scale. There is no way to express one through a
circle primitive. This is the overhaul.

Everything else on the list below is ordinary work, not architecture risk.

---

## What is already right, and must not be lost

### 1. One stamper serves every tier

Live raster drawing, vector replay, the eraser, and the shape tool all funnel through
`BrushStamper.stampStroke` → `stampDab` → `DabTarget`. Add a dab kind there and every consumer gets
it at once. Concretely, an imported ABR brush would immediately:

- work as an **eraser** (`isEraser` swaps the blend mode to `.destinationOut` and nothing else —
  plan §2.1's "the eraser *is* a stroke" decision),
- **replay losslessly** on a vector layer, because `VectorStroke` stores the whole `Brush` by value
  and re-stamps it,
- be covered by `RasterVectorParityLogicTests`, which compares the two tiers at **zero** tolerance.

That last one is worth stating plainly: **the parity test is the regression net for the brush
overhaul, and it already exists.** Plan §11 makes the same argument about the GPU port. Any new dab
kind that renders differently in the two tiers fails a test that is already written.

### 2. The replayability contract

`DabRNG` is seeded from the stroke id, `DabLattice` carries a parent's seed to its pieces, and
`DiscardedDabTarget` exists so that dabs *outside* a piece's visible range are still **computed and
then dropped** rather than skipped ([BrushStamper.swift:303](PaintSoftware/Engine/BrushStamper.swift:303)).

This is a real constraint on every dynamic an importer might add, and it is currently implicit. State
it as a rule:

> **Any per-dab random draw must come from the passed-in `DabRNG`, and a dab must draw the same
> number of values regardless of whether it will be drawn.**

A per-dab *conditional* draw (`if someJitter > 0 { rng.unit() }` evaluated per dab rather than per
stroke) desynchronises the sequence, and the failure mode is not a crash — it is a split stroke whose
surviving piece's ink moves, which is precisely the class of bug that cost Sessions 4–7. ABR's angle
jitter, roundness jitter, scatter-count and flow jitter are all exactly this shape.

`applyScatter` is fine today only because `scatter` is constant for a stroke, so its early return is
per-stroke in effect. Do not copy that pattern for a per-dab-varying parameter.

### 3. Imported-asset lifetime is already solved

`ProjectStore` copies every `.custom` brush's texture into `<project>/brushes/` on save and restores
it into the shared library on load ([ProjectStore.swift:96](PaintSoftware/Services/ProjectStore.swift:96)).
So "a project references a brush texture the user later deleted" already has an answer, and ABR/
Procreate imports inherit it. `VectorCanvasData.ImageRef` is the same idea for placed images and is
the model to copy if a brush ever needs more than a file name.

### 4. The eraser degrades gracefully by construction

`VectorEraser.supportsCleanCut` and `supportsSplitting` gate geometric cutting on shape, hardness,
grain, opacity and jitter. A typical imported brush — textured, scattered, angle-jittered — fails
those gates automatically and falls back to the retained alpha punch, which is pixel-exact whatever
the dabs did. **No eraser code has to learn about imported brushes.** That is the payoff of having
written those gates as properties of the brush rather than as a list of known-good presets.

---

## What needs to change

### The blocker: `DabTarget` is circle-only

The seam to introduce is a second primitive alongside `stampCircle`:

```swift
func stampImage(_ texture: CGImage, at point: CGPoint, size: CGSize, rotation: CGFloat,
                color: UIColor, alpha: CGFloat, blendMode: CGBlendMode)
```

Three things make this cheap to add rather than a rewrite:

- There are only **three** `DabTarget` conformers (`RasterLayerTexture`, `DiscardedDabTarget`, and the
  vector renderer's context target), so the protocol is genuinely small to widen.
- `stampDab` already `switch`es on `brush.shape` and the compiler will point at every site.
- It **removes** a known cost rather than adding one. `stampApproximateSquare` fakes one square dab
  with ~16 gradient-filled circles; plan §9 flags that as "wants a measurement first, deferred to
  Phase 5". A real image-stamp path retires it, and `.square` becomes a built-in texture.

**It needs its own cache.** `DabGradientCache` memoizes gradients keyed on colour and hardness, and
`PerfBaselineTests.testDabGradientCacheHitRate` pins the hit rate at 100% with a test whose comment
explains exactly how a naive key destroys it. An image path needs the analogous thing — a tinted,
rotation-bucketed `CGImage` cache — and it needs the same kind of test, or per-dab `CGImage`
construction will dominate everything. Build the cache and its hit-rate test in the same change as
the primitive, not after.

### `BrushShape` and `customTextureFileName` should become one thing

Today `.custom` is a `BrushShape` case with a **parallel optional field** carrying the file name, and
the two can disagree (`.custom` with a nil name, or `.hardRound` with a name set). More to the point:

> **`customTextureFileName` is written by the UI and copied by the project store, but the renderer
> never reads it.** `stampDab` routes `.custom` to `stampApproximateSquare`
> ([BrushStamper.swift:256](PaintSoftware/Engine/BrushStamper.swift:256)).

So the custom-stamp feature is plumbing and persistence with no pixel path behind it. That is not a
bug to fix in isolation — it is the ABR work, arriving early and half-built. When the image primitive
lands, collapse the pair into one payload-carrying enum:

```swift
enum BrushTip: Codable, Equatable {
    case round                       // procedural, hardness gradient — today's soft/hard/pen/pencil
    case stamp(BrushTextureRef)      // imported: ABR, Procreate, or a user PNG
}
```

An enum with a payload makes the illegal states unrepresentable and keeps the `switch` in `stampDab`
exhaustive, which is what turns "add a brush format" into a compile-error-guided change.

### `Brush` will need grouping before it needs fields

`Brush` is a flat struct of ~14 scalars plus three grouped sub-structs (`dynamics`, `grain`,
`blendMode`). ABR and Procreate carry far more: angle and roundness jitter, tilt and azimuth response,
taper, per-dab flow jitter, dual-brush/wet-mix, texture depth curves. Adding those flat means every
one is a new key in `Brush`'s `Codable` surface, and every key is a decode-compatibility question —
`VectorStroke.init(from:)` already exists as a hand-written decoder precisely because a synthesized
one throws `keyNotFound` on a field added later.

Group them the way `dynamics` and `grain` already are (`BrushTipDynamics`, `BrushTextureSettings`,
`BrushTaper`), each with a `static let default` and its own defaulted decode. Then a new setting is
one nested field, not a migration.

### Two smaller notes

- **`brush.shape` is switched on in two places**: `stampDab` and `VectorEraser.supportsCleanCut`. That
  is fine — the second is a deliberate policy decision about what may be cut, not a duplicated render
  path — but a new tip kind must be considered at both, and the eraser one should default to
  *refusing* to cut. Conservative in the safe direction: a false "clean" claim is a visible artefact,
  a false "residue" claim is only a retained element.
- **Grain is procedural and position-based** (`BrushGrain.noiseValue` over canvas coordinates). ABR and
  Procreate grain is an imported tiling texture, usually with its own scale/rotation/depth and a
  choice of *rolling* with the stroke or being *anchored* to the canvas. The current model only
  expresses anchored, which is the right default; rolling grain is a new field, not a new subsystem.

---

## What I would not do

- **Do not port the vector tier to the GPU first.** Plan §11 already argues this, and the brush
  overhaul strengthens it: the parity test is the safety net for *both* projects, and it only holds
  while both tiers share one `BrushStamper`. Change the rasterizer and the stamp format at once and
  neither has a regression net.
- **Do not add an ABR parser before the image primitive exists.** Parsing is the easy, testable,
  pure-data half and it will look like progress. Without `stampImage` there is nothing to render what
  it parses, and the parsed model will get shaped around the wrong renderer.
- **Do not relax `supportsSplitting` to let imported brushes be cut.** Its remaining reason is real:
  the coverage test measures against a capsule chain, and scattered or non-round ink is not bounded
  by one. Leaving imported brushes on the punch path is correct, not a limitation.

## Order, if it is ever scheduled

1. `stampImage` on `DabTarget` + its cache + a hit-rate test. `.square` becomes a texture; delete
   `stampApproximateSquare`. **No file formats involved** — this is the whole architectural change,
   and it is independently valuable (plan §9's deferred square-brush cost).
2. `BrushTip` enum; wire `customTextureFileName` into the renderer it never had. User PNG stamps
   start working — the first user-visible feature, and it exercises the whole path.
3. Group `Brush`'s settings into sub-structs, with defaulted decode.
4. `.abr` parser → `Brush`. Then Procreate `.brush` (a ZIP: `Brush.archive` keyed-archive plist plus
   `Shape.png` / `Grain.png`), which maps onto the same model.

Steps 1–3 are worth doing on their own merits even if no importer is ever written, which is the test
of whether this ordering is honest.
