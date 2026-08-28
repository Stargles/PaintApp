# Canvas Resize — Specification

The owner's ask, [TODO.md](TODO.md) item **(9)**, verbatim:

> *"a resize canvas option in actions would be nice, to which users can resize the canvas however they
> want. They should be able to control whether it gets cropped/expanded, or if everything gets scaled.
> I guess a good way to do it is a scale option, which will scale the original stuff on the canvas,
> plus a toggle for it to automatically scale with the new canvas size. Note: if the aspect ratio
> changes, then it should letterbox it. Not in the conventional sense of adding black, just scaling
> the stuff so it fits."*

**The headline: this is roughly two thirds built, under two other names, and neither of them is
reachable from a menu that says "resize".** `CanvasManager.setCanvasPadding` is already a whole-document
crop/expand — it walks every layer × every cel, rewrites all four content tiers, and rewrites
`canvasSize` — constrained only to a symmetric margin. `VectorCanvas.mapping(_:throughSimilarity:)` is
already an exact vector scaler, carrying `stroke.size`, the dab lattice, fill paths, placed-image
transforms and text point sizes through one similarity, with the measurement and the three
exceptions written into its own doc comment. What is missing is the *arithmetic that joins them*, a
dialog, an undo contract, and the answer to what happens on cel 400 of 800.

§0 is the census of what exists and is the most useful part of this document. §1 enumerates every
tier. §2 is the decisions. §4 stages it. §5 is the settled rulings. §6 is the owner's rulings — five
questions, all now answered.

---

## 0. What already exists

### `setCanvasPadding` is a whole-document crop/expand with a symmetric-margin UI bolted on

[`CanvasManager+Document.swift:19-56`](PaintSoftware/Models/CanvasManager+Document.swift). Read it as
the resize it is, not as the slider it looks like:

```swift
commitAllInteractiveState()                         // :28  bake every transient canvas-sized buffer
selection = nil                                     // :29
let offset = CGPoint(x: delta, y: delta)            // :31  centred placement
let newSize = CGSize(width: oldSize.width + 2*delta, height: oldSize.height + 2*delta)   // :32
for layerIndex in layers.indices {                  // :34  every layer …
  for celIndex in layers[layerIndex].cels.indices { // :35  … every cel
    …raster   = …raster.resized(to: newSize, offset: offset)                    // :36-37
    …fillImage  = PixelOps.resizedCanvasImage(fill,  to: newSize, offset: offset) // :39
    …bakedImage = PixelOps.resizedCanvasImage(baked, to: newSize, offset: offset) // :42
    …vector   = vector.resized(to: newSize, offset: offset)                     // :45
  } }
canvasSize = newSize                                // :50
history.removeAll()                                 // :53  not undoable, by design
regenerateAllThumbnails()                           // :55
```

That is the crop/expand behaviour the ask names, complete, for all four content tiers, with the
transient-state bake and the undo invalidation already reasoned about in the doc comment at `:13-18`.
The **only** thing constraining it is that `delta` is one number applied to all four sides. Its
Actions-menu control is the "Canvas Padding" slider,
[`ActionsMenu.swift:217-240`](PaintSoftware/Views/ActionsMenu.swift), range `0...512`
([`CanvasManager.swift:30`](PaintSoftware/Models/CanvasManager.swift)).

**It is NOT what the owner's freeze report (6) meant, and that was settled by asking (2026-08-27).**
The owner: *"by 'try to resize the canvas' I meant moving the canvas with two fingers if I recall
correctly."* This slider is off that hook entirely — see TODO.md (6). What remains is a real cost, now
measured rather than supposed, and §4's stage 1 fixes it regardless of whether it was ever a freeze.

**MEASURED 2026-08-27**, `PerfBaselineTests.testWhatTheCanvasPaddingResizeCosts`, 4 layers × 8 cels at
2048×1024, best of three, simulator. **Taken on a contended machine — 35% idle, another session's
suite running — so every figure is a ceiling, not a floor**, which is the safe direction for a cost
that is being called too large:

| | 32 cels, before | 32 cels, after | at 300 (INFERRED) | at 1000 (INFERRED) |
|---|---|---|---|---|
| whole `setCanvasPadding` | 497 ms | **390 ms** | 3.7 s | 12.2 s |
| of which `regenerateAllThumbnails()` | 86 ms (17%) | 84 ms (**22%**) | | |
| of which the buffer walk | 411 ms (83%) | 306 ms (**78%**) | | |
| peak resident during it | 3.5 GB | **1.8 GB** | | |

"after" is with the per-cel `autoreleasepool` described below, which is the only change made here.

**The thumbnail pass is the small half, and that inverts the guess this section used to carry.** Four
fifths of the cost is the per-cel buffer walk itself, so debouncing or deferring the thumbnails — the
obvious fix, and the one `startThumbnailBackfill` already exists for — would take about 17% off. The
walk is what stage 1 has to move.

**The memory number is the headline, and it is a code fact rather than an accident of the fixture.**
The loop at `:34-48` has **no `autoreleasepool` per cel**. Each cel autoreleases two canvas-sized
images (`renderToUIImage()`, then the `UIGraphicsImageRenderer` output), and nothing drains until the
whole loop returns — so the intermediates for *every* cel are resident at once. 32 cels peak at 3.5 GB
on a document that is 256 MiB at rest. At 300 cels that is tens of gigabytes of un-drained
intermediates (INFERRED, linear in cel count by construction), and on a 3 GB iPad 9 the operation does
not get slow, it gets **jetsammed**. A per-cel `autoreleasepool` is one line, it is
**done** (`CanvasManager+Document.swift:34`), and it takes the peak from 3.5 GB to 1.8 GB and the wall
clock from 497 ms to 390 ms — the time falls as well because a gigabyte of un-drained intermediates is
a gigabyte of page faults. **`flipCanvas` (`:73-88`) is the same loop with the same omission and was
deliberately left alone**: it is the neighbour rather than the thing measured, nothing pins its
behaviour, and it should be changed by whoever is already in it.

**What is still not done, and is stage 1's actual job**: 1.8 GB at 32 cels is still linear in cel
count, and the walk is still synchronous on the main actor. The pool bought a factor of two, not a
different shape.

### The three resize primitives, and what each can and cannot do

| primitive | file:line | what it does | scales? |
|---|---|---|---|
| `RasterLayerTexture.resized(to:placing:)` | [`RasterLayerTexture.swift:380`](PaintSoftware/Engine/RasterLayerTexture.swift) | `current.draw(in: content)` into a `newSize` renderer, raising `interpolationQuality` only when `content.size != size`. A blank texture stays blank and allocates nothing. | **yes**, when the rect is a different size |
| `PixelOps.resizedCanvasImage(_:to:placing:)` | [`PixelOps.swift:414`](PaintSoftware/Services/PixelOps.swift) | the same, for `fillImage`/`bakedImage` | **yes** |
| `VectorCanvas.resized(to:placing:)` | [`VectorLayer.swift:624`](PaintSoftware/Engine/VectorLayer.swift) | derives `k` from the placement rect and **bakes** `_transform ∘ placement` into every element through `mapping(_:throughSimilarity:)`, returning an identity-transform canvas. Lossless at `k == 1`, exact at any `k`. | **yes** |

**That last row is stage 2's correction to this section, and it went in the feature's favour.** It read
*"appends a translation to the canvas-level `_transform`; touches no element"* until stage 2 checked
it — true when this document was written, and false since TODO item (12) stage 3 made the primitive
bake instead. So §2's *"the scale must go into the elements, never into `_transform`"* was **already
satisfied by the existing primitive**, and the vector arm of stage 2 required no code at all: stage 1
widened the parameter to `placing:` with a uniformity assertion, and passing a rect of a different
size is the whole of it. §2 keeps its closed-form derivation as the *stated* form the shipped
primitive is pinned against, not as work outstanding.

The two raster primitives take a **destination rectangle**; crop/expand passes one the size of the
source (a copy, nothing filtered) and the scale mode passes one of a different size (a resample at
`.high`). That one widened parameter is the whole of the raster side of the scale mode — see §2.

### `VectorCanvas.mapping(_:throughSimilarity:)` is the exact vector scaler, already written and already tested

[`VectorLayer.swift:1591-1673`](PaintSoftware/Engine/VectorLayer.swift), built for the lasso move's
scale grip. It takes one element and one similarity and returns the mapped element, carrying every
scalar that a naive point-map would leave behind:

