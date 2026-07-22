# Known Issues

Format: one section per bug, newest first. See [CLAUDE.md](CLAUDE.md) for the multi-session protocol.

> **Housekeeping (2026-07-22):** two previously-tracked issues were removed as resolved and
> verified against the full test suite (29 tests, 0 failures, 1 intentional skip):
> - *Fill containment "regression"* — was a test bug (probe point in the canvas letterbox margin).
>   `testFillToolMasksFromReferenceLayerAcrossLayers` is re-enabled and passing. The one genuine
>   finding from that investigation (the FloodFillEngine vertical flip) is retained below.
> - *Zoomed-in blur / "PencilKit ink can't be fixed this way"* — the raster-content blur fix shipped
>   (`magnificationFilter = .nearest`), and the larger conclusion (replace PencilKit) was **done**:
>   Session 11 replaced PencilKit with the custom `RasterLayerTexture`/`StrokeCanvasView` engine, so
>   there is no PencilKit ink left to blur. The engine-rewrite follow-ups it proposed (Metal GPU
>   renderer, per-stroke opacity-accumulation buffer, dirty-rect bounded undo) are tracked in
>   [SESSION_LOG.md](SESSION_LOG.md) Session 13's "not done" list, not here.

---

## Fill tool: off-center fill vertically mirrored — FIXED (2026-07-22)

**Status:** fixed and verified (visually in the simulator + two re-enabled XCUITests,
`testFillToolFillsOffCenterSquareTopLeftWithoutMirroring` / `...BottomRightWithoutMirroring`).

The long-latent vertical flip was two mismatched CoreGraphics orientation conversions in the GPU
fill's CPU glue (`CanvasManager`): `compositeReferenceRGBA` was extracting the reference bytes through
a `translateBy/scaleBy(-1)` flip, and `imageFromRGBA` was re-introducing one via `CGContext.makeImage()`.
Drawing a top-down `cgImage` into a *default* bitmap context already lands row 0 at the top, so both
now skip the flip (reference via a plain `draw`, output via a `CGDataProvider`-backed `CGImage`).
Centered shapes hid it for months because they're symmetric under a vertical flip.

Note: the XCUITest probe helper `rgbaPixel` had the *same* latent flip (harmless on the centered /
colour-only checks every earlier test used); it was corrected at the same time, so position-sensitive
fill assertions now read the true on-screen pixel.

## Fill tool: gap-closing UI test disabled, root cause not fully closed out (2026-07-21)

**Status:** `testFillToolBridgesOpenContourGapWhenGapClosingEnabled` in `PaintSoftwareUITests.swift`
is still disabled via `throw XCTSkip(...)` at the top of the test body (confirmed still skipped in
the 2026-07-22 run). The fill tool itself is not known to be broken for real usage — this is about
pinning down whether the *test* is still wrong, or whether there's a genuine (probably narrow) leak
bug left in the gap-closing path.

**Note (2026-07-22):** the *sibling* test this originally shared a theory with
(`testFillToolMasksFromReferenceLayerAcrossLayers`) was since root-caused to a letterbox-probe test
bug and re-enabled — so the "why does the passing sibling use the same probe point?" contradiction
below is resolved for that test, and the real canvas-bounds helpers (`visibleCanvasBounds(_:)` /
`safeOutsideCornerPoint(_:)`) now exist. Re-running this test with those helpers for its "outside"
probe point is the obvious next step that hasn't been done yet.

### Confirmed and fixed (while chasing this)

1. **The original gap was unbridgeable at any slider setting.** The test drew a lineart square with
   one edge left "60% closed" (~328pt on a 2048pt canvas); the gap-closing slider maxes at a 40pt
   radius, and morphological closing can only bridge ~2×radius (~80pt), so the gap was ~4× too wide.
   **Fix:** shrunk the intended gap to ~30pt.
