# Known Issues

Open items only — fixed entries are pruned, and the fix lives in the commit and the code comment.
One section per bug, newest first.

## An interrupted stroke stubs, and no terminal callback runs (2026-08-16)

A stroke begun while a timeline popover is open stops being processed a few samples in. Touch
delivery to the recognizer stops and **no terminal callback fires — crucially not cancel** — which is
why the stub survives the pen lift and dies only when the next stroke rebuilds `vectorScratch`
(`StrokeCanvasView.swift`).

With the pen this reads as "the stroke turns into a line after a lag spike": the smart-shape hold
timer has nothing left to reset it, so it completes 0.8 s later and replaces the ink with a detected
line. The perceived lag spike is exactly that hold constant elapsing, not a stall — the popover
teardown itself was **measured at 0.43 ms**. With the eraser the same stub appears without the line,
because shape detection is gated to pen/pencil.

**Two candidates that reading could not separate**: a mid-sequence `isUserInteractionEnabled`/removal
flip (`CanvasView.reconcileLayers` writes both, `CanvasView.swift:388`), or UIKit dropping the touch
sequence via the popover's presentation overlay. Nothing here picks between them yet.

This is the shape the entry below (`StrokeGestureRecognizer.failTrackedStroke`) already names: a path
that fails an already-begun stroke which nothing in the suite reaches. Next step is a capture — the
action recorder (see CLAUDE.md) on the owner's iPad, reproducing a stroke started under an open
timeline popover, read for where in the touch sequence delivery actually stops.
## Drawing on a compositor document runs at ~17 fps on a 4K canvas, and the cap only dents it (2026-08-16)
## XCUITests cannot launch into the editor on the iPad 9 (2026-08-16)

The logic tier runs on the owner's device beautifully — 991 tests in 36 s, Release, against 3 min on
the simulator — but **every XCUITest fails in `launchIntoEditor`**, before it has touched anything it
is about to test. 18 of 18 in `SandwichCompositingUITests` + `BlendModesAndCompositorUITests`, all at
the same line.

The trace says why: `Tap "sizePicker.createButton"` → `Computed hit point {-1, -1} after scrolling to
visible`, so the tap never lands and `timeline.frameLabel` never appears. That is the size picker
laying out differently on a 10.2" 4:3 screen (2160x1620) than on the iPad Pro 13" every UI suite was
written against — a test-fixture problem on the device, not a product bug, and nothing to do with the
compositor.

Worth fixing because device runs are 5x faster than the simulator and are the only place the memory
behaviour is real. Likely fix: make `launchIntoEditor` scroll the size picker or dismiss it by
keyboard rather than tapping a button that can land off-screen. Until then, **device testing means
the logic tier only**, and the UI suites stay on the simulator.

## Drawing on a vector layer at 4K is capped at ~19 fps by the live stroke preview (2026-08-16)

**Measured on the owner's iPad 9, Release** (`PerfBaselineTests.testTheLiveStrokePreviewCostsFourTimesMoreOnAVectorLayerThanARaster`):
one dab costs **53.8 ms on a vector layer at 4096²** against 4.0 ms on a raster layer — a ceiling of
**19 fps** before anything else in the frame, against 250 fps for raster. At 2048² it is 16.4 ms
against 3.0 ms. The owner reports 17 fps.

`StrokeCanvasView.refreshDisplay`'s `.overlay` branch runs once per touch-move and does four
canvas-sized things where the raster path does one: it allocates a **fresh** canvas-sized
`UIGraphicsImageRenderer` bitmap, draws the committed vector render into it, renders the live scratch,
and draws that over the top. At 4096² the allocation alone is 64 MiB, per dab.

**This is not the compositor and it is not this branch.** No composite runs during a dab —
`makeSandwichKey` freezes the active layer's content version for the duration of a stroke precisely so
the compositor stays off the drawing path — and `refreshDisplay` predates the Metal work. The owner's
own experiment proves it from the other side: halving `renderResolution` cuts a sandwich rebuild from
40.6 ms to 13.1 ms on that device and **changed the frame rate not at all**, because
`RenderResolution` is applied in `makeSandwichRequests` and reaches nothing on this path.

