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
tier. §2 is the decisions. §4 stages it. §5 is the settled rulings. §6 is what needs the owner.

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

**This is almost certainly what the owner's freeze report (6) means by *"try to resize the canvas"*** —
it is the only control in the Actions menu that changes the canvas extent. Two properties of the code
above are worth holding next to that report, neither of which proves anything on its own: the loop is
**synchronous on the main actor over every cel in the document**, and it ends in
`regenerateAllThumbnails()`, whose own doc comment (`CanvasManager.swift:1519-1522`) names *"canvas
resize"* as one of its two callers and states that it is *deliberately not debounced*. Each thumbnail
is a full `PixelOps.rasterize` of the cel. On the 1–4-cel documents actually on the owner's iPad
(PERFORMANCE.md item 14, read off the device) that is imperceptible; on the 300–1000-cel document the
owner intends it is a multi-second main-thread block with no spinner. **That is a hypothesis, not a
finding** — the sequence in report (6) also involves the text keyboard, and §4's stage 1 fixes the
block regardless of whether it was ever the cause.

### The three resize primitives, and what each can and cannot do

| primitive | file:line | what it does | scales? |
|---|---|---|---|
| `RasterLayerTexture.resized(to:offset:)` | [`RasterLayerTexture.swift:372`](PaintSoftware/Engine/RasterLayerTexture.swift) | `current.draw(in: CGRect(origin: offset, size: size))` into a `newSize` renderer. A blank texture stays blank and allocates nothing. | **no** — the draw rect is the *old* size |
| `PixelOps.resizedCanvasImage(_:to:offset:)` | [`PixelOps.swift:408`](PaintSoftware/Services/PixelOps.swift) | the same, for `fillImage`/`bakedImage` | **no** |
| `VectorCanvas.resized(to:offset:)` | [`VectorLayer.swift:431`](PaintSoftware/Engine/VectorLayer.swift) | appends a translation to the canvas-level `_transform`; touches no element. Lossless. | **no** |