- `.stroke` — `samples` **and** `lattice.samples` mapped; `size *= k` (guarded on `k != 1` so a pure
  translation leaves the stored number bit-identical). `parameters`, `seedID`, `visibilityThreshold`
  and `sampleVisibilityThresholds` are dimensionless and untouched, so the seeded `DabRNG` replays
  and a cut piece still selects its parent's dabs.
- `.fill` — `path.copy(using:)`, id preserved. (Single precision: ~1e-6 of magnitude, not 1e-9.)
- `.image` — `position.applying(t)`, `scale *= k`, `rotation += theta`. Asserts a positive determinant.
- `.text` — `frame.corners`, `frame.size` **and** `recipe.typography.pointSize` all scaled together,
  because `TextFrame.Basis` requires `basis.width == size.width` and the first handle drag or
  keystroke into a still-`autoSize` box would otherwise snap the type back to its pre-scale size.

Its doc comment at `:1563-1586` already carries the measurement the brief for this document quotes —
**264 similarity cases, worst dab displacement 1.3e-13 pt, worst parameter error 8.9e-16**, pinned by
`LassoMoveLogicTests.testAScaledPieceLandsEveryDabWhereTheSimilarityPutsIt` — and already names the
three floors that break it (§2, "the spacing floor").

**It asserts its argument is a similarity** (`:1597-1601`): equal axis norms, perpendicular axes. A
non-uniform stretch trips that assert, deliberately, because `k = hypot(t.a, t.b)` would be one number
standing in for two different axis widths. **The owner's letterbox instinct and the engine's one
existing constraint are the same rule**, arrived at independently, which is the strongest reason to
settle it rather than debate it.

### `CanvasSizePickerView` is create-only and is not on this path

[`CanvasSizePickerView.swift`](PaintSoftware/Views/CanvasSizePickerView.swift), 85 lines. One call
site, [`ContentView.swift:37`](PaintSoftware/ContentView.swift), on the new-document screen. It sets
`canvasManager.canvasSize` on a manager with no layers and calls `addVectorLayer()`. It contributes
the **validation** a resize dialog wants (`1...8192`, `:15-16`, `sizePicker.widthField` /
`sizePicker.heightField` accessibility ids) and nothing else. It is not a resize and never was.

### Two existing defects on this path, which a resize inherits unless it fixes them

1. **`flipCanvas` does not mirror vector content at all.**
   [`CanvasManager+Document.swift:73-76`](PaintSoftware/Models/CanvasManager+Document.swift) says so
   in its own comment and flags it as a follow-up. A resize must not inherit the shape of that
   omission: every tier, or none.
2. **`setCanvasPadding` misses two things that hold canvas coordinates.** `guideStrokes`
   (`CanvasManager.swift:71`, document-level, `TimedSample.x/y` in absolute canvas points) are not
   transformed, so growing the padding leaves every interpolation guide 
   `delta` points off its artwork. And `copiedCel` (`CanvasManager.swift:481`) is a canvas-sized
   clipboard payload that nothing clears; `pasteCel`
   ([`CanvasManager+Timeline.swift:141-147`](PaintSoftware/Models/CanvasManager+Timeline.swift)) does
   no size check, so a copy-resize-paste installs a cel whose `RasterLayerTexture.size` is the old
   canvas's. Both are one line each in the generalised loop, and stage 1 fixes both.

### One more thing already on this path, and it is a trap

**The raster tier already rescales on load, non-uniformly, silently.** `decodeCel` builds every
texture as `RasterLayerTexture.load(from: image, size: canvasSize)`
([`ProjectStore.swift:1088`](PaintSoftware/Services/ProjectStore.swift)), and `setContents` draws the
decoded PNG as `image.draw(in: CGRect(origin: .zero, size: size))`
([`RasterLayerTexture.swift:231-247`](PaintSoftware/Engine/RasterLayerTexture.swift)). So a PNG whose
dimensions disagree with `manifest.canvasWidth/Height` is **stretched to fit, aspect and all**.

The vector tier does not do this — `VectorCanvas(size: canvasSize, elements: …)` leaves elements
alone. So a "resize" implemented as *"just change the manifest header"* would look like a crop before
the save and like a non-uniform stretch of the raster half only after the reload. That path must be
closed off explicitly: **the header and every buffer move together, in one operation, or not at all.**

### What does *not* exist

- No `HistoryActionLabel` case for a canvas resize
  ([`HistoryActionLabel.swift`](PaintSoftware/Models/HistoryActionLabel.swift), 73 cases; `.resizeFrame`
  is a *timeline* duration op and `.transform` is a layer transform). The enum's exhaustive `phrase`
  switch means adding the feature without a label is a build failure — which is the mechanism that
  will force the decision in §2 to be made rather than defaulted.
- No scaling raster primitive. `ImageWarp` ([`ImageWarp.swift:65`](PaintSoftware/Engine/ImageWarp.swift))
  is the app's only true resampler, and it is a *homography* warp built for text distort — far more
  machinery than a uniform scale needs.
- No transform for `Lattice` / `InterpolationRecipe` (§1).
- No determinate progress UI anywhere in the app. The only *working* long-operation pattern is
  `GalleryOpenState` + `Task { await Task.yield(); await …InBackground() }`
  ([`GalleryView.swift:134-145`](PaintSoftware/Views/GalleryView.swift)); the two other spinner flags
  are dead (`isRegisteringInterpolation` guards synchronous work and can never be observed;
  `isFilling` is declared and read but never assigned).

---

## 1. Every tier, and what a resize owes it

`M` below is the single resize map defined in §2. `k` is its scale factor (1 in crop/expand mode).

| tier | where | crop/expand | scale |
|---|---|---|---|
| `Cel.raster` | `Cel.swift:9`, `RasterLayerTexture` | redraw at offset; blank stays blank and free | **resample** — lossy, irreversible |
| `Cel.fillImage` | `Cel.swift:12` | redraw at offset | **resample** — lossy |
| `Cel.bakedImage` | `Cel.swift:15` | redraw at offset | **resample** — lossy |
| `Cel.vector` elements | `VectorLayer.swift:244` | `mapping(_:throughSimilarity:)` per element, with the translation baked in | the same call with `k != 1` — **exact** |
| `VectorCanvas._transform` | `VectorLayer.swift:245` | **comes out identity in both arms.** `resized(to:placing:)` bakes it into the elements (TODO item (12) stage 3), so nothing in the app produces a non-identity cel transform | same |
| `VectorCanvas.size` | `VectorLayer.swift:233` | new size | new size |
| `Cel.thumbnail` | `Cel.swift:26` | nil it; `startThumbnailBackfill()` | same |
| `Cel.interpolation` lattices | `InterpolationRecipe.swift:109` → `Lattice.swift:40-45` | `restOrigin` + `vertices` translate | `restOrigin`, `vertices` through `M`; `restCellSize *= k`; `cols`/`rows`/`activeCells` untouched |
| `LocalEdit.stroke` | `InterpolationRecipe.swift:142` | translate | through the same `mapping` — **it lives in the lattice's rest space, so it moves *with* the lattice; mapping it a second time in canvas space is the trap** |
| `MotionGroup` | `MotionGroup.swift` | — | — (ids, name, colour, mode; no geometry) |
| `InterpolationRecipe.t` / `SpacingCurve` | `InterpolationRecipe.swift:188`, `:64` | — | — (normalised 0…1) |
| `guideStrokes[].samples` | `CanvasManager.swift:71`, `GuideStroke.swift` | translate — **missed today** | through `M` (`x`,`y` only; `pressure`/`time` are unit-free) |
| `AlphaMask` | `AlphaMask.swift:31` | — | — **nothing at all.** A mask is a list of source UUIDs resolved at render time (LAYER_COMPOSITING.md §6.1); its coverage cache is keyed on width/height (`MaskResolver.swift:88-90`) and self-invalidates |
| `Layer`/`LayerFolder` effects, blend modes, opacity, `compositorRole` | `ProjectManifest.swift:242-336`, `:131-230` | — | — (no geometry) |
| `ViewPreset` | `ViewPreset.swift` | — | — (visibility dictionaries) |
| onion skin | `OnionSkinSource.swift:843-899` | — | — (derived per frame, cache keyed on `(cel, canvasSize, size)`) |
| `selection`, `floatingPiece`, `vectorFloat`, `shapePreviewTexture`, interactive fill/shape/text | `SelectionModels.swift:125-200`, `CanvasManager.swift:2235` | **bake, then discard** — `commitAllInteractiveState()` + `selection = nil`, exactly as `setCanvasPadding:28-29` already does | same |
| `copiedCel` | `CanvasManager.swift:481` | **clear it** — see §0 | same |
| `canvasPadding` | `CanvasManager.swift:27` | preserved literally, in points | preserved literally — see §5 |
| every size-keyed cache | `PixelOps.RasterizeKey`, `MaskResolver.CacheKey`, `EffectPipelines.scratchSize`, `OnionSkinRasterCache` | self-invalidating; purge to reclaim the bytes | same |
| compositor admission | `MetalCompositor.swift:516-525` | — | **re-checked implicitly, and the gate is about memory, not speed** — jetsam kills the process before `Metal.makeTexture` would return nil (`:505-506`). Growing the canvas raises `peakCompositeTextures × w·h·4` against `CompositorBudget.textureBudgetBytes`, a threshold set by the document's layer/effect structure as much as by the canvas. The live canvas is pre-shrunk below it by `affordableSize` and softens instead of refusing; the dialog warns and proceeds — §5 rule 14, §6 Q5 |

