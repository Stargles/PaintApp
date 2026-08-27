<!-- Written 2026-08-27 to settle the owner's ruling of the same day: that a vector layer should not
have a transform of its own, and that shrinking a layer should shrink its objects' canvas
coordinates instead. Read-only pass over `main` at f44a2e9 — nothing here was built, and no test was
run. Figures are labelled MEASURED (from a scratch `swiftc` run, or from a number already in this
repo with its citation) or INFERRED (read off the source, not observed on the device). -->

# The layer transform — keep it, or bake it into the geometry?

**Verdict: adopt, with changes.** The ruling is right, and it is right for a reason that has nothing
to do with saving two bytes a sample. `VectorCanvas._transform` is an indirection that **eleven of
its sixteen entry points invert away again before they can do anything**, and the five that read it
forward include one whose only job is to hand it back to the box that wrote it. It also carries three
defects that are properties of the indirection itself and cannot be fixed while it stands — one of
which silently discards ink the artist just drew.

The changes are: **the bit width is not the justification and must not be promised** (§6 — the honest
answer is that TODO item (8)'s already-settled 24 bits stays 24 bits), and **deleting the field is a
separate, optional decision that should be taken after the baking lands, not with it** (§7).

---

## 0. The ruling, and what this document is answering

> *"oh, I'm not sure why layers themselves should ever be able to be shrunk. Only the objects in them
> should be. Every object in the vector layer should be given coordinates according to the canvas, and
> if the entire layer is 'shrunk', then those coordinates of the objects should shrink, not the entire
> layer itself being transformed."* — the owner, 2026-08-27

Restated as a storage rule: **a `VectorCanvas`'s display list is in canvas coordinates, and the only
way content moves is that its own numbers change.** No affine sits between storage and the canvas.

Three corrections to the brief that produced this pass, stated first because two of them change what
the answer is worth:

1. **It is a *cel* transform, not a layer transform**, and the codebase already knows this — see §4.
   Every name in the app says "layer" and the storage says "cel". The load-bearing consequence is that
   baking rewrites **one drawing, not the animation**.
2. **TODO item (8) is not open.** It was decided on 2026-08-27 (commit `f44a2e9`, TODO.md:69-84):
   **fixed width, 24 signed bits an axis at quarter-pixel.** The owner's 15-bit arithmetic was already
   overtaken, and it was overtaken by CANVAS_RESIZE.md §2's finding that **the layer transform is only
   one of three independent reasons a stored coordinate leaves `[0, extent)`**. Adopting this ruling
   removes one of the three. It does not restore 15 bits, and it does not change the 24.
3. **`ImageRef`'s synthesized `Codable` does not "break every existing document."** ADD_TEXT stage 2's
   per-element decode (`VectorCanvasData.LossySlot`, `VectorLayer.swift:2810-2830`) contains a failed
   element to *that element*. A new non-optional field on `ImageRef` would therefore **silently drop
   every placed image from every existing document, count it in `DecodeReport.malformedCount`, and
   write the loss to disk on the next save** — narrower in blast radius and worse in kind than a
   refused document. It does not arise under this design anyway (§3), but the correction matters
   because "it breaks loudly" is the wrong thing to plan against.

---

## 1. What `_transform` actually buys today

`VectorCanvas` is *"the vector content of one cel"* (`VectorLayer.swift:227`). `_transform` is
declared at `:246`, accessed through `transform` at `:353-356`, and its doc says what it is for:
*"Move/rotate/scale of the entire layer's content, applied at render time so it stays crisp"*
(`:351`).

### 1a. The census — every read and every write

Twenty-two sites in the app, all but two of them inside `VectorLayer.swift`.

**The five forward reads — the only places the transform does work:**

| site | what it does |
|---|---|
| `render()` step 2, `VectorLayer.swift:2348-2356` | concatenates `_transform` and draws the **already-rasterized** local content through it |
| `renderIsolated(ids:)`, `:2400-2406` | the same arm again, for a lasso float's own picture |
| `layerTransform(pivot:)`, `:866-871` | decomposes the affine into `LayerTransform` **for the Move box that wrote it** |
| `canvasText(fromLocal:)`, `:809-813` | maps a stored text frame back out so the editor can be opened on it |
| `cutPreviewEdits`' `canvasSamples`, `:1964`, `:1975` | maps stored geometry back to canvas space to re-stamp into the eraser's scratch raster. Its own doc: *"Only `cutPreviewPieces` needs this; every other caller is going the other way."* |

**The eleven entry points that invert it away before storing or testing anything:**

| entry point | line | inverts at |
|---|---|---|
| `addStroke(canvasSpaceStroke:)` | `:575` | `:579` (samples), `:582` (width ÷ scale) |
| `localSamples(fromCanvas:)` | `:598` | `:601` — **dead: zero callers in the app and zero in the tests** |
| `addImage(canvasSpaceElement:canvasPosition:canvasFit:)` | `:670` | `:673`, `:676` (position, scale, and the cascade step) |
| `localText(fromCanvas:)` | `:803` | `:806` |
| `addFill(canvasSpacePath:…)` | `:834` | `:837` |
| `localPath(fromCanvas:)` | `:845` | `:848` |
| `erase(alongPath:…)` | `:958` | `:967`, `:968` |
| `cutToIntersection(atCanvasPoint:…)` | `:1017` | `:1025`, `:1026` |
| `cutPreviewEdits(alongPath:…)` | `:1891` | `:1898`, `:1899` |
| `topmostText(atCanvasPoint:)` | `:2272` | `:2277-2279` (point **and** the fingertip slop) |
| `splitForLassoMove(insideLocalPath:)` | `:1427` | not itself — its **name** records that its caller already did it, through `localPath(fromCanvas:)` |

**The remaining plumbing:** `init` `:402`, `makeCopy()` `:425`, `resized(to:offset:)` `:434`,
`setTransform(_:)` `:852-857`, `transformScale` `:590` (**one caller in the whole repo, and it is a
test**: `BrushEngineLogicTests.swift:537`), and the persistence triple
`VectorCanvasData` `:2891` / `:2908` / `:2941-2943`.

Outside `VectorLayer.swift` there are exactly two readers of the value:
`CanvasManager.setVectorTransform` / `closeVectorTransformBracket` (`CanvasManager.swift:335-400`) and
`CanvasView.Coordinator`'s two calls into the Core Animation latch (`:1672`, `:1702`).

**That is the owner's argument, counted.** Eleven inversions against five forward reads; of the five,
one is a round trip to the writer, one exists for a single eraser preview, and the two that matter
(`render` and `renderIsolated`) apply the affine to a *bitmap*, which §2 shows is where the defects
come from.

### 1b. Per feature — does it need a layer transform, or a way to map a gesture into storage?

| feature | reads `_transform`? | needs a *layer* transform? |
|---|---|---|
| **Whole-cel Move** (`isVectorTransforming`) | yes — it is the only writer, `CanvasManager.swift:352` | **No.** It needs a way to move content. It writes the affine because that was the cheap way to do it in 2026-08. The undo bracket restores an affine (`:367-372`), which is the one thing that is genuinely simpler today. |
| **Lasso float** | reads it as `baseTransform` (`CanvasManager+LassoMove.swift:185`) and divides it back out of every nudge (`:249-251`) | **No — and it already proves the ruling works.** A nudge maps element geometry through `VectorCanvas.mapping(_:throughSimilarity:)` and writes it back. It is precisely "the objects' coordinates change", shipped, tested, and exact to 1.3e-13 pt (`VectorLayer.swift:1585`). It reads `baseTransform` only to cancel it. |
| **Interpolation** | **no — it drops it on the floor.** `interpolationContentProvider` returns `.vector?.elements` raw (`CanvasManager+Interpolation.swift:577`), and `InterpolationEvaluator.render` takes `content` + `size` and no affine (`:1247-1250`) | No. See §2 defect C: this is a live correctness bug caused by the transform's existence. |
| **Onion skin, gallery thumbnails, export, flatten, merge** | indirectly, via `PixelOps.rasterize(cel:)` → `cel.vector?.render()` (`PixelOps.swift:276`) | **No.** They ask for a picture. Identity costs them nothing; `render()` already branches on `_transform.isIdentity` and skips the pass. |
| **Interactive fill's reference composite** | indirectly, `CanvasManager+Fill.swift:848` | No, same reason. The fill's own path goes in through `addFill(canvasSpacePath:)`, which inverts. |
| **Vector eraser (all three modes)** | via `erase`, `cutToIntersection`, `eraseHybrid`, `cutPreviewEdits` | **No.** Every one of them inverts a canvas-space gesture into storage on the way in, and the preview maps back out. Identity deletes eight lines. |
| **Fills** | via `addFill(canvasSpacePath:)`, `localPath(fromCanvas:)` | No. |
| **Placed images** | via `addImage(canvasSpaceElement:)` | No — but the *element* keeps its own pose. §5. |
| **Text** | via `localText`/`canvasText`/`topmostText` | No — but the *frame* keeps its four corners. §5. |
| **Canvas padding** (`setCanvasPadding`) | writes it, via `resized(to:offset:)` `:434` | **No.** It appends a pure translation. Translating stored geometry is exact and is what the raster tiers already do. |

---

## 2. What breaks if it is removed, in order of severity

### The three defects removal *fixes*, first — because they are the case

All three are INFERRED from source. None is in [BUGS.md](BUGS.md). Each has a repro the owner can run
in under a minute, and stage 1 (§7) should not be started until at least defect A is confirmed.

**A. Drawing on a scaled-down cel silently loses ink.** `renderLocalContent` rasterizes into a context
of exactly `size` — `UIGraphicsImageRenderer(size: size, format: format)`, `VectorLayer.swift:2450` —
in **local** space, and `render()` applies `_transform` to that finished bitmap afterwards. So local
geometry outside `[0, size]` is **clipped before the transform is ever applied**. But
`addStroke(canvasSpaceStroke:)` stores `canvasPoint · _transform⁻¹`: on a cel scaled to *k*, the
visible canvas maps to a local rect `1/k` times the extent. At *k* = 0.5, three quarters of the canvas
stores local coordinates the renderer will crop. At the floor, *k* = 0.02
(`ObjectTransformFrame.swift:260`), 99.96% of it does.
*Repro:* vector layer, Move with no selection, drag a corner in to about half size, tap away, draw a
line across the whole canvas. Expected under this reading: only the part of the line in the top-left
quadrant survives.

**B. Scaling a cel up is a bitmap magnification, and the doc comment says the opposite.**
`setVectorTransform`'s own doc claims it applies the transform *"losslessly (the geometry is
re-rasterized at the new transform, no resolution loss)"* (`CanvasManager.swift:329-331`). It is not
re-rasterized at the new transform; step 1 stamps at canvas resolution in local space and step 2
magnifies the result. CANVAS_RESIZE.md §2 already states the general fact and states it correctly:
*"a scale folded into `_transform` … is a **bitmap resample of the vector render** … Every reason the
vector tier exists is lost in one line, invisibly, and the result still looks right at a glance."*
That paragraph was written about a canvas resize; it is equally true of the Move box, and nobody
joined the two. **Two doc comments in this tree contradict each other and the wrong one is the one a
reader of the Move path will meet.**