All three take a `CGPoint` offset and draw at the source's own size. Widening that one parameter from
a point to a **destination rectangle** is the whole of the raster side of the scale mode — see §2.

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
| `Cel.vector` elements | `VectorLayer.swift:244` | nothing (the canvas `_transform` carries it) | `mapping(_:throughSimilarity:)` per element — **exact** |
| `VectorCanvas._transform` | `VectorLayer.swift:245` | append the translation (today's `resized`) | rewrite the translation only — see §2 |
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
| compositor admission | `MetalCompositor.swift:505-520` | — | **re-checked implicitly.** Growing the canvas raises `peakCompositeTextures × w·h·4` against `CompositorBudget.textureBudgetBytes`, and the refusal is silent — see §6 |

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
k  = scaleContent ? min(Nw/Ow, Nh/Oh) : 1          // the letterbox factor
Cw = k·Ow ,  Ch = k·Oh                             // the content rect in the new canvas
dx = (Nw − Cw)/2 ,  dy = (Nh − Ch)/2               // centred
if !scaleContent { dx = dx.rounded() ; dy = dy.rounded() }
M  = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: k, y: k)
```

`M` maps a point `p` in the old canvas to `k·p + d` in the new one. MEASURED (scratch `swiftc`,
2026-08-27): the matrix form and the hand form agree to `< 1e-12`, and the `.scaledBy` spelling is the
one that means *scale first, then translate* — the other order is wrong and reads identically.

**Why `min` and not `max`.** `min` fits the content inside the new extent, leaving genuine empty
canvas on the axis that did not bind. That is the owner's *"just scaling the stuff so it fits"*, and
the leftover is real paper — `canvasBackgroundColor` — not a painted bar. `max` would cover the new
extent and crop the overflow; it is a different feature and §6 asks whether it is wanted.

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

Two consequences, both settled in §5:

1. **The undo of a resize restores the geometry exactly and the pixels approximately**, and the
   operation says so at the moment it happens rather than at the moment the artist presses undo.
2. **The operation can tell which case it is in, up front, and for free.** A document where every cel
   reports `raster.hasContent == false` with `fillImage == nil` and `bakedImage == nil` has an exactly
   invertible resize. That is not a corner case: it is what the owner's real packages measure as
   (PERFORMANCE.md item 14 — three cels on the device's largest live project, all with a fully
   transparent raster tier, all now omitted from the save entirely).

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

The budget is 192 MiB and an over-budget composite is declined *silently*, dropping the whole cache
process-wide. The arithmetic that matters, all **INFERRED** from `w·h·4`:

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

**What is not measured, and must be before stage 2 ships:** the wall-clock cost of one cel's raster
resize. `setCanvasPadding` performs exactly this operation today and nobody has ever timed it. The
neighbouring figures — 15.2 ms/cel for the save's PNG encode, 8.0 MiB INFERRED for the load path's
full-canvas draw — bracket it but do not give it.

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
(8) and item (9) can ship in either order.** The concrete shape, if it helps the ruling:

| | today | proposed |
|---|---|---|
| `VectorSample.x`, `.y` | `CGFloat`, 64 bits each | **20 bits each, signed, ¼-pixel** → ±131,072 pt, sixteen times the app's own 8192 cap (`CanvasSizePickerView.swift:16`), which is the off-canvas headroom reasons 1–3 above require |
| `VectorSample.pressure` | `CGFloat`, 64 bits | **8 bits**, 0…1 |
| per sample | **192 bits / 24 bytes** | **48 bits / 6 bytes** |

That is **4× exactly**, against the ~5× the ask claims for a two-coordinate comparison, and it is the
honest number for the three-component struct this app actually stores. (TODO item (8) already corrects
one arithmetic slip in the ask — 2048 is 2¹¹, not 2¹⁰ — and this is the second: `VectorSample` is
three `CGFloat`, so the baseline is 192 bits, not 128.) The owner's ruling that a reversible transform
decodes to `Double`, works there, and re-encodes at the bake is unaffected and stays exactly as
written; under (C) a canvas resize is simply not one of the events that re-encodes.

**This is a recommendation, not a decision.** It is §6's first question.

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

**Stage 2 — the scale toggle and the letterbox rule.**
`scaleContent == true`. Raster through the widened `placing:` rect at `.high` interpolation; vector
through `mapping(_:throughSimilarity:)` per element plus the `_transform` translation rewrite from §2;
lattices through `M` with `restCellSize *= k`, and `LocalEdit` strokes through the same `mapping`
**once, in rest space, not again in canvas space**. Guides through `M`. The dialog's floor sentence.
Still not undoable.
*Tests:* the two `swiftc`-verified identities in §2 as XCTest assertions on real types; the letterbox
invariant (content fits, exactly one axis has slack, slack is split evenly); a vector round-trip at
`k = 0.25` then `k = 4` asserting samples return to within 1e-9; and the floor boundary, which
`LassoMoveLogicTests` already knows how to state.
*Owed before merge:* the wall-clock of one cel's raster resize, which has never been measured.

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
2. **On an aspect change, fit — never stretch, never bar.** `k = min(Nw/Ow, Nh/Oh)`. The leftover is
   empty canvas at the document's own background colour, not a painted band. This is the owner's ask
   and independently the only shape `mapping(_:throughSimilarity:)` accepts.
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
   buffer extent becomes `typed + 2 × canvasPadding`. (§6 asks the owner to confirm this reading.)
10. **The history stack is cleared, then the resize is recorded as one step.** Depth 1 afterwards.
    Undo runs the inverse resize; it restores geometry exactly and raster pixels approximately, and the
    app says so when the resize happens rather than when undo is pressed.
11. **A resize that cannot map some element refuses entirely**, naming the count and the kinds. Never
    a partial resize.
12. **No disk write happens during a resize, and no save may start during one.**
13. **The dab-spacing floor, the dab-diameter floor and pencil grain are inherited, knowingly.** The
    dialog says once that brush texture re-stamps at the new size; nothing in the engine changes.

---

## 6. Open questions for the owner

1. **The fixed-point encoding (TODO item 8).** §2 recommends **(C)**: the coordinate width is a
   property of the *format* — 20 signed bits per axis at quarter-pixel, ±131,072 pt, 4× smaller than
   today's three `CGFloat` — rather than derived from the canvas extent. The reason is that stored
   coordinates already leave `[0, extent)` routinely (layer-local space, off-canvas drags, and every
   shrink), so the extent was never a bound on the data. Under (C) a resize re-encodes nothing and the
   two items are independent. **Confirm, or rule for (A) re-encode-on-resize / (B) width-per-document,
   both of which make the resize lossy for vector.**

2. **Undo of a resize with raster content.** Vector is exactly invertible; raster is not — a downscale
   discards pixels and the undo restores a resample. Options: (a) undo it anyway and say so in a banner
   — the recommendation, and strictly better than today's no-undo; (b) keep whole-document geometry ops
   non-undoable as `flipCanvas` is, and clear the stack; (c) stage 4's scratch-directory version, which
   is exact but is its own design. Note this bites nobody today: the packages measured on the iPad have
   no raster content at all.

3. **What does the width/height field mean — the artwork rect, or the padded buffer?** §5 rule 9
   recommends the artwork rect, with padding preserved literally and never scaled. The alternative is
   that the typed number is the buffer and padding eats into it, which makes the two Actions controls
   interact in a way neither of them shows.

4. **Fit only, or fit *and* fill?** The ask says fit. Fill (`max` instead of `min`, cover the new
   extent and crop the overflow) is the other thing artists reach for on an aspect change, and it is
   one line. Worth having, or is one behaviour clearer than two?

5. **A resize can grow a document past the compositor's admission gate, which declines silently and
   drops the whole texture cache process-wide** (`MetalCompositor.swift:505-520`; the budget itself is
   ruled off-limits by PERFORMANCE.md §5). Should the dialog refuse a size that would, warn and let the
   artist proceed, or say nothing and let the app fall back to the CPU compositor?