**The fix, and it belongs in its own branch.** Stop compositing the two into one bitmap: give the
scratch its own `UIImageView`/`CALayer` over the committed one and let Core Animation composite them,
which it is doing anyway. That deletes the per-dab allocation and both blits, leaving only
`scratch.renderToUIImage()` — the raster path's cost. It is a change to the most gesture-sensitive
code in the app (`vectorScratchRole` has three modes and `.replacement` and `.none` behave
differently), so it wants its own branch and its own pass through the vector-eraser UI suites, not a
rider on a compositor-memory fix.

## The project thumbnail composites the whole canvas to make a 320x320 tile (2026-08-16)

`ProjectStore.SaveSnapshot` builds a full `makeRenderRequest` at native canvas size, composites it,
and hands the result to `ThumbnailRenderer.render(…, thumbnailSize: 320x320)`. On a 4096² document
that is 16.8M pixels rendered to fill 102k — and on a 3 GB device the GPU path declines it
(`CompositorBudget`, which sizes only the *live canvas* down), so it lands on the CoreGraphics
reference. With a bloom and a blur in the stack that is minutes of background CPU per save.

**Not a regression from the Metal flip** — with the old `.coreGraphics` default the thumbnail took
exactly the same path — and on a device with room it is now much faster than it was. Left alone here
because fixing it properly means deciding what size a thumbnail composite should be and checking that
against `ProjectSaveLogicTests`, which is a save-path change and not a crash fix. The shape of the
fix: give `makeRenderRequest` an optional render size the way `makeSandwichRequests` has one, and
have `ProjectStore` ask for something near the tile's own size.

## The Metal composite hands Core Animation a non-native pixel format (2026-08-16)

`CompositorMetalEngine.readBack` builds its `CGImage` as `premultipliedLast` RGBA in device RGB;
Core Animation's native layout on iOS is BGRA premultiplied-*first*. So assigning one to
`UIImageView.image` costs a full-canvas convert-and-copy inside the CA commit, on the main thread —
three of them per sandwich rebuild, 64 MiB each at 4096². The CoreGraphics backend never paid it: a
`UIGraphicsImageRenderer` image is already in CA's format, so this arrived with the backend flip and
is invisible to every headless benchmark, which stops at the `CGImage`.

**Unmeasured on device** — it is a hitch per stroke-lift rather than a sustained cost, so it is not
the 17 fps above. Worth fixing next: `bgra8Unorm` for the two accumulator textures would produce
byte-identical pixel *values* (Metal presents both formats to a shader as RGBA) with a CA-native
byte order, at the cost of one runtime capability check. Verify with `CompositorParityLogicTests`,
which compares values rather than layouts and so would not itself notice the change.

## Two-finger pan/pinch/rotate is dead while the Fill tool is selected, on device (2026-08-15)

The product owner reports it from their iPad: pick Fill and the canvas will not pan, pinch or rotate;
pick any other tool and it does. **Unexplained and not fixed.**

Three simulator attempts failed to reproduce it — including a `-configuration Release` build and a
real two-finger drag rather than the canned `pinch`/`rotate` gestures — and the canvas moved every
time, so this is not something the shipped XCUITests are failing to notice. It may be device-specific
(a real pencil/palm in play, `UIPencilInteraction`, or hover events the simulator never delivers).

Do not "fix" it by guessing at recognizer priorities. **Next step is a capture, not a patch**: turn on
the action recorder (see CLAUDE.md), reproduce it on the iPad, and read which recognizer answered what
— the recording carries every state transition and every `shouldRequireFailureOf` answer, which is
exactly the evidence the simulator refused to produce.

## A mask sourced from a graded group can be stale (2026-08-15)

A group used as a mask **source** whose effect reshapes coverage — blur, outline, bloom, Sobel,
sharpen — can serve a mask computed before the grade changed.

`MaskResolver`'s cache key is built per-*layer*, from `stack.leafLayerIndices`, and a folder is not a
leaf: a folder's grade cannot reach the key at all, so changing it does not invalidate anything. Only
effects that change *coverage* show it; a grade that only moves colour leaves the thresholded alpha
where it was.

Fixing it means putting node grades into the mask cache key, which is a change of its own and not an
extension of the per-layer version — the key would have to walk the stack's folders as well as its
leaves. Deliberately not attempted alongside the effect UI.

## Whether UIKit honours a `.began -> .failed` transition is unverified, in both directions (2026-08-15)