**C. Interpolation ignores the transform entirely.** The content provider hands the evaluator the raw
local display list (`CanvasManager+Interpolation.swift:577`) and the evaluator takes no affine
(`:1247-1250`). Two keyframes whose cels carry different transforms are therefore registered and
blended in two different coordinate frames, and the in-between is drawn in neither. `registrationFrame`
and the ARAP lattice are all built from `registrationPoints(of:)` (`:1212`), which reads
`stroke.samples` and `image.transform.position` — local, every one.
*Repro:* two keyframes, Move the second one's cel bodily to the right, scrub the in-between. Expected
under this reading: the in-between shows the drawing un-moved, and it snaps at the keyframe.

Under the ruling all three stop existing, because there is no local space for content to be clipped
in, no bitmap to magnify, and nothing for the evaluator to be blind to.

**And the obvious cheaper fix does not work.** The natural objection to this whole document is that A
and B are bugs in `render()`: give step 1 a context sized to `localContentBounds()` instead of to the
canvas and the clipping goes away. It does not survive contact — it fixes A and *not* B (still a
resample), fixes nothing about C, and it makes the allocation unbounded: at *k* = 0.02 on an 8192
canvas the local content bounds are 409,600 pt across, which is 1.7×10¹¹ pixels. The clipping is load-
bearing; it is what keeps `render()` from allocating the sky. That is the real signal that the local
space is wrong, not that the renderer is.