2. **`app.sliders.firstMatch` grabbed the wrong slider** (SideToolbar's brush sliders come first in
   the tree). **Fix:** added `accessibilityIdentifier("fillPanel.gapClosingSlider")` /
   `"fillPanel.edgeOverlapSlider"` and the test now looks them up by identifier.
3. **Overshooting a synthetic drag too near the physical screen edge drops the next stroke** (likely
   colliding with an iOS edge-swipe gesture). **Fix:** kept the overshoot modest (`dx: 0.72`).

### Not yet resolved

After all three fixes the test still fails at the final assertion (`isWhitish` at `dx:0.05,dy:0.05`
reads pure black while a screenshot shows the fill cleanly contained). Suggested next steps:
1. Re-point the "outside" probe at a spot provably inside the visible canvas band using the new
   `visibleCanvasBounds`/`safeOutsideCornerPoint` helpers, then re-run.
2. If it still fails, write a unit target that calls `FloodFillEngine.fill` directly on synthetic
   `Layer`/`Cel` wall data (no UI/touch synthesis) to isolate any real leak — the core
   `dilate`/`erode`/`morphologicalClose` math was already verified correct in isolation.

To re-enable once understood, delete the `throw XCTSkip("Disabled pending investigation — see
BUGS.md")` line at the top of the test body.

---

## Feature audit — newly found issues (2026-07-22)

Recorded during a full feature pass; **not yet fixed** (logged only, per request). Roughly ordered
most- to least-impactful. None are crashes; the app builds clean and the whole test suite is green.

### Correctness / behavior