`StrokeGestureRecognizer.failTrackedStroke` exists to fail a stroke that has already begun, and
**nothing in the suite reaches it.** Every two-finger gesture — synthetic *and* real, confirmed by an
action recording — delivers both touches in a single event, so the recognizer is still `.possible`
and takes the legal `.possible -> .failed` guard instead.

So the question is open on both sides: it is not established that UIKit honours the transition, and it
is not established that it refuses. A defensive conditional readback is in place and is documented in
the code as unproven — do not read its presence as evidence it works.

What would settle it: a test that delivers the second touch in **its own event**, some frames after
the first, so the recognizer is genuinely `.began` when the failure arrives. Until someone writes
that, treat the path as unexercised.

## The onion skin renders unmasked (2026-08-15)

`PreviousCelOnionSkinSource` rasterizes the previous cel with `PixelOps.rasterize(cel:)` and applies
no mask, and `onionSkinView` sits below `sandwichBelowView` and is never blanked
(`CanvasView.swift:46` vs `:54`, shown at `:1416-1419`). So a masked layer's onion skin draws ink
outside the layer's own mask, at `onionSkinOpacity`.

**Half of this shipped as a fix and half is deliberately deferred.** The half that shipped: the
source asked for the cel at `currentFrame - 1`, but `addVectorLayer` mints ONE cel spanning the whole
scene, so from any frame but the first that lookup returned *the cel being drawn on* and the onion
skin ghosted the live artwork onto itself. Invisible normally — the layer's own pixels cover it — but
a mask uncovers it, which is how the product owner found it: a red layer masked by a black one showed
translucent red outside the mask on every frame of a block except frame 0. Fixed by stepping back
from the current *cel's* `startFrame`, which is what the doc comment always promised.

The residue: with two genuine cels, the previous cel's ghost is still unmasked, so the same leak
returns. Not fixed here because the owner is overhauling onion skin into a proper customizable menu
and this would be rewritten. When it is rewritten, reuse `resolveLiveMask(forLayerAt:)` /
`RenderNode.masksClipping(leafAt:in:)` rather than writing a second mask-resolution path, and mind
§6.4's warning that a `CALayer.mask` slot collision fails silently in whichever direction install
order decides.

## The multi-pass effect decline path is reasoned-correct and uncovered (2026-08-15)

`EffectPipelines.encode` returns `false` for "declined — fall back to `EffectReference`", and its
caller now honours that with `guard effects.encode(…) else { pool.release(scratch); return false }`.
Nothing tests it: the decline only fires when the device refuses a texture allocation, which a
healthy simulator never does, so the guard is verified by reading rather than by running.

Worth knowing *how* it got there, because the shape recurs. Merging `tmp/p9-layer` and
`tmp/p9-multipass` created it out of two changes git reported no conflict between, because they
touched different lines: `encode` returned `Void` on one branch, so the caller ignoring its result
was correct; the other branch made it `@discardableResult -> Bool`. Merged, the caller discarded the
signal, `@discardableResult` suppressed the warning that would have caught it, and a decline
proceeded to `mix()` with an **unwritten pool texture** — stale pixels presented as a result.

## A green backend-parity test does not prove both backends ran (2026-08-15)

Every parity test appends the Metal case only `if CompositorMetalEngine.shared != nil`, and
`xcresulttool get test-results activities` on a full run shows only Start/Set Up/Tear Down — no
console log, no activity naming the backend. So a green parity sweep is equally consistent with
CoreGraphics-only execution on both sides of the comparison. The tests are honest; their green
under-determines what it exercised. Fix once, generally: an `XCTContext.runActivity` per iteration
recording which backend(s) actually ran.

## Duplicating a cel or a layer drops the in-between's `interpolation` recipe (2026-08-14)

Both per-cel copy sites build `Cel(...)` without passing `interpolation`:
`CanvasManager+LayerTree.swift`'s `duplicateLayer(at:)` (the `source.cels.map`, ~line 384) and
`CanvasManager+Timeline.swift:106`'s `duplicateCel`. A duplicated in-between therefore keeps its
pixels and silently loses its recipe link — it stops being derived and becomes an ordinary drawing,
with no feedback.