### What actually breaks, ranked

1. **The persisted format.** `VectorCanvasData.transform` is `[a, b, c, d, tx, ty]`
   (`VectorLayer.swift:2761`), written at `:2891-2892`, read at `:2941-2943`, and handed to the
   initializer at `ProjectStore.swift:1144`. **Every existing document on the owner's iPad that has
   ever used the Canvas Padding slider carries a non-identity entry on every cel of every layer**,
   because `setCanvasPadding` runs `vector.resized(to:offset:)` over the whole document
   (`CanvasManager+Document.swift:45`). This is the only breakage that can lose artwork, and §3 is
   about it.
2. **The whole-cel Move undo bracket.** `VectorTransformBracket` holds two affines and a reference
   (`CanvasManager.swift:236-241`); `closeVectorTransformBracket` restores by calling `setTransform`
   both ways (`:390-399`) and its doc calls that *"lossless … with no re-rasterization anywhere"*,
   which for the *undo* is true. With no field to restore, the step has to carry either the
   pre-transform elements or the inverse map. §4 prices both.
3. **`resized(to:offset:)`** (`:432-437`) must translate the display list instead of composing a
   translation. Exact, and its own doc's word "lossless" survives the change — a translation moves no
   sample onto a different sub-pixel and re-stamps nothing.