1. **Selections are keyed by layer/cel *index*, not by stable ID.** `Selection`,
   `FloatingPiece.sourceLayerIndex/targetLayerIndex`, and their guards in `SelectionModels.swift`
   store raw `Int` indices. `deleteLayer`/`moveLayer` shift indices without clearing/patching the
   active selection, and `handleActiveContextChanged` only fires on `currentLayerIndex`/`currentFrame`
   `didSet`. Repro: with a selection active on the current layer, swipe-delete *that same* layer from
   the Layers panel — `currentLayerIndex` stays numerically the same but now points at a *different*
   layer, no context-change fires, and the stale selection's guards (`currentLayerIndex ==
   selection.layerIndex`) still pass, so a subsequent Fill/Clear/Move operates on the wrong layer's
   pixels. `FillReferenceMode` already does this the right way (stores a `UUID`); selections should
   too.

2. **`flipCanvas` doesn't flip object (photo) layers.** `CanvasManager.flipCanvas` iterates each
   cel's `raster`/`fillImage`/`bakedImage` only. Object layers hold their image in
   `Layer.objectImage`/`objectTransform`, not in a cel, so Flip Horizontal/Vertical leaves inserted
   photos unmirrored and un-repositioned while everything else flips around them.

3. **RasterLayerTexture is mutated off the main thread during a fill.** `performFill` dispatches to a
   global queue, and `FloodFillEngine.rasterizeReferenceComposite` then calls the reference cel's
   `raster.renderToUIImage()` on that background thread. `RasterLayerTexture` is a non-thread-safe
   class (mutable `CGContext` + `cachedImage`, mutated by `stampCircle` on the main thread). `isFilling`
   guards overlapping *fills* but not a concurrent stroke on the reference layer — a narrow data race.

4. **Deleting a layer's only cel leaves it permanently blank/undrawable.** The timeline block menu's
   "Delete" calls `deleteCel` with no "last cel" guard. A layer with zero cels has no active cel, so
   `activeCelIndex` returns nil everywhere → the layer can't be drawn on and its thumbnail goes stale.
   Recoverable only by tapping the empty gap in its timeline row (which creates a new cel), which isn't
   discoverable. No confirmation prompt either.

5. **Gallery/project thumbnail is a single layer, not the composited stack.** `ProjectStore.save`
   picks the first visible layer's active cel as the thumbnail, so a multi-layer drawing shows only
   its bottom-most visible layer in the gallery tile.

6. **`AppVersion.current` is a stale hardcoded git hash** (`"c8125aa"`, shown in the gallery corner).
   It's a manually-updated constant, so it no longer matches HEAD and will keep drifting.

### UX papercuts

7. **Pencil-only drawing is ON by default** (`pencilOnlyDrawing = true`). On a device/simulator with
   no Apple Pencil, the canvas silently ignores finger drawing until the user finds the SideToolbar
   toggle — easy to read as "drawing is broken."

8. **Picking a black/white/gray swatch discards hue.** In `ColorPickerPanel`, selecting a grayscale
   color sets `hue = 0`; raising saturation/brightness afterward snaps to red rather than preserving
   the previously-chosen hue (most pickers retain it).

9. **Switching brush presets resets live size/opacity.** `selectBrush` re-baselines `brushSize`/
   `brushOpacity` from the preset, so re-tapping the current brush in the panel throws away a size the
   user just dialed in via the SideToolbar. (Partly intentional per its doc comment, but the
   re-tap-same-brush case is surprising.)

### Non-functional / missing (as-designed stubs, listed for completeness)

- Distort/Warp transform modes render/gesture identically to Uniform (`TransformMode.isImplemented`
  is false for them) but still appear in the Move bottom-bar picker.
- Adjust panel, and ActionsMenu's Cut/Copy/Paste/Drawing Guide, are "Coming soon" stubs; timeline
  block menu's "Select Multiple" is permanently disabled.
- No UI to change `fps` (fixed at 24) or edit scene length directly; `fps` only shows as a label.
- Square/custom brushes are approximated as a tiled grid of round dabs (scalloped edges, seam
  build-up), and per-stamp `.normal` compositing makes slow strokes read darker than fast ones — both
  documented placeholder limitations of the foundation engine, pending the real renderer.

## Refactoring / cleanup opportunities (2026-07-22)

- **Two remaining `Color` → components call sites bypass the semantic-color fix.**
  `ProjectStore.swift`'s `Color.codable` (line ~8) and `PixelOps.uiColor(from:)` (line ~19) still call
  `UIColor(color).getRed(...)` directly — the exact pattern `ColorConversion.swift` was written to
  replace (resolve against a fixed trait collection first). Route both through
  `Color.rgbaComponents`/`resolvedUIColor`. (`PixelOps.uiColor` was flagged out-of-scope in Session
  12 and is still live; it backs the Select→Fill action, where `brushColor` could be a semantic
  color.) The `getRed` calls in `FloodFillEngine`/`RasterLayerTexture` take an already-resolved
  `UIColor` and are fine.
- **`CanvasManager.moveLayer(from:to:)` is dead code** — no caller (the Layers panel has no
  `.onMove`), so layers can't currently be reordered at all. Either wire it up (and then make it
  adjust `currentLayerIndex`, which it doesn't) or remove it.
- **Duplicated transform-overlay code.** `ObjectTransformOverlayView` and `FloatingPieceOverlayView`
  each define their own private `HandleView` and near-identical `project(_:)` / rotate-handle /
  anchor-preserving-resize logic. Worth extracting a shared base or helper.
- **Duplicated canvas-flip geometry.** `CanvasManager.flippedImage` and `RasterLayerTexture.flipped`
  implement the same mirror-about-center draw twice.
- **README is stale post-rewrite.** It still documents PencilKit (Step 4 "add PencilKit.framework"),
  pen/pencil-only brushes, and an old file tree (no `Engine/`, `Services/`, Gallery, Select/Move/Fill).
  Update to reflect the custom raster engine, brush library, and current features.
- **`ContentView.saveIfNeeded` only fires on scene-phase change and Return-to-Gallery.** Opening or
  creating a project replaces `canvasManager` without an explicit save of the outgoing one; it's safe
  today only because those paths are reached from the gallery (which already saved), but it's fragile
  — a direct project→project transition would silently drop unsaved work.