**A resize that handles the active cel and forgets the other 999 is a data-loss bug**, and the shape
of that bug is already in the tree: PERFORMANCE.md item 14 records three independently-scoped
cel-eviction designs, all declined, and the first was declined precisely because
`RasterLayerTexture.hasContent`'s door *"is consulted by `flipCanvas` and `setCanvasPadding`, both of
which call `history.removeAll()` one line later and both of which would, under deferral, read every
off-window cel as blank and silently discard it."* Whatever this feature does, it iterates every cel
of every layer eagerly, and it must not become the reason that eviction design gets revisited.

---

## 2. The decisions

### One map, `M`, and every tier applies the same one

Old extent `O = (Ow, Oh)`, new extent `N = (Nw, Nh)`, both ≥ 1 canvas point.

```
k  = scaleContent ? (fill ? max(Nw'/Ow', Nh'/Oh') : min(Nw'/Ow', Nh'/Oh')) : 1   // Fit (default) or Fill
Cw = k·Ow ,  Ch = k·Oh                             // the old *buffer* placed in the new canvas
dx = p + (Nw' − k·Ow')/2 − k·p ,  dy = …           // centred, in artwork space
if !scaleContent { dx = dx.rounded() ; dy = dy.rounded() }
M  = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: k, y: k)
```

`M` maps a point `p` in the old canvas to `k·p + d` in the new one. MEASURED (scratch `swiftc`,
2026-08-27): the matrix form and the hand form agree to `< 1e-12`, and the `.scaledBy` spelling is the
one that means *scale first, then translate* — the other order is wrong and reads identically. Both
identities are now XCTest assertions on the shipped types rather than scratch findings
(`CanvasResizeLogicTests.testTheMapIsScaleThenTranslateAndNotTheOtherWayRound` and
`…IsSection2sClosedForm`), the second over §2's own 324-case grid.

**`O` and `N` here are buffer extents; `O'` and `N'` are those extents inset by `canvasPadding` on
every side, and `k` is the ratio of the *primed* pair.** This section wrote `k = min(Nw/Ow, …)` until
stage 2 built it, and the unprimed reading is wrong on any document with a margin. On 10 pt of padding,
growing a 100 pt artwork to 200 gives a buffer ratio of `220/120 = 1.833` where the artist typed a
number meaning 2: their drawing comes out 183 pt wide inside a margin that has silently grown to 18.33.
That is exactly the "two Actions controls fighting over one number" §6 Q3 rejected, arriving through
the scale arm instead of through the fields, and §5 rule 9 is what settles it — the padding is a
working margin in canvas points and never scales, so it is the artwork that has to land where the
artist asked. At `k == 1` the two readings are identical (`(Nw − 2p) − (Ow − 2p) == Nw − Ow`), which is
why nothing caught it in stage 1. The consequence, stated rather than hidden: with padding, Fit places
`k × oldBuffer`, which exceeds the new buffer by `2p(k − 1)`, so **ink drawn out in the old margin can
overflow even under Fit** — the same crop Fill applies to everything, applied to the margin only.
Pinned by `CanvasResizeLogicTests.testTheScaleFactorIsTheArtworkRatioAndNotTheBufferRatio`.

**`M⁻¹` flips Fit to Fill, and that is not a detail of stage 3's undo.** `k = min(rx, ry)` going out
wants `1/k = max(1/rx, 1/ry)` coming back, which is Fill's rule on the reversed ratios. Deriving the
inverse from `scale != 1` — what `CanvasResizeMap.inverse` did while only crop/expand could run —
picks Fit both ways and returns `1/max(rx, ry)`, the wrong factor on every aspect change. Latent
rather than live, and fixed in stage 2 because stage 2 is the first thing that can reach it.

**`min` is Fit, `max` is Fill — the same map either way, and this is not disturbed by offering both**
(§6 Q4). `min` fits the content inside the new extent, leaving genuine empty canvas — real paper,
`canvasBackgroundColor`, never a painted bar — on the axis that did not bind; that is the owner's
*"just scaling the stuff so it fits"* and stays the default. `max` covers the new extent and lets the
overflow hang off the edges instead. Fill is not a second feature: `M` is the one formula above with a
different choice of ratio, and `VectorCanvas.mapping(_:throughSimilarity:)` accepts it unchanged,
because Fill is still a single uniform scale. What Fill does cost is a second instance of the
vector/raster asymmetry below.

**Why centred and not top-left.** `setCanvasPadding` is centred (`:31-32`), which is the precedent, and
a drawing on a canvas being grown belongs in the middle of the larger one. Under scale, exactly one of
`dx`/`dy` is zero and the other is half the slack.

**Why `dx`/`dy` are rounded to whole points when `k == 1` and not when `k != 1`.** A bitmap drawn at a
half-point offset is filtered; crop/expand must be pixel-exact or it is a lossy operation pretending
not to be. Under scale the draw is a resample anyway, and rounding the offset there would put the
raster tier half a point away from the vector tier on the same cel — which is the one thing that must
not happen. MEASURED: with whole-point rounding, crop/expand out and back lands on **exactly** the
original offset (residual 0.0 pt over the cases tried).

**One map, expressed once.** Not "a draw rect for the raster and a scale factor for the vector" —
those are the same `M` written twice, and two expressions of one geometry are how they come to
disagree. The precedent is explicit: `RasterLayerTexture.flippedImage`'s doc comment
(`RasterLayerTexture.swift:339-345`) says it exists as one function because *"a canvas flip has to
move all three raster tiers … in exact lockstep, or content lands on the wrong side of the canvas
relative to the rest."*

### The raster side is one widened parameter

The three primitives in §0 take `offset: CGPoint` and draw at the source's own size. Replace that with
a destination rectangle:

```swift
func resized(to newSize: CGSize, placing content: CGRect) -> …
```

- crop/expand: `content = CGRect(origin: d, size: O)` — byte-identical to today's behaviour.
- scale: `content = CGRect(origin: d, size: CGSize(width: k·Ow, height: k·Oh))`.

`setCanvasPadding`'s existing call becomes the first form and changes nothing. Set
`interpolationQuality = .high` on the scale path (the app sets it exactly once today, to `.none`, in
the fill shader's mask upload — `CanvasManager+Fill.swift:858`; the default is `.default`, and for a
one-shot whole-document resample the difference is worth the milliseconds).

### The vector side scales the *elements*, and must not scale `_transform`

`VectorCanvas.render()` renders the display list into a canvas-sized bitmap **first**, then applies
`_transform` to that bitmap (`VectorLayer.swift:2219-2228`). So a scale folded into `_transform` — the
obvious generalisation of `resized(to:offset:)` — is a **bitmap resample of the vector render**: the
strokes are stamped at their old sizes into a bigger buffer and then blown up. Every reason the vector
tier exists is lost in one line, invisibly, and the result still *looks* right at a glance.

The scale goes into the elements, through `mapping(_:throughSimilarity:)`, which re-stamps the brush
at the new size on the next render. **The composition with an existing layer transform has a closed
form**, and it is simpler than a conjugation:

> Scale every element by `S = CGAffineTransform(scaleX: k, y: k)` about the local origin, and replace
> `_transform`'s translation with `(k·tx + dx, k·ty + dy)`. Leave `a, b, c, d` untouched.