4. **The lasso float's `baseTransform`.** `VectorFloat.baseTransform` (`CanvasManager+LassoMove.swift:52`)
   and the identity its doc asserts — `VectorCanvas.affine(from: frame.transform, pivot: pivot) ==
   baseTransform` (`:56`, `:215-218`) — become the identity case. The arithmetic does not change; it
   simplifies. `LassoMoveLogicTests.testAZeroDeltaNudgeChangesNoSampleAndNoPixel` still means what it
   means.
5. **`mapping(_:throughSimilarity:)`'s three floors now bite the whole-cel Move.** This is the one
   place the ruling changes what the artist sees, and it must be disclosed rather than discovered.
   `BrushStamper.stampSpacing`'s **1 pt absolute floor** (`BrushStamper.swift:67`) means that below
   `brushSize · spacingFraction == 1` a scaled stroke gets a different dab count — *"under 20 pt for
   Hard Round, under 33 pt for the Pen"* (`VectorLayer.swift:1597-1604`). Today a whole-cel scale is a
   bitmap resample and therefore does **not** hit this; after the change it does, exactly as a lassoed
   piece already does. LASSO_MOVE.md §1 inherits the three floors *"knowingly"* — but it inherited them
   for a piece the artist deliberately transformed, not for every cel they nudge. §9 asks whether the
   owner wants to be told.
6. **`renderIsolated(ids:)`'s transform arm** (`:2400-2406`) goes. No behaviour depends on it beyond
   the float's picture agreeing with the layer's, which identity preserves trivially.
7. **`transformScale`** (`:590`) and **`localSamples(fromCanvas:)`** (`:598`) go. The first has one
   caller and it is `BrushEngineLogicTests.swift:537`; the second has none anywhere. Both are dead
   weight today and are worth deleting whatever is decided here.
8. **Tests that construct a canvas with a transform.** `VectorCanvas.init(size:elements:transform:)`
   and its three-array convenience both take one; `BrushEngineLogicTests`,
   `VectorTextPersistenceLogicTests`, `VectorTransformUndoLogicTests`, `ObjectTransformLogicTests` and
   `LassoMoveLogicTests` all exercise non-identity transforms deliberately. These are the bulk of the
   churn in §7 stage 3, and most of them become tests of the *bake* rather than being deleted.

**Nothing else breaks.** The eleven inverting entry points each lose an inversion and keep their
signature. Thumbnails, export, onion skin, merge, rasterize-layer and the compositor never see the
field at all.

---

## 3. Migration

**Bake on load, write identity forever, keep the field.** That is correct, it is not lossy in
geometry, and it needs no version gap in either direction.

```
elements = elements.map { VectorCanvas.mapping($0, throughSimilarity: payload.affineTransform) }
transform = .identity
```

**Is it correct?** Yes, on one precondition that holds: `mapping(_:throughSimilarity:)` asserts its
argument is translate·rotate·uniform-scale (`VectorLayer.swift:1613-1617`), and the only two writers of
`_transform` produce exactly that — `setVectorTransform` goes through `affine(from:pivot:)` with
`aspect == 1` (`CanvasManager.swift:352`, `VectorLayer.swift:874-876`), and `resized(to:offset:)`
appends a translation. `ObjectTransformFrame.isFreeform`'s own doc records why nothing else can:
*"`VectorCanvas.setTransform` can only carry a similarity, so a stretched whole layer has nowhere to be
stored"* (`ObjectTransformFrame.swift:246-255`). A hand-edited or future file could still hold a shear;
the fallback is defined and already written — `mapping(_:throughStretch:)`, with the ink taking
`sqrt(|det|)` by the owner's ruling of 2026-08-27 (LASSO_MOVE.md §5.17).

**Is it lossy?**

| | lossy? |
|---|---|
| stroke samples, fill paths | **No.** 1.3e-13 pt over 264 similarity cases — the figure `mapping`'s own doc carries (`VectorLayer.swift:1587`). |
| `stroke.size`, text `pointSize`, image `scale` | **No.** One multiply, and today's storage already divides by the same number on the way in. |
| text `frame.corners` | **No.** Four point maps. |
| **rendered pixels** | **Yes — and better.** The bake is a native re-stamp at the new size where today is a bitmap magnify (defect B). The exception is the `stampSpacing` floor (§2 item 5), which changes the dab count on a heavy shrink. It costs no ink — dab diameter still scales — and it re-rolls the dab RNG, which is invisible on all five built-in brushes because their `scatter` and `rotationJitter` are zero (`VectorLayer.swift:1600-1603`). |

**Forward and backward compatibility — the rare case with no gap at all.** Keep `transform` in the
schema and keep writing `[1,0,0,1,0,0]`.

