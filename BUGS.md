# Known Issues

Open items only — fixed entries are pruned, and the fix lives in the commit and the code comment.
One section per bug, newest first.

## `testMovingThePlayheadRebuildsTheBlendedCanvas` is order-dependent (2026-08-15)

Not load, and not a product regression — **state left in the simulator by whatever test ran before
it**. Measured three ways on an erased simulator, quiet machine:

| run | result |
|---|---|
| full boundary suite (961 tests) | **failed** |
| with one other `LayerUITests` case, erased first | **failed** |
| genuinely alone (`totalTestCount: 1`), erased first | **passed** |

It dies at `LayerUITests.swift:657`, which is `row.waitForExistence` inside the `setBlendMode`
helper — a **missing layer row**, nothing to do with the playhead or the composite its name
describes. Two other tests call that same helper with the same `layerIndex: 1` after the same
`drawCrossedStrokesOnTwoLayers` setup and both pass, so the row identifier is not broken.

The likely mechanism is that `launchIntoEditor` does not guarantee a fresh document, so a prior
test's project is restored and the panel does not hold the two layers this test assumes. The fix
belongs in the test's setup, not in the app. **Do not "fix" it by re-running until green.**

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
- Adjust panel and ActionsMenu's Cut/Copy/Paste/Drawing Guide are "Coming soon"; the timeline block
  menu's "Select Multiple" is permanently disabled.
- No UI to change `fps` (fixed at 24) or edit scene length directly.
- Square/custom brushes are tiled round dabs, not true shaped stamps (scalloped edges, seam
  build-up); per-stamp `.normal` compositing makes slow strokes read darker than fast ones.

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