Derivation: `_transform` is a similarity `T(x) = k_T·R·x + t_T` (its own accessor `transformScale` says
so — the overlay only ever produces translate·rotate·uniform-scale). Wanting `M ∘ T`, and storing
elements in `L' = k·L`, gives `M(T(L'/k)) = k_T·R·L' + (k·t_T + d)`. **MEASURED** (scratch `swiftc`,
2026-08-27, 324 cases spanning `k_T ∈ {0.31, 1, 2.7}`, `θ ∈ {0°, 17°, 90°, 213°}`, three translations,
three resizes, three probe points): worst deviation from `T` then `M` is **1.8e-12 pt**. It degenerates
to today's `resized(to:offset:)` exactly when `k = 1`.

`mapping` asserts a similarity, so this is only well-defined because `k` is a single number — which is
the letterbox rule. A per-axis stretch has no correct `stroke.size` and is not offered.

### The vector/raster asymmetry is permanent, and undo has to say so

A vector resize is **exact and invertible**: geometry through a similarity, brush re-stamped at the new
size. Resize to 0.25× and back to 4× and the samples return to within float noise (1.3e-13 pt, the
figure `mapping`'s own doc carries).

A raster resize is a **resample**: `draw(in:)` filters, a downscale discards pixels, and the inverse
upscale invents them. It is irreversible in the ordinary sense — round-tripping a raster cel through a
0.5× and a 2× leaves a visibly softer image. Crop/expand is worse still on the shrink: pixels outside
the new bounds are simply gone.

Three consequences, the first two settled in §5:

1. **The undo of a resize restores the geometry exactly and the pixels approximately**, and the
   operation says so at the moment it happens rather than at the moment the artist presses undo.
2. **The operation can tell which case it is in, up front, and for free.** A document where every cel
   reports `raster.hasContent == false` with `fillImage == nil` and `bakedImage == nil` has an exactly
   invertible resize. That is not a corner case: it is what the owner's real packages measure as
   (PERFORMANCE.md item 14 — three cels on the device's largest live project, all with a fully
   transparent raster tier, all now omitted from the save entirely).
3. **Under Fill, the asymmetry gets a second instance, and it is the interesting one** (§5 rule 2,
   §6 Q4). Content that overflows the new canvas is *kept* on the vector tier — an off-canvas element
   is still an element, exactly as §6 Q1 already established for stored coordinates that leave
   `[0, extent)`, which they do routinely — but every raster tier is cropped destructively, because a
   raster tier is a buffer of exactly the canvas extent and the overflow has nowhere to live. This is
   not a rule 11 refusal case: nothing is unmappable, `M` is defined everywhere, and a raster tier
   losing pixels off its own edges is the same thing an ordinary crop/expand shrink already does,
   above.

### The spacing floor: a large downscale changes how a stroke stamps, not only where

`BrushStamper.stampSpacing` is `max(brushSize · spacingFraction, 1)`
([`BrushStamper.swift:67`](PaintSoftware/Engine/BrushStamper.swift)). The `1` is an **absolute** floor
in canvas points and does not scale. Below `brushSize · spacingFraction == 1` the dab spacing stops
tracking the brush size, so a scaled stroke gets a different dab count.

MEASURED (scratch `swiftc`, 2026-08-27, reproducing `stampSpacing` and `advance` exactly). Where the
floor does **not** bind at either size, over 144 cases spanning five brushes × three sizes × five
scale factors × three stroke shapes, every dab lands within **2.7e-12 pt** of exactly `k` times where
it was — the similarity is exact, as `mapping`'s doc says. Where it binds, the dab count changes in
**81** of the cases tried. The threshold per built-in brush:

| brush | `spacingFraction` | floor binds below | default size | at its default size |
|---|---|---|---|---|
| Soft Round | 0.08 | 12.50 pt | 18 | free |
| Hard Round | 0.05 | **20.00 pt** | 10 | **already floored** |
| Pencil | 0.04 | 25.00 pt | 6 | **already floored** |
| Pen | 0.03 | **33.33 pt** | 4 | **already floored** |
| Square | 0.15 | 6.67 pt | 16 | free |

**Three of the five built-ins are inside the floor at their shipping default size.** So this is not a
hairline case reachable only by a heavy shrink — it is the ordinary case, and it binds on an *upscale*
as well as a downscale. While the floor holds at both sizes, spacing stays 1 pt while width goes
`S → kS`, so **the number of dabs covering any one pixel changes by exactly `k`**. For a dab whose
alpha is 1 that is invisible (opaque over opaque is opaque). For a dab whose alpha is below 1 it is a
change in apparent opacity — which means every pressure-tapered stroke end, every light-pressure
passage, the whole of a Pencil stroke (`opacity: 0.9` plus grain at `depth: 0.55`), and any brush the
artist has given a `flow` below 1.

**What the spec does about it: nothing, knowingly, and it says so out loud.**

- Fixing it means making the floor relative rather than absolute, which changes how *every existing
  stroke in every existing document* renders — a far larger and riskier change than this feature, and
  one that belongs in [BRUSH_ENGINE_EXTENSIBILITY.md](BRUSH_ENGINE_EXTENSIBILITY.md) if anywhere.
- Baking the old spacing into the stroke would mean a new persisted field on `VectorStroke` and would
  make a scaled stroke stop matching a freshly drawn one of the same size — trading a change nobody
  can name for a permanent inconsistency.
- The scale mode already carries the same three floors through the lasso move's scale grip, shipped
  and pinned by `testTheSpacingFloorIsTheOnePlaceAScaleChangesTheDabCount`. This feature inherits an
  existing, documented, tested limitation rather than introducing one.
- The floor's siblings inherit the same way: `stampDab`'s **0.5 pt** diameter floor
  (`BrushStamper.swift:237`), `stampApproximateSquare`'s two **1 pt** floors (`:280`, `:282`), and pencil
  grain, which samples an absolute canvas-position noise field (`grainAlphaMultiplier`, `:269-273`) and
  therefore re-samples under a translation as much as under a scale — so a scale is no regression
  there either.

What the spec *does* do: **name the effect in the dialog** when the scale factor would move a stroke
across a floor. One sentence, once, at the moment the artist chooses — *"Brush textures will re-stamp
at the new size"* — is the difference between a known trade and a mystery.

### Undo: one step, no pixels in it, and the whole stack below it goes

`UndoHistory` charges in approximate retained bytes against `maxCost = min(max(physical/16, 64 MiB),
768 MiB)` — **192 MiB on the owner's iPad 9** — summed across *both* stacks
([`UndoHistory.swift:83-86`](PaintSoftware/Models/UndoHistory.swift), `:140-142`), and it evicts oldest
silently rather than refusing (`:201-206`). A whole-cel operation is charged `w·h·4` twice = **16 MiB at
2048×1024**, so about **12** fit (PERFORMANCE.md item 13, owner-ruled correct 2026-08-21).

**A snapshot-based undo of a full-document resize is therefore not merely expensive, it is absurd**:
800 cels × 16 MiB is 12.8 GiB against a 192 MiB budget, and `trim()` would evict the entire history
including the resize itself. That door is closed. So:

1. **`history.removeAll()` first.** Every entry below a resize holds canvas-coordinate pixel patches at
   the old dimensions — `StrokeCanvasView.swift:820` stores cropped before/after `UIImage`s keyed to
   `RasterLayerTexture.strokeDirtyRect`, `SelectionModels.swift:702` stores whole-cel images. Restoring
   any of them after a resize puts pixels at the wrong size in the wrong place. `setCanvasPadding:53`
   and `flipCanvas:81` already do this, for exactly this reason.
2. **Then record exactly one step, whose undo is the inverse resize.** `M⁻¹` is `k' = 1/k` with the
   complementary offset; the same walk runs backwards. It captures no pixels, so its cost is the
   structural shape already in use — `4096` flat plus `Σ elements.count × 512` for the vector arms
   (`CanvasManager+Undo.swift:68`, `CanvasManager+LassoMove.swift:439`). At 800 cels × 200 elements that
   is ~82 MiB, inside budget; at 800 × 1000 it is ~410 MiB and would evict itself, so the cost formula
   must be the flat structural one plus a *bounded* term, or the step charges `4096` and the honest
   answer is that the closures retain the old `VectorCanvas` objects, whose real cost is the elements.
   **The vector arms are the only thing this step retains, and stage 3 must measure that number before
   claiming it fits.**
3. **Undo depth after a resize is 1.** That is strictly better than today, where it is 0.
4. **The undo of a lossy resize is announced when the resize happens**, via `CanvasNotice` — the
   banner machinery is already built and already used for hidden layers and for undo/redo itself
   (`CanvasManager.swift:2361`). Not a modal: the artist asked for the resize.
5. **A new `HistoryActionLabel` case, `resizeCanvas`.** `.resizeFrame` is a timeline op; reusing it
   would put "resize frame" in the undo banner for a document-wide operation.

### Memory and time: per-cel, bounded fan-out, and never `regenerateAllThumbnails`

The budget is 192 MiB on the owner's iPad 9 (`physicalMemory / 16`, clamped `[64 MiB, 768 MiB]`,
`Compositor.swift:167-171`), and it exists for memory rather than speed — `Metal.makeTexture` does not
return nil under this pressure, jetsam kills the process first (`MetalCompositor.swift:505-506`). An
over-budget composite is declined (`:516-525`), but nothing is purged there: the cache-dropping purge
belongs to the *other*, dynamic gate (`os_proc_available_memory()` pressure, `:530-538`), which reacts
to the OS rather than to canvas size. On the live canvas the size gate never fires at all —
`makeSandwichRequests` sizes its request through `CompositorBudget.affordableSize` first, so an
over-large document composites fewer pixels instead of being refused (§6 Q5). The arithmetic that
matters, all **INFERRED** from `w·h·4`:

| | 2048×1024 | growing to 4096×2048 |
|---|---|---|
| one canvas-sized `CGContext` | 8.0 MiB | 32.0 MiB |
| one cel's raster arm at peak (old context + old `UIImage` + renderer buffer + new context) | ~24 MiB | **~80 MiB** |
| ditto with `fillImage` and `bakedImage` present too | ~72 MiB | **~240 MiB** |

So: **`PixelOps.parallelMap` must not be pointed at the raster arm.** Eight cores × 80 MiB is 640 MiB
and a jetsam. The rules:

1. **Stream, cel by cel, replacing each tier in place and releasing the old before the next.** No
   second copy of the document exists at any moment.
2. **Fan out the vector arm freely** — mapping an element array is kilobytes, and the fan-out helper
   (`PixelOps.parallelMap`) is the same one the save already uses per cel.
3. **Bound the raster arm's concurrency**, derived rather than typed: `max(1,
   CompositorBudget.textureBudgetBytes / (2 × newCanvasBytes × 3))`. At the owner's canvas growing 4×
   that is 2; at a shrink it is more. Do not tune `CompositorBudget` itself — PERFORMANCE.md §5 rules
   that out in as many words.
4. **Never call `regenerateAllThumbnails()`.** Set `cel.thumbnail = nil` and call
   `startThumbnailBackfill()` — the deferred `.utility` pass PERFORMANCE.md item 9(c) already shipped,
   which batches by layer, walks layer *ids* not indices, and version-checks each install. This is
   also the free fix for `setCanvasPadding` and `flipCanvas`, whose 96.3 ms-of-a-303.6 ms-open figure
   is the same walk.
5. **Purge the size-keyed caches after the swap** — `PixelOps.rasterizeCache` and the compositor pool,
   through the purge item 12 shipped for backgrounding. They self-invalidate by key but hold their old
   bytes until FIFO eviction, and a resize is precisely the moment the old bytes can never hit again.
6. **Off the main actor, with the busy state on.** Copy `GalleryOpenState`'s shape exactly, including
   the `await Task.yield()` that commits the spinner's frame before the work starts. Indeterminate for
   stage 1 (it is what the app has); determinate `n / total` at stage 3, because unlike every other
   long operation here the total is known before the first cel.

**MEASURED 2026-08-28, `PerfBaselineTests.testWhatScalingEveryCelCostsAgainstCroppingIt`** — the
figure §4 stage 2 owed. 4 layers × 8 cels at 2048×1024 ↔ 1024×512, best of three, simulator, Debug,
**on a contended machine (30% idle)**, so every absolute figure is a ceiling:

| | scale | crop/expand | ratio |
|---|---|---|---|
| run 1 | 854.0 ms — **13.3 ms/cel** | 390.7 ms — 6.1 ms/cel | **2.19×** |
| run 2 | 634.8 ms — **9.9 ms/cel** | 311.9 ms — 4.9 ms/cel | **2.04×** |
| peak resident | ~490 MB | ~305 MB | 1.6× |

**Scaling costs about twice what cropping does, and `.high` is not what it costs.** A third run with
`interpolationQuality` forced to `.default` in both primitives (experiment, reverted) measured
**2.28×** — no cheaper than `.high` once load is divided out. So the `.high` decision above is right
for a stronger reason than it gave: there are no measurable milliseconds to trade, because the 2× is
the cost of resampling *at all* rather than of the quality setting, and no setting recovers it.

At the owner's real document size that is **3.0–4.0 s for 300 cels and 9.9–13.3 s for 1000**,
synchronously on the main actor, at a peak linear in cel count. Not affordable — and neither is
crop/expand, at 1.5 s and 4.9 s on the same walk, which stage 1 already shipped. **Scaling does not
create the problem; it doubles it**, and stage 3 has to size its bounded-concurrency budget against
10 ms a cel rather than 5.

### Failure and partial completion: validate first, then a mutation that cannot fail

`ProjectStore.writeAtomically` has three silent failure returns (`:559-562`, `:568-573`, `:574-586`),
its failure atom is the whole document package, and `ContentView.saveIfNeeded:94` branches on `.ask`
and nothing else — so a total save failure looks exactly like a success
([ARCHITECTURE_REVIEW.md](ARCHITECTURE_REVIEW.md) finding 3). A resize is the one operation after which
that matters most: it is the only edit whose loss cannot be reconstructed from memory, because the
in-memory document has already been overwritten.

Four rules:

1. **Nothing is written to disk during a resize.** The operation is entirely in memory; the atom is the
   in-memory document. There is no half-resized package because there is no package write.
2. **The failure modes are enumerable and are all detectable before anything mutates.** Rendering
   cannot fail — `UIGraphicsImageRenderer` returns an image or the process is jetsammed, which is not a
   return value. What *can* fail is per-element and is a decode: `VectorFillElement.cgPath` returning
   nil on a damaged archived path, `path.copy(using:)` returning nil, `image.cgImage == nil`. So
   **run a validation pass over the whole document first** — a decode, not a render, and therefore
   cheap — and if anything cannot be mapped, **refuse the whole resize** and raise a notice naming the
   count and the kinds, in the style `VectorCanvasData.DecodeReport` already established for the load
   path. The mutation pass that follows cannot fail.
3. **Gate the save while a resize is in flight.** `ScenePhaseSaveGate` fires on `active → !active`
   ([`ScenePhaseSaveGate.swift:33-35`](PaintSoftware/Services/ScenePhaseSaveGate.swift)), so an artist
   switching apps mid-resize would otherwise write a document that is half old-size and half new. An
   `isResizing` flag consulted by `ContentView.saveIfNeeded` alongside its existing
   `screen == .editor && canvasSize != nil` guard is the whole of it.
4. **[ARCHITECTURE_REVIEW.md](ARCHITECTURE_REVIEW.md) finding 3's thirty-line remedy is a prerequisite,
   not a nice-to-have.** Give `writeAtomically` a return value and raise the existing `CanvasNotice` on
   failure. The safety net underneath — `stashLiveProjectForSave` moves the pre-resize package into
   `Backups/` before the rename — already exists and already keeps the old document for one rotation;
   what is missing is the artist being told to go and look.

### The coupling to TODO item (8) — fixed-point sample coordinates

Item (8) proposes `bits per axis = ceil(log2(extent)) + 2`, the `+2` buying quarter-pixel placement,
and item (8) itself flags the coupling: *"if the encoding's width is derived from the canvas extent,
resizing the canvas changes the domain."*

**The premise this rests on is not true of the current tree, and that is the load-bearing finding.**
`ceil(log2(extent)) + 2` bounds a coordinate only if stored coordinates lie inside `[0, extent)`. They
do not, for three independent reasons, none of them exotic:

1. **Vector geometry is stored in layer-local space, not canvas space.** `addStroke(canvasSpaceStroke:)`
   maps incoming samples through `_transform.inverted()` and divides `size` by the transform's scale
   ([`VectorLayer.swift:573-585`](PaintSoftware/Engine/VectorLayer.swift)). A layer the artist has
   scaled to 0.1× with the Move tool stores local coordinates **ten times the canvas extent**, by
   construction and correctly.
2. **Touches keep being delivered outside the view they began in.** Nothing clamps a sample to the
   canvas rect; a drag that starts on paper and travels off it records the whole path.
3. **A shrink already leaves geometry outside the canvas as the normal steady state.**
   `setCanvasPadding` shrinking appends a *negative* translation and crops the raster tiers, but leaves
   every vector element exactly where it was. Content outside `[0, extent)` is not an edge case in this
   app; it is what a crop *is*.

So the three options, with their costs:

**(A) Re-encode every sample on resize.** Decode at the old width, apply `M`, re-encode at the new.
*Cost:* the resize becomes O(total samples in the document) — for the owner's intended 300–1000 cels
that is tens of millions of coordinates, and it puts artwork rewriting inside an operation that
otherwise touches no vector sample at all. *Fatal cost:* a downscale **shrinks the domain**, so quarter-
pixel in the new encoding is a whole pixel of the old. Resize down then up no longer round-trips, and
the one property that makes the vector tier worth resizing — exactness — is destroyed by the encoding
that was supposed to save memory. Worse, `stroke.size` is a `CGFloat` and is *not* encoded, so widths
would stay exact while positions quantised: a stroke's dabs would jitter relative to its own width.

**(B) Width fixed per document at creation, stored in the manifest.** A resize re-encodes nothing.
*Cost:* growing the canvas past the stored domain overflows, so a "widen the encoding" migration is
needed — which is option (A), on demand, with worse timing. And two documents at the same canvas size
would carry different encodings depending on their history, a fact nothing on screen explains and
every future reader has to rediscover.

**(C) The encoding is canvas-independent: a format constant, not a document field.** Fixed fractional
precision (the owner's own quarter-pixel rule), and an integer range sized once to the *format's*
domain rather than to any document's extent. *Cost:* a handful of bits per sample more than the
tightest possible packing.

**RECOMMENDATION — (C), and the coupling then dissolves entirely: a resize touches no sample, and item
(8) and item (9) can ship in either order.** **(C) is what shipped, and item (8) is now built**
(2026-08-27, `PackedSampleRun` in `Engine/ShapeGeometry.swift`) — a format constant, not a document
field, exactly as recommended here. One refinement the build added: **the quantisation origin is
written into each stroke's payload** (`"samples": {"o":[cx,cy],"d":"<b64>"}`) rather than implied by
the reader's canvas size, so a decoder needs no context at all and a cel that is never re-saved stays
readable whatever the canvas becomes. The concrete numbers below are superseded; see the correction
that follows the table.

| | today | proposed here (superseded) | TODO item (8), built |
|---|---|---|---|
| `VectorSample.x`, `.y` | `CGFloat`, 64 bits each | 20 bits each, signed, ¼-pixel → ±131,072 pt, sixteen times the app's own 8192 cap (`CanvasSizePickerView.swift:16`) | **16 bits each, signed, ¼-pixel, origin at the canvas centre** → ±8,192 pt |
| `VectorSample.pressure` | `CGFloat`, 64 bits | 8 bits, 0…1 | **8 bits**, 0…1 |
| per sample | **192 bits / 24 bytes** | 48 bits / 6 bytes | **40 bits / 5 bytes** in the field; **7.10 B on the wire** (MEASURED) |

**Correction.** This recommendation sized the field with headroom — 20 bits, ±131,072 pt, "sixteen
times the app's own 8192 cap" — on the ground that reasons 1–3 above need off-canvas margin to degrade
into. The owner's actual ruling carries **no headroom at all**: the field is sized to exactly the
addressable canvas (±8,192 pt, 16 bits centred) and the encoder saturates rather than wraps at that
boundary (TODO.md — *"if you draw outside the 16k, it should not wrap but rather clamp"*). That yields
**4.8× exactly** on the *field*, a bigger win than the 4× here, against the ~5× the ask claims for a
two-coordinate comparison — **and the win on disk, which is the one that matters, is larger still:
MEASURED 2026-08-27, 7.10 bytes a sample on the wire (5 of payload plus base64 and JSON escaping)
against ~77 for a full-precision one, ~11×; `PackedSampleRun`'s own doc comment carries the
provenance.** But the point of recording the difference is not the ratio, it's that the two designs
disagree about what should happen at the edge: headroom degrades gracefully into slop, a zero-headroom
clamp degrades by flattening ink against the boundary. **The off-canvas-headroom argument in reasons
1–3 above is weakened by this, not wrong.** The owner accepted the loss of margin explicitly, and only
at the canvas's own ceiling: a canvas of exactly 16k has no room left for ink that wanders off it,
which the owner accepted on the ground that such a canvas *"will likely never be used for animation"*
(TODO.md). At any ordinary canvas the margin is large — TODO.md's own figure is 8× in x and 16× in y
at 2048×1024. (TODO item (8) also corrects one arithmetic slip in the ask this section already fixed
once — 2048 is 2¹¹, not 2¹⁰ — and the three-`CGFloat` baseline of 192 bits stands unchanged.) The
owner's ruling that a reversible transform decodes to `Double`, works there, and re-encodes at the
bake is unaffected and stays exactly as written; under (C) a canvas resize is simply not one of the
events that re-encodes.

**This was a recommendation, not a decision — it has since been settled and built.** See §6, question 1,
and TODO.md's item (8) for the current number and the rest of its rulings.

---

## 3. Why the rejected alternatives were rejected

**Change `canvasSize` and let the load path rescale.** It already would — `setContents` stretches any
mismatched PNG to the manifest's extent (`RasterLayerTexture.swift:231-247`). It is rejected because
the stretch is non-uniform (the aspect the owner explicitly asked to letterbox is exactly what it
destroys), because it moves the raster tier and not the vector one, and because the document would
look different after a reload than before it — the worst class of bug this codebase can ship, since
the artist's evidence and the developer's disagree.

**Put the scale in `VectorCanvas._transform`.** One line, and it is wrong: `render()` applies
`_transform` to an already-rasterized bitmap, so this is a resample of the vector render dressed as a
vector operation. §2 carries the argument.

**Per-axis scaling (stretch to fill the new extent).** Rejected by the owner's own ask, and
independently by the engine: `mapping(_:throughSimilarity:)` asserts equal axis norms, and
`stroke.size` is a single scalar with no per-axis meaning. Supporting it means a second element mapper,
a second width model, and a new `TextFrame` case. It is the Freeform transform, which
[LASSO_MOVE.md](LASSO_MOVE.md) stage 3 owns and this feature should not pre-empt.

**Snapshot the document for undo.** 12.8 GiB against a 192 MiB budget. §2.

**A per-cel progress bar that lets the artist keep drawing.** The canvas extent is changing under every
buffer; `setCanvasPadding`'s own comment (`:25-27`) explains that even a *pending* shape preview has to
be baked first because it would commit mis-scaled. A resize is modal-busy or it is a race.

**A dirty-tracking resize that skips blank cels' vector tiers.** The raster tier already skips blank
textures for free (`hasContent`, and it allocates nothing). Extending that to a "which cels changed"
model is the shape PERFORMANCE.md §5 settled against for good on 2026-08-21 — *"a dirty check that is
wrong once silently drops artwork"* — and this is a worse place to try it than the save was.

**Refuse a resize that would blow the compositor budget.** Tempting, and rejected as a *silent*
behaviour: `MetalCompositor`'s admission gate already declines quietly (`:505-520`), and a second quiet
refusal on top of it gives the artist a dialog that does nothing. If the size is going to be a problem,
the dialog says so before the artist commits — §6 asks whether it should refuse or merely warn.

---

## 4. Staged delivery

Each stage merges on its own and is usable on the owner's iPad. Follow the multi-session protocol in
[CLAUDE.md](CLAUDE.md); a new *test* file needs a hand-written `project.pbxproj` entry with an id
derived from the file name, plus the duplicate-id check after any rebase touching that file.

**Stage 0 — the save tells you when it failed. ~30 lines, independent, ships alone.**
[ARCHITECTURE_REVIEW.md](ARCHITECTURE_REVIEW.md) finding 3's own "smallest useful remedy": give
`writeAtomically` a return value, thread it through `save`'s `completion`, raise the existing
`CanvasNotice` from `ContentView`. Useful on its own; a prerequisite here because after a resize the
in-memory document is the only copy of the new state.

**Stage 1 — "Resize Canvas" exists, crop/expand only. THE SMALLEST USEFUL SHIPPABLE THING.**
Generalise `setCanvasPadding`'s loop into `resizeCanvas(to:scaleContent:)` with `scaleContent == false`.
Widen the three primitives from `offset: CGPoint` to `placing: CGRect`. New Actions row and a sheet
reusing `CanvasSizePickerView`'s `1...8192` validation. Guides transformed and `copiedCel` cleared —
the two existing omissions in §0. Thumbnails through `startThumbnailBackfill()` instead of
`regenerateAllThumbnails()`, which also fixes `setCanvasPadding` and `flipCanvas`. Still
`history.removeAll()`, still not undoable, still synchronous — **exactly today's contract, with an
arbitrary rectangle instead of a symmetric margin.** The artist can crop and expand their canvas, which
is half the ask, and nothing about the app's behaviour is newly risky. Interpolation lattices and
`LocalEdit` strokes translate, which is trivially the right map at `k == 1`.
*Tests:* the map (`M` at `k == 1` is a whole-point translation; out-and-back is the identity), the
per-tier walk (a document of N layers × M cels has every tier at the new size and no tier missed), the
guide and clipboard fixes, and a round-trip through `ProjectStore` proving the manifest and every
buffer agree.

**Stage 2 — the scale toggle and the letterbox rule. DONE (2026-08-28).**
`CanvasResizeMode` replaces the `scaleContent: Bool` — three cases, one map, no second code path, and
a `Bool` pair could reach a state the model cannot mean. **The vector arm needed nothing**:
`VectorCanvas.resized(to:placing:)` already derives `k` from the placement rect and bakes
`_transform ∘ placement` into every element through `mapping(_:throughSimilarity:)`, returning an
identity-transform canvas — TODO item (12) stage 3's doing, and *stronger* than §2's prescribed
"rewrite the translation only", which this document now keeps as the stated derivation the shipped
primitive is pinned against. The raster arm needed nothing either: stage 1's `placing:` rect and its
conditional `.high` are the whole of it. What stage 2 actually built is the mode, the artwork-ratio
correction above, `InterpolationRecipe.mapped(through:)` (lattices through `M` with
`restCellSize *= k`, `LocalEdit` strokes through the same `mapping` **once, in rest space**), the
inverse's mode flip, and the dialog: a Scale toggle, a Fit/Fill picker shown only when the aspect
actually changes, the floor sentence, and §5 rule 14's compositor warning. Still not undoable.
*Tests:* `CanvasResizeLogicTests`, 31 tests — §2's two identities on the real types (the second over
its own 324-case grid), the letterbox invariant and its Fill dual, the round trip at `k = 0.25`/`4`
*and* at `0.625`/`1.6` where the mode flip is load-bearing, the floor boundary through the dab walk
plus the survey the dialog asks, the artwork-ratio correction, the Fill asymmetry, and the compositor
gate's two thresholds.
*Owed before merge:* **measured** — see §2's table above.

**Stage 3 — undoable, off-main, and a busy state.**
The validation pass; `isResizing` and the save gate; the `GalleryOpenState`-shaped busy modal with
`await Task.yield()`; bounded raster concurrency; the cache purge; the `resizeCanvas`
`HistoryActionLabel` case and the single inverse-resize undo step; the `CanvasNotice` when a raster
tier was resampled. This is the stage that makes the feature usable on a 300–1000-cel document, and it
is the stage whose undo cost must be measured rather than asserted.

**Stage 4 — deferred polish, independent small branches.**
A preset list (1080p, 2048×1024, square) beside the free-form fields. Anchor choice for crop/expand
(nine-way, instead of always centred) — a real feature, not a constant, and the ask does not call for
it. Writing the pre-resize raster PNGs to a scratch directory so undo can restore them exactly rather
than approximately, which interacts with the save's atomicity and is its own design. Mirroring vector
content in `flipCanvas`, which stage 1 and 2 make trivial by giving that function the same per-element
mapper.

---

## 5. Behaviour, decided

1. **Two modes, one toggle.** *Crop / Expand* keeps the artwork at its own size; *Scale artwork* scales
   it with the canvas. One switch, defaulting to Crop / Expand, because that is the non-destructive one.
2. **On an aspect change, the artist picks Fit or Fill — never stretch, never bar, in either arm.**
   *Fit* — `k = min(Nw/Ow, Nh/Oh)`, the default — lands the whole drawing inside the new extent; the
   leftover is empty canvas at the document's own background colour, never a painted band. *Fill* —
   `k = max(Nw/Ow, Nh/Oh)` — covers the new extent and lets the overflow hang off the edges. Both are
   the one map `M` from §2 with a different choice of ratio, and `mapping(_:throughSimilarity:)`
   accepts either unchanged, since Fill is still a single uniform scale. The ask was fit only; **Fill
   is the addition the owner accepted, 2026-08-28** (§6 Q4). The choice is offered only when the
   aspect actually changes: at an unchanged aspect `min` and `max` are the same number and the picker
   would be a control that does nothing. **And Fit's inverse is Fill, not Fit** — §2.
3. **Content is centred, in both modes.** Matching `setCanvasPadding`'s existing placement.
4. **Crop/expand offsets round to whole canvas points; scale offsets do not.** Crop/expand must never
   resample; under scale the two tiers must agree with each other more than they must land on a
   pixel boundary.
5. **One map `M`, computed once, applied to every tier.** Not a draw rect here and a factor there.
6. **Vector scales by mapping the elements, never by folding the scale into `_transform`.**
7. **All four content tiers move, on every cel of every layer, plus document-level guides.** No
   partial application, no "active cel only", no deferral of off-screen cels.
8. **Transient state is baked and then discarded**, exactly as `setCanvasPadding` does: interactive
   fill, shape, text, both float kinds, the shape preview texture, and the selection. The timeline
   clipboard is cleared.
9. **`canvasPadding` is preserved literally, in canvas points, and never scales.** It is a working
   margin the artist set with a separate control, not artwork; scaling it would make two controls fight
   over one number. The width and height the artist types therefore mean the **artwork rect**, and the
   buffer extent becomes `typed + 2 × canvasPadding`. **Confirmed by the owner, 2026-08-28** (§6 Q3).
   Under scale this is also what makes `k` an *artwork* ratio rather than a buffer one — §2 — with the
   one consequence that ink drawn out in the old margin can overflow even under Fit.
10. **The history stack is cleared, then the resize is recorded as one step.** Depth 1 afterwards.
    Undo runs the inverse resize; it restores geometry exactly and raster pixels approximately, and the
    app says so when the resize happens rather than when undo is pressed.
11. **A resize that cannot map some element refuses entirely**, naming the count and the kinds. Never
    a partial resize.
12. **No disk write happens during a resize, and no save may start during one.**
13. **The dab-spacing floor, the dab-diameter floor and pencil grain are inherited, knowingly.** The
    dialog says once that brush texture re-stamps at the new size; nothing in the engine changes.
    **Shipped in stage 2** as `SpacingFloorSurvey`: one walk when the sheet opens collecting
    `size × spacingFraction` per stroke, and a binary search per keystroke, because a stroke crosses at
    factor `k` exactly when its threshold lies in `[min(1, 1/k), max(1, 1/k))`. The sentence is
    conditional on this document actually having such a stroke, not shown whenever scaling.
14. **A resize that would push the document past the compositor's admission gate warns and lets the
    artist proceed — it never refuses and there is nothing to fall back silently from.** The warning
    has two halves (§6 Q5). The live canvas itself never reaches the gate: past it, the canvas
    composites at reduced resolution instead, softer rather than slower. But the eyedropper's colour
    pick does reach it and falls to the CPU reference for that one pick; the live-mask preview on a
    masked layer runs on the CPU reference unconditionally, gate or no gate, so it only gets slower as
    the canvas grows. Export and the project thumbnail are unaffected at any canvas size.
    **Shipped in stage 2, not stage 3**, because the warning is a property of the dialog rather than of
    undo: `CompositorSizeGate` holds the two texture counts the live tree gives
    (`peakCompositeTextures` for the eyedropper's native-size request, plus `uploadableLeafCount` for
    the sandwich's) and asks `CompositorBudget.affordableSize` at the typed extent. Two counts because
    the two thresholds are genuinely different — at 4096×2048 on the owner's iPad 9 the canvas softens
    while the eyedropper still fits.

---

## 6. Open questions for the owner

1. **The fixed-point encoding (TODO item 8). ANSWERED — (C), as recommended, but not at the width
   proposed here — and BUILT, 2026-08-27.** §2 recommends **(C)**: the coordinate width is a property
   of the *format* — this section proposed 20 signed bits per axis at quarter-pixel, ±131,072 pt, 4×
   smaller than today's three `CGFloat` — rather than derived from the canvas extent. The reason is that stored coordinates
   already leave `[0, extent)` routinely (layer-local space, off-canvas drags, and every shrink), so
   the extent was never a bound on the data. Under (C) a resize re-encodes nothing and the two items
   are independent. The owner confirmed (C) but settled narrower: TODO item (8) is **16 signed bits per
   axis, ¼-pixel, origin at the canvas centre — ±8,192 pt**, once TODO item (12) removed the layer-local
   reason and the owner ruled the encoder should saturate rather than carry headroom. **As built, each
   payload carries the origin it was quantised about**, so a decoder needs no canvas context and this
   question cannot be re-opened by a resize: the sample tier is genuinely out of §2's way. See §2's
   correction and TODO.md's item (8) for the number and the rest of its rulings.

2. **Undo of a resize with raster content. ANSWERED — (a), 2026-08-28: undo it anyway, and say so.**
   Vector geometry returns exactly; raster pixels return as a resample after a downscale, and the app
   announces that at the moment the resize happens, not at the moment undo is pressed (§5 rule 10). The
   owner's own reason for picking it: strictly better than today, where Canvas Padding has no undo at
   all. (b) keeping the operation non-undoable like `flipCanvas`, and (c) stage 4's exact
   scratch-directory version, were the alternatives declined. This bites nobody today: the packages
   measured on the iPad have no raster content at all.

3. **What does the width/height field mean — the artwork rect, or the padded buffer? ANSWERED — the
   artwork rect, exactly as §5 rule 9 recommended, 2026-08-28.** `canvasPadding` is preserved literally
   and never scales; the buffer extent is `typed + 2 × canvasPadding`. The alternative — the typed
   number is the buffer, and padding eats into it — was rejected because it would make the two Actions
   controls interact in a way neither of them shows.

4. **Fit only, or fit *and* fill? ANSWERED — both, as a choice, 2026-08-28. Fit stays the default.**
   Fill (`max` instead of `min`) covers the new extent and lets the overflow hang off the edges. It is
   not the data-loss operation the "crop the overflow" framing above suggested: the vector tier keeps
   the overflowing elements exactly as it already keeps any off-canvas element (§6 Q1), and only the
   raster tiers are cropped, destructively, because a raster tier is a buffer of exactly the canvas
   extent (§2, "the vector/raster asymmetry"). Not a rule 11 refusal case — nothing is unmappable. §5
   rule 2.

5. **The compositor's admission gate on a resize that grows the canvas. ANSWERED — warn, and let the
   artist proceed, 2026-08-28.** This question's own premise — that the gate "declines silently and
   drops the whole texture cache process-wide" — is not what a resize does to the live canvas, and the
   correction matters more than the choice.

   **The gate is about memory, not speed.** `MetalCompositor.attempt` refuses before it allocates
   anything (`MetalCompositor.swift:516-525`) because `Metal.makeTexture` does not return nil under
   this pressure — jetsam kills the process first (`:505-506`; `RenderTree.swift:522-531` makes the
   same point independently). "Just take longer" was never one of the options at the point the guard
   sits: the alternative to refusing is the app dying.

   **The budget is `physicalMemory / 16`, clamped to `[64 MiB, 768 MiB]`** (`Compositor.swift:167-171`)
   — 192 MiB on the owner's 3 GB iPad 9, 512 MiB on an 8 GB iPad Pro, the 768 MiB cap above 12 GB. It is
   checked against `peakCompositeTextures × canvasBytes` (`RenderTree.swift:542`), so the size a
   document tips over at depends on its **layer and effect structure**, not on the canvas alone.

   **On the live canvas the gate never fires, and there is no CPU fallback.** `makeSandwichRequests`
   sizes its request through `CompositorBudget.affordableSize` before `attempt` ever sees it
   (`RenderRequest.swift:697-701`; the scaling itself is `Compositor.swift:221-246`, `sqrt(budget /
   wanted)`). An over-large document therefore stays on the GPU and composites **fewer pixels** — the
   canvas gets *softer*, not slower, on an image the artist is already told is a preview
   (`RenderResolution`). The thing that actually purges the whole cache, `purgeLocked()`, belongs to a
   *different*, dynamic gate (`os_proc_available_memory()` pressure, `:530-538`) that reacts to the OS
   rather than to canvas size; the static, size-based refusal a resize can cause just declines that one
   composite (`:516-525`) and purges nothing.

   **Export is unaffected — but that is only half the answer, and it is not the half that matters
   most.** The app has no separate export feature; the only full-document composite on the save path is
   the manifest thumbnail (`ProjectStore.swift:270-294`), and since `2f4b737` (2026-08-20, "Composite
   the gallery tile at the tile's size, not the whole canvas") it is bounded to a 320×320 box
   (`fittingWithin: Self.thumbnailBounds`) that routes through the same `renderSize(fitting:within:)` →
   `CompositorBudget.affordableSize` pipeline as the live canvas (`RenderRequest.swift:527-545`). At
   that bound the composite can never approach even the 64 MiB budget floor, on any canvas size —
   saving and thumbnailing are unaffected by this gate regardless of how large the canvas grows. The
   native-size arm is not empty, though; it just is not the thumbnail any more.

   **Two ordinary, in-session gestures live on that native-size arm, and they reach it by two different
   routes.** `makeRenderRequest`'s own doc comment says so directly (`RenderRequest.swift:522-524`):
   passing no `fittingWithin` bound is what makes the eyedropper, the live-mask resolve and every parity
   test composite at native size, "an identity that `affordableSize` does not promise." The eyedropper
   (`CanvasManager+Eyedropper.swift:47-52`) is uncapped on purpose — a reduced composite would blend
   neighbouring pixels into the sampled colour, and a wrong colour looks exactly like a right one — and
   its request runs through `Compositor.composite`, so on a document over the gate it genuinely falls
   back to `CoreGraphicsCompositor` for that one pick (`Compositor.swift:365-366`). **The live-mask
   preview (`CanvasView.swift:1367`, `resolveLiveMask`) does not go through the gate at all, in either
   direction.** `MaskResolver.coverage` calls `CoreGraphicsCompositor.composite` directly and
   unconditionally, once per mask source (`MaskResolver.swift:9-14`, `:180-181` — "Always the CPU
   reference, whichever backend asked"), which is a parity decision and not a fallback, so it never
   touches `MetalCompositor` and cannot "reach" this gate the way the eyedropper does. Its cost still
   grows with native canvas size on every stroke begun on a masked layer; it simply pays that cost
   always, gate or no gate, rather than only once the document is over it.

   **Either way, this is where the 7047 ms vs 18.8 ms figure actually bites, during an interactive
   gesture rather than offline** — though the figure needs its own scope stated rather than borrowed
   whole. It is for a single-pass grade over 4.2M pixels, Debug
   (`PerfBaselineTests.testEffectCompositeCostOnBothBackends`, quoted at `Compositor.swift:207-208`),
   i.e. the cost of a document with a grading layer in the tree, not of a plain stack — a plain stack's
   CPU/GPU gap is the much smaller per-layer-slope and fixed-intercept pair in `Compositor.swift`'s own
   table, above. A document large or effect-heavy enough to sit over the gate pays the large figure on
   every eyedropper tap that reaches the fallback; the live-mask preview sits somewhere on that same
   curve on every stroke begun on a masked layer, scaled by canvas size and by how many sources the
   mask has.

   **Three in-source comments carried the stale claim, corrected in place rather than only here.**
   `MetalCompositor.swift:518-523` and `RenderTree.swift:529-531` each named `ProjectStore`'s thumbnail
   as the consumer that reaches this gate at native size; both now name the eyedropper instead, which is
   the one that actually does. `MetalCompositor.swift:563-566` made the same size claim in passing, for
   an unrelated point about the upload cache holding two composite sizes per session; it now states the
   thumbnail's true, `affordableSize`-bounded size rather than repeating "native." All three were true
   when written (`ca1680b`, 2026-08-16) and stopped being true four days later when `2f4b737` bounded the
   thumbnail's composite; none were updated to match. This document's own §1 row and §2 "Memory and
   time" section carried the same stale claim and are corrected alongside this answer.

   **The dialog's warning therefore has two halves.** Past a size that depends on this document's layer
   stack: the canvas itself composites at reduced resolution and looks softer while you work — not
   "falls back to CPU," which is not what the artist experiences on the canvas. And picking a colour, or
   beginning a stroke on a masked layer, can pay the CPU reference's cost for that one composite — which
   is where "falls back to CPU" is actually true, just not on the canvas itself. Saving and exporting
   pay neither cost. §5 rule 14.