- *New build opens an old document*: bakes on decode. Correct picture, and the next save writes
  identity, so the bake happens once per document ever.
- *Old build opens a new document*: reads identity, applies nothing, draws baked geometry. **Correct
  picture.** This is the whole reason to keep the field rather than drop it — a dropped key decodes to
  `[]`, which `affineTransform` already maps to `.identity` (`:2941`), so dropping it would also work;
  keeping it costs 48 bytes a cel and removes the question.
- *No `ImageRef` change is owed*, which is why correction 3 in §0 is a correction and not a design
  constraint. Baking rewrites an image's `x`/`y`/`scale`/`rotation` **values**; the four `Double`s stay
  four `Double`s and the synthesized `Codable` never notices.

**Where the bake runs.** In `VectorCanvasData`'s own decode path, not in `ProjectStore` — so it is one
place, it is covered by `VectorCanvasDataLogicTests`, and it composes with the per-element `LossySlot`
decode instead of running after it. A cel whose payload dropped an element bakes the survivors, which
is the honest thing to do and matches what that type already does on re-encode.

**Timing.** Per cel, as it decodes — which is where the streaming model wants it (cels are streamed,
not held resident). §4 prices it.

---

## 4. The live drag, and the question that decides its cost

### Is `_transform` per-cel or per-layer-across-all-cels? **Per cel.** Three pieces of evidence:

1. `VectorCanvas` is *"The vector content of **one cel** on a `.vector` layer"* (`VectorLayer.swift:227`),
   held at `Cel.vector`, and every cel of a layer has its own.
2. `setVectorTransform` resolves `activeCelIndex(inLayer:atFrame:)` and writes that one cel's canvas
   (`CanvasManager.swift:336-338`, `:352`).
3. `closeVectorTransformBracket`'s doc has already litigated it: *"**One cel, matching
   `setVectorTransform`.** … a multi-cel vector layer transformed on frame 3 and again on frame 20 has
   genuinely had two different `VectorCanvas` objects changed … A step that reached across every cel of
   the layer would undo a transform the artist never made on the other frames"* (`:374-380`).

**So the tool called "whole-layer Move" moves one drawing.** A bake rewrites that drawing and nothing
else. The 300–1000-cel document is not touched by a Move; it is touched only by the one-off load bake
(§3) and by `setCanvasPadding`, which already walks every cel of every layer synchronously on the main
actor and already regenerates every thumbnail (CANVAS_RESIZE.md §0).

### Does the lasso-move pattern cover it? Yes, line for line

`StrokeCanvasView.beginLiveLayerTransform(base:)` / `updateLiveLayerTransform` / `endLiveLayerTransform`
(`Views/Canvas/StrokeCanvasView.swift:438-468`) is the existing latch, and it is the **model** the
lasso float's own trio was written from — `CanvasManager+LassoMove.swift` and LASSO_MOVE.md §0 say so
explicitly (*"modelled line for line on the whole-layer `beginLiveLayerTransform` trio"*).

The latch does not depend on the field existing. Its parameter is *"the affine the currently displayed
image was rendered at"* (`:436-437`) and every later delta is `viewTransform(from: base, to: current)`.
Under the ruling `base` is `.identity` and `current` is `VectorCanvas.affine(from: pose, pivot:)`. One
`UIView.transform` assignment per touch-move, exactly as today. **PERFORMANCE.md item 11's 5 fps → 60
fps fix is untouched.**

What changes is the *end* of the gesture:

| | today | under the ruling |
|---|---|---|
| per touch-move | one `UIView.transform` + one `setTransform` + `scheduleThumbnailRegen` | identical |
| at gesture end | replace one affine; `endLiveLayerTransform` rasterizes once | map N samples; `endLiveLayerTransform` rasterizes once |
| undo step | two affines, nominal cost 4096 (`CanvasManager.swift:395`) | see below |

**The bake, priced on the owner's real cel.** 190 strokes (TODO.md:121 — *"the cel measured on the
owner's own device"*) and 8,714 samples (the figure this pass was handed; **it is not recorded anywhere
in this repo and should be landed in PERFORMANCE.md with its provenance**). A similarity map is four
multiplies and four adds per point, plus one multiply per stroke for the width: ~70k floating-point
operations. That is **microseconds**, against a `render()` on the same cel that stamps thousands of
radial gradients into a canvas-sized context. INFERRED, but the margin is four orders of magnitude and
does not need measuring.

**The undo step, priced honestly.** Two options:

- *Whole-array swap*, which is what `registerVectorElementsUndo` (`CanvasManager+Text.swift:411`)
  already does for every other vector mutation, and what `applyToVectorFloat` does per nudge. At 24
  bytes a sample that is **~209 KB per Move gesture** on the measured cel. `UndoBudget`'s floor is 64
  MiB (`UndoHistory.swift:85`), so ~300 whole-cel Moves before the oldest trims. Acceptable, and it is
  the shape every neighbouring path already uses.