**Deliberately not fixed here, because the obvious fix may be worse than the bug.**
`InterpolationRecipe.references` holds `CelRef(layerID:celID:)` — **UUIDs, not indices within the
layer** — and both duplicate paths mint fresh UUIDs for the copy (and, in `duplicateLayer`, for the
layer too). So copying the recipe across verbatim does not give the duplicate its own keyframes: it
gives it pointers back at the *original's*, and the copy's in-betweens would regenerate from the
source layer, tracking edits to a layer the artist thinks they have left behind. The three candidate
answers — remap each `CelRef` through the old→new id mapping the duplication already builds, drop
the recipe as it does today but say so in the UI, or copy verbatim and accept the shared reference
as intentional — are a vector-interpolation product call, not a layer-compositing one. See
[VECTOR_INTERPOLATION.md](VECTOR_INTERPOLATION.md).

## Fill tool: the gap-closing UI test is still skipped (2026-07-21)

`testFillToolBridgesOpenContourGapWhenGapClosingEnabled` is `XCTSkip`'d, and it is the single skip in
every clean full run. Three separate causes were found and fixed along the way (an originally
unbridgeable gap, `app.sliders.firstMatch` grabbing the wrong slider, and a synthetic drag too near
the screen edge dropping the next stroke) and the final containment assertion still fails. Next
steps: re-point the "outside" probe using `visibleCanvasBounds`/`safeOutsideCornerPoint`; if it still
fails, call `FloodFillEngine.fill` directly on synthetic wall data to tell a real leak from a
test-probe bug — the morphology math itself is verified correct in isolation. Re-enable by deleting
the `throw XCTSkip(...)` at the top of the test body.

## Duplicate is a silent no-op against an adjacent neighbour (2026-07-28)

The overlap bug behind this is fixed (the shared frame-length clamp filters `>= startFrame`), but
when a neighbour starts at exactly the source's end frame there is zero free space, so Duplicate
correctly does nothing — with no feedback at all. Worth greying the control out when
`clampedCelLength` returns nil. The alternatives that aren't a no-op — place the copy at the next
free run, or shift later cels rightward — are timeline feature design and a separate decision.

## Switching brush presets resets live size/opacity (2026-07-22)

`selectBrush` re-baselines `brushSize`/`brushOpacity` from the preset, so re-tapping the current
brush throws away a size the user just dialled in. Partly intentional per its doc comment — needs a
product call, not just a fix.

## Missing / stubbed, as designed

- Distort/Warp transform modes render and gesture identically to Uniform but still appear in the Move
  bottom-bar picker.
- ActionsMenu's Cut/Copy/Paste/Drawing Guide are "Coming soon"; the timeline block menu's
  "Select Multiple" is permanently disabled.
- No UI to change `fps` (fixed at 24) or edit scene length directly.
- Square/custom brushes are tiled round dabs, not true shaped stamps (scalloped edges, seam
  build-up); per-stamp `.normal` compositing builds opacity up where a stroke crosses itself, which
  is the flow-versus-opacity distinction the engine does not make.
  **The "slow strokes read darker than fast ones" half of this entry was wrong and is corrected**:
  dab emission is not timed. `BrushStamper.advance` walks from the last *dab* and returns unmoved
  below one spacing, so a pencil held still lays one dab, and a 400pt line gets the same 50 dabs per
  100pt whether it takes 0.3 s or 10 s. What is left is hand tremor, not the clock — at a slow speed
  the aim from the last dab to the sample that finally clears the spacing carries proportionally more
  noise, so the chain wanders: 100.0 → 106.0 dabs per 100pt from 800 to 40 pt/s at 0.4pt of tremor,
  100.5 → 149.2 at a shaky 0.8pt. `StrokeSampleGate` halves the residue as a side effect. Removing it
  outright is a stabilizer question, not a sampling one.

## Cleanup opportunities

- **Duplicated transform-overlay code** — `ObjectTransformOverlayView` and `FloatingPieceOverlayView`
  each define their own `HandleView` and near-identical project/rotate/resize logic.
- **Duplicated canvas-flip geometry** — `CanvasManager.flippedImage` and `RasterLayerTexture.flipped`
  implement the same mirror-about-centre draw twice.
- **`ContentView.saveIfNeeded`** fires only on scene-phase change and Return-to-Gallery, so a direct
  project→project transition would silently drop unsaved work. Currently safe only because every
  entry point goes through the gallery first.
- **A vector cel still carries `fillImage`/`bakedImage`**, so raster features allocate canvas-sized
  bitmaps on a vector layer. The product owner wants vector fully divorced from raster —
  [VECTOR_INTERPOLATION.md](VECTOR_INTERPOLATION.md) §4 item 26 is the full write-up.