- *Store the inverse similarity* — 32 bytes a step, and exactly invertible. **MEASURED** (scratch
  `swiftc`, 2026-08-27, 200 trials × 200 composed gestures, scale ∈ [0.3, 3],
  full rotation, probes spanning −500…2500): worst point drift **3.6e-11 pt**, worst relative width
  drift **4.5e-15**. Four orders below the quarter-pixel quantum item (8) is going to store, so
  incremental baking is numerically free.

Take the array swap for stage 1 — it matches the neighbours and it survives a future non-similarity —
and keep the inverse-map option in reserve if the budget ever complains.

**The one disclosure.** While the finger is down the latched picture is a Core-Animation-scaled bitmap
and the bake is a native re-stamp, so **the preview is soft for the length of one gesture and snaps
sharp on release**. Today the preview and the commit are *both* soft (defect B), so they agree and
nobody notices. This is the identical bargain LASSO_MOVE.md §5.17 disclosed for Freeform's stretched
ink and the owner accepted; the same `mayDiverge` latch-drop mechanism bounds the error to one
gesture and stops it accumulating.

---

## 5. Images and text — which transforms survive, and why they are not the same wart

They survive, both of them, and the distinction is sharp enough to state as a rule.

> **A transform is an object property when its consumers *compose* with it. It is an indirection when
> its consumers *invert* it away.**

`VectorImageElement.transform` is a `LayerTransform` — position, one scale, one rotation
(`VectorLayer.swift:164`). Every consumer composes:

- `mapping(_:throughSimilarity:)` multiplies into it (`:1631-1633`);
- `splitForLassoMove` tests `image.transform.position` for containment (`:1505`);
- `contentBounds(of:)` reads it to size the box (`:1333-1335`);
- `draw(image:into:)` concatenates it (`:2596`);
- `registrationPoints(of:)` contributes it (`CanvasManager+Interpolation.swift:1221`).

**Nobody inverts it.** A placed photograph *is* a rectangle with a pose; the pose is the object's
identity, not a lens the storage is viewed through. The same rectangle exists in Illustrator, in
Procreate and on the artist's desk.

`TextFrame` is stronger still. It stores **four canvas points** (`TextObject.swift`, `frame.corners`) —
not a matrix — and `affineTransform` (`:445`) and `homography` (`:470`) are *derived from* the corners
on demand. There is no stored transform to remove. `mapping` maps the corners
(`VectorLayer.swift:1644`) and scales `frame.size` and `pointSize` with them, for a reason its own
comment argues at length: `TextFrame.Basis` states `basis.width == size.width` for every frame this
project writes, and mapping the corners alone would break it.

So the owner's *"every object … should be given coordinates according to the canvas"* is satisfied
exactly: **the coordinates are canvas coordinates.** An image's coordinate is a centre plus a scale
plus an angle; a text box's is four corners. Both are positions in canvas space once `_transform` is
gone — which is more than can be said today, where `localText(fromCanvas:)`'s doc has to warn that
`TextFrame.corners`' own comment *"says canvas space"* and is *"written from the authoring
perspective"* while the storage is local (`VectorLayer.swift:1636-1641`). **Removing the layer
transform makes that comment true.** That is the cleanest small proof that the indirection is the wart
and the object poses are not.

Two concrete simplifications fall out: `addImage(canvasSpaceElement:)` stops dividing `canvasFit` and
the 24 pt import cascade by the layer scale (`:673-677`), and `localText(fromCanvas:)` /
`canvasText(fromLocal:)` collapse to the identity and can be deleted along with `mappingText`.

---

## 6. The bit-width outcome — the honest number

**The owner's 15/16-bit hope is not reached, and the ruling should not be sold on it.**

TODO item (8) settled 24 signed bits an axis at quarter-pixel on 2026-08-27, because
`ceil(log2(extent)) + 2` bounds a coordinate **only if stored coordinates lie inside `[0, extent)`**,
and CANVAS_RESIZE.md §2 found three independent reasons they do not. Adopting this ruling retires
exactly one of the three:

| reason a coordinate leaves `[0, extent)` | after the ruling |
|---|---|
| **1. Layer-local storage.** `8192 / 0.02 = 409,600 pt` (TODO.md:73-78) | **Gone.** There is no local space, so there is no `1/k` term. |
| **2. Touches keep being delivered outside the view.** Nothing clamps a sample to the canvas rect | **Unchanged**, and worse than it looks: I could find **no clamp on canvas zoom anywhere in `CanvasView.swift`** — no `minimumZoomScale`, no clamp in `handlePinch` (`:3129`) — and five overlays guard with `max(canvasScale, 0.01)`, which is the code contemplating 1 screen point = 100 canvas points. A drag across a 1366 pt screen at that zoom records ~136,600 canvas points. (INFERRED — an absence of evidence; a clamp may live somewhere I did not find, and this is §9's fourth question.) |
| **3. A shrink parks content outside the bounds.** `setCanvasPadding` crops the raster tiers and leaves vector elements where they are | **Unchanged.** Bounded by the *old* extent, so ≤ 8192. |
| **4. (not in that list, and it should be) The lasso float's scale has a floor and no ceiling.** `uniformlyScaled` clamps with `max(…, minimumScale)` and nothing above (`ObjectTransformFrame.swift:312`); `stretched` the same per axis (`:340-341`) | **Unchanged**, and it already writes into element geometry today. Repeated grow gestures are unbounded in principle. |

**The honest bound.** Retiring reason 1 takes the *accidentally* reachable worst case from 409,600 pt
— one corner drag — down to whatever reason 2 allows, which on the evidence above is ~137,000 pt and
is not provably bounded at all. Reasons 2 and 4 are both unbounded-in-principle, so **no field width
is safe without a saturating clamp at encode time**, and nothing in the tree clamps today.

**The honest field width.** If reason 2 were clamped to, say, 4× the extent (32,768 pt), a signed
quarter-pixel field would need 18 bits; 20 bits (±131,072 pt) would restore 4× headroom. Against
today's settled 24, that saves **one byte of a seven-byte sample — 14%** — and costs the byte
alignment that made 24 the choice. It is not a reason to do anything.

**Stated plainly: the ruling is worth adopting for §2's three defects and §1's eleven inversions. It is
worth nothing for the bit width, and TODO item (8) should not be re-opened on account of it.**

---

## 7. Cost, in stages that each merge and are each usable

The staging convention is ADD_TEXT.md §3's: one worktree per stage, each lands on `main` on its own,
each is usable on the owner's iPad. A new *test* file needs a hand-written `project.pbxproj` entry with
an id derived from the file name, plus the duplicate-id check after any rebase — CLAUDE.md's warning
about two branches minting the same id.

**Stage 0 — confirm the defects and clear the dead wood. ~2 hours, no risk.**
Get defects A and C on the owner's iPad (a recording, or four seconds of their time); file all three in
BUGS.md; fix the false doc comment at `CanvasManager.swift:329-331`; delete `localSamples(fromCanvas:)`
(`:598`, zero callers) and `transformScale` (`:590`, one test caller). No behaviour change. **Do not
start stage 1 before defect A is confirmed** — the whole case rests on it, and it is read off the
source, not observed.

**Stage 1 — `bakeTransform()` exists, and every writer ends in it. ~1–2 days. This is the smallest
useful shippable thing.**
One new method on `VectorCanvas`: map every element through the current `_transform` and set it to
identity. Four call sites: `closeVectorTransformBracket` bakes at the end of a Move gesture (and its
undo step becomes an element-array swap); `resized(to:offset:)` bakes its translation; the load path
bakes what it decoded; `rasterizeLayer` needs nothing (it flattens through `render()` either way).
**`_transform` still exists and `render()` still applies it**, so during a drag nothing about the render
path changes and every existing test that constructs a canvas with a transform still compiles and still
passes. Defects A, B and C stop being reachable for anything the artist does from here on.
*Tests:* a Move-then-draw test that a stroke drawn after a 0.3× Move lands where the finger was (the
regression test for defect A); a scale-up render that is sharper than the bitmap magnify; an
interpolation test across two moved keyframes. Plus the round-trip: bake ∘ affine⁻¹ returns the samples
to within the 1.3e-13 pt `mapping` already promises.

**Stage 2 — the persisted field goes advisory. ~half a day.**
Always encode `[1,0,0,1,0,0]`; bake on decode inside `VectorCanvasData.init(from:)`. Migration
complete, in both directions, with no version gap (§3). *Tests:* `VectorCanvasDataLogicTests` gains an
old-payload fixture with a non-identity transform whose decode produces baked geometry and identity,
and a new-payload-in-old-build assertion written as the identity it is.

**Stage 3 — delete the field. ~2–3 days, and it is optional.**
`render()` loses step 2, `renderIsolated` its arm, the eleven entry points their inversions,
`layerTransform(pivot:)` becomes a pose about a pivot, `localText`/`canvasText`/`mappingText` go,
`beginLiveLayerTransform(base:)` takes `.identity`. The cost is not the app — it is the five test files
in §2 item 8 that deliberately exercise non-identity transforms, which mostly become tests of the bake.
**Judge this stage after stage 1 has been on the iPad for a week.** It buys clarity, not behaviour, and
it is the churn.

**Stage 4 — narrow the coordinate field. Not owed, and §6 says do not.**

**Total, honestly: about a week including a device pass**, of which stages 0–2 are two and a half days
and carry all of the value. Stage 3 is the other half and carries none of it. That is not a small
change, and it would be indefensible for two bytes a sample; it is defensible for three defects, one
of which discards ink.

---

## 8. Verdict

### The strongest case for rejecting, stated fairly

**A layer transform is the only operation in this app that is exactly, infinitely and freely
reversible.** Scale a cel to 2% and back to 100% and the geometry is *bit*-identical, because nothing
ever touched it. Undo is two affines and 32 bytes. Under the ruling, the same round trip is exact only
to 3.6e-11 pt and — through `BrushStamper.stampSpacing`'s 1 pt floor — **not reversible in pixels at
all**: a stroke shrunk below the floor and grown back comes back with a different dab count and a
re-rolled RNG. LASSO_MOVE.md §1 accepts those floors *"knowingly"*, but it accepts them for a piece the
artist deliberately picked up and transformed, not for every cel they nudge with the Move box. The
ruling trades an exact operation for an inexact one, spends a week doing it, and the memory argument
that motivated the question turns out (§6) to be worth 14% of one sample field.

Additionally: the deferred-transform design is *correct in principle* and merely has a broken renderer.
The right fix might be to render local content at the transform's own resolution rather than at canvas
resolution — which is a real technique, is what a proper vector renderer does, and would fix B without
touching storage.

### Why I do not take it

The reversibility argument is the good one and it loses on a fact: **the app already made this trade,
deliberately, for the lasso move, and shipped it.** Every nudge of a floating piece maps geometry and
inherits the same three floors, with the owner's ruling behind it. Having two transform paths in one
app where one is exact-and-clipped and the other is inexact-and-correct is worse than having one.

The renderer argument loses on arithmetic: rendering local content at the transform's own resolution
means allocating a buffer `1/k` times the canvas on a shrink, which at the existing floor is 1.7×10¹¹
pixels (§2). The clipping is not a bug in `render()`; it is `render()` defending itself against a
coordinate space that has no bound. **A space that must be clipped to stay affordable, and whose
clipping silently destroys the artist's ink, is the wrong space.**

And the census settles the rest. Eleven entry points invert the transform away; five read it forward;
of those five, one round-trips to the writer and one serves a single eraser preview. A field that
almost every user of it must first undo is not an abstraction, it is a tax — which is exactly what the
owner's instinct reacted to, without having seen the count.

### Adopt, with changes

1. **Adopt** the storage rule: display lists are canvas coordinates; a cel transform is baked, never
   stored.
2. **Do not** promise the bit width (§6). TODO item (8)'s 24 bits stands, and the encoder needs a
   saturating clamp regardless.
3. **Stage 3 is optional** and should be decided after stage 1 has been used (§7).
4. **The `stampSpacing` disclosure needs a ruling** before stage 1 merges (§9.1).

---

## 9. Open questions

1. **Does the owner want to be told that a heavily shrunk-and-regrown cel does not come back
   dab-for-dab?** The geometry does; the dab count does not, below ~20 pt for Hard Round. It costs no
   ink and is invisible on all five built-in brushes. LASSO_MOVE.md §1 already accepts it for a lassoed
   piece — this is the same fact applied to a whole cel. A device question, not a code question.
2. **Should whole-cel Move become one undo step per nudge?** LASSO_MOVE.md §5.5 rules *"four — one per
   nudge"* and says the ruling *"covers both"*, with §3 stage 4 recording that `setVectorTransform` does
   not obey it yet. Stage 1 rewrites that step anyway, so this is the cheapest it will ever be to fix.
3. **Should the tool be renamed?** Every name says "layer" and the storage has always been per-cel
   (§4). `isVectorTransforming`, `setVectorTransform`, `beginLiveLayerTransform` and
   `LiveLayerTransform` all mislead a reader about what a Move touches. Cosmetic, and cheap while the
   file is open.
4. **Is there a clamp on canvas zoom?** §6 reason 2 turns on it and I could not find one. If the answer
   is no, that is worth its own BUGS.md entry independent of everything here — an unclamped zoom makes
   the stored-coordinate domain unbounded whatever the storage model is.
5. **Should the fixed-point encoder saturate, refuse, or assert?** Not answered by item (8), and it has
   to be answered before that item ships.
6. **Where did 8,714 samples come from?** The figure is load-bearing for §4 and is not in this repo.
   It belongs in PERFORMANCE.md labelled MEASURED with its provenance, beside the 190 strokes that
   already is (TODO.md:121).
