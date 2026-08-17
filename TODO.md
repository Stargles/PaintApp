# TODO

The owner's asks. [BUGS.md](BUGS.md) is for what we find. An item leaves when merged, not when a
branch exists. **Three in flight at once**, unless the extras need no simulator — see
`tools/simlock.sh`.

**At the start of a pass, empty "Done this pass".** It is a record of the pass you are in, not a
changelog — `git log` is the real history, and a list carried across passes stops meaning anything.
Prune it first, before adding the new asks.

## The canvas size that actually matters

**The owner works at 2048×1024, or 1080p — "likely the former" (2026-08-17).** Not 4096².

Every performance number this project has collected was measured at 4096², which is **eight times the
pixels** of 2048×1024. Any cost that scales with area is therefore overstated by roughly 8× against the
document the owner actually animates on, and a conclusion drawn at 4K may be about a canvas nobody uses.
Benchmark at 2048×1024 first and treat 4096² as the stress case, not the baseline. This applies to the
17 fps entry below, the gallery thumbnail, and the onion skin composite alike.

## In flight

- [ ] **The onion skin panel — built, green, and parked unmerged** on `tmp/onion` (`f09f1bc`, worktree
      `../PaintApp-onion`), 1123 tests / 1120 passed / 0 failed. Everything the owner asked for is
      wired: Drawings|Frames (semantics confirmed by the owner), Behind|In Front, count sliders with the
      loop toggle, Tinted|Original, the tint gradient, per-slot opacity sliders, and linked opacity on by
      default. Out-of-pegs deliberately omitted, with the layout left able to take it.
      Resolution is a **Full/Half/Quarter setting defaulting to Half**, the fraction floored at a
      `readableFloorEdge` of 768 px so a small canvas cannot drop below the measured readability cliff
      (512 px fails visibly — hatching collapses to moiré and 2 px strokes vanish).
      **Three things stand between it and merge**, none of them a code problem:
      1. A device re-run of both perf tests. Simulator numbers at 4096²: Full 262 ms / 1495 ms for
         2 / 10 skins, Half 61 ms / 380 ms, Quarter 15 ms / 93 ms. Device is ~1.1× the simulator for this
         workload. **Full at ten skins is worse than the pre-fix implementation was** — flagged below.
      2. The owner's ruling on whether Full needs a warning in the UI, given the above.
      3. A rebase onto current `main` and the merge. Conflict surface is exactly two places in
         `CanvasView.swift` — `updateUIView`'s call order (`updateOnionSkin()` was moved up deliberately
         so "In Front" out-ranks `sandwichAbove` while sitting below the chrome overlays) and
         `makeUIView`'s subview construction. A trial rebase was clean.
      Two facts recorded nowhere else: the device/simulator ratio above, and that **Half + 10 skins at
      4096² thrashes** — only ~3 cached sources fit a 10-skin window, so every rebuild pays ~7 misses.
      Quarter is the setting for that combination. Fixed the shipped double-application of opacity along
      the way (skins drew at 0.09 instead of 0.3) and closed the "onion skin renders unmasked" bug.

## Queued

New this pass (owner, 2026-08-17):

- [ ] **Add Text, in the Actions menu.** Fonts from a large selection, plus colour, size, spacing and
      the rest of what a text tool carries. Move, rotate, and **distort by dragging each of the four
      corners independently, giving a 3D-perspective warp** (a projective/homography transform, not an
      affine one). **On a raster layer it bakes** once a canvas action follows it — a brush stroke,
      eraser, fill — the way the fill tool and smart shapes already behave. **On a vector layer it stays
      an editable object.** Large enough to be its own project, not a single branch.
      Owner's decisions, 2026-08-17: **iOS system fonts to begin with, behind a provider seam** so
      open-source font packs can be added later without touching call sites; and **delivered in stages,
      each one usable**, rather than as one branch that lands whole.
- [ ] **A performance pass, calibrated to 2048×1024.** The owner asked for it directly: *"any
      performance enhancements that can be made to reduce memory, stop lagspikes, or increase fps?"* A
      ten-agent read-only investigation was written and launched, then cancelled when the session ran out
      of usage. **Re-run it rather than re-deriving it** — the script survives at
      `.claude/projects/-Users-juliapark-Desktop-Kevin-P-PaintSoftware/*/workflows/scripts/perf-investigation-wf_f6c930aa-045.js`
      and is re-invokable as-is. It surveys the drawing hot path, compositing and invalidation, memory,
      the app-switch freeze, timeline and playback, and save/load/startup; then ranks through three
      lenses and synthesises a programme. Its whole point is the recalibration above — including a
      required list of candidates *overrated by 4K bias*, since naming the work not worth doing matters
      as much as naming the work.
- [ ] **An oval and a partial oval are one feature, with no modes.** The owner, asked whether a
      nearly-closed stroke should be snapped shut, answered by collapsing the whole design:
      *"The oval and arc feature should be the same feature with no modes. Whatever the user draws that
      follows an oval path whether partial or full spawns in that oval, and the stroke is then projected
      onto that oval. It may not be a full oval, in which case the stroke would only be projected to a
      portion of the oval. Finger snapping it will basically then turn that oval into a circle and the
      partial projection remains."*
      So the model is **an ellipse plus the angular span the stroke covered**. The hold fits the full
      ellipse the stroke lies on — always the whole ellipse, that is the geometry — and what gets drawn
      is the stroke *projected* onto it, which is the whole ellipse when the stroke closed and a portion
      of it when the stroke did not. Handles and editing operate on the ellipse; the two-finger snap
      makes it a circle and **the span is preserved across the snap**.
      **There is deliberately no arc-vs-oval decision to make**, and that is the point of the answer: no
      coverage threshold, no "was this sloppy or intentional", no second shape kind. A full stroke
      projects to a full oval and a half stroke to half, by the same rule. Anything that reintroduces a
      mode here is a misreading. Wants the headless sweep harness `ShapeDetectorLogicTests` already has,
      including spans either side of a closed loop and the span surviving a snap.

Carried over:

- [ ] **17 fps drawing on a 4K canvas.** Diagnosed and **not** the compositor: one dab costs 53.8 ms on
      a vector layer at 4096² against 4.0 ms on raster, because `StrokeCanvasView.refreshDisplay`'s
      `.overlay` branch allocates a fresh canvas-sized bitmap per touch-move. `renderResolution` never
      reaches that path, which is why the owner's 50% test changed nothing. Fix is to give the scratch
      its own layer; wants its own branch. Numbers in BUGS.md.
- [ ] **Returning from another app freezes for a few seconds**, with no memory warning fired.
- [ ] **Leaving to the gallery takes ~3 s.** The thumbnail composites the full 4K canvas for a 320×320
      tile; already in BUGS.md.

## Done this pass

- **Lasso flood fill**, as a *type* option under the existing fill tool (`.flood` still the default),
  drawn with the loop gesture `SelectionOverlayView` already has. Owner's resolution of how the two
  requirements compose: *"it bridges gaps only on the outermost encirclement of the fill tool, all
  inner lines are filled over."* `floodInitFromLasso` seeds the flood at every open pixel the loop
  encircles instead of the one pixel a tap lands on, then unions the loop mask back over the region —
  the seed gives the outer-boundary behaviour (a loop spanning several compartments seeds all of them,
  the region grows out to the artwork's own silhouette, and gap closing acts only at that outer edge),
  and the union is what paints every line the loop encircles instead of treating it as a wall. The mask
  is non-zero winding (an artist overshooting their own start point is normal; even-odd would bite a
  hole out of the fill exactly there) and the seed colour is the loop's most common colour rather than
  its centre pixel, since centring on a line would invert the tool into filling *along* the artwork.
  **The outer half is verified working** — `LassoFillLogicTests` pins it as measurements (a 3-row
  break in a 3px wall bridges at the default 8px radius, a 7-row one does not; a loop that pokes out of
  the intended shape floods whatever it pokes into, in full) — but **the inner-line half does not
  reliably paint over pre-existing artwork on either layer kind, for content on the *same* layer as the
  fill**, and that is a real gap in the feature as shipped, not a hedge:
  - **Vector**: `VectorCanvas.Kind` orders elements `fill = 0, image = 1, stroke = 2`
    (`VectorLayer.swift:349`), so every fill renders beneath every stroke regardless of paint order —
    a lasso fill lands correctly and the line art draws straight back over it. Read from the code, not
    measured; no test asserts it either way. BUGS.md.
  - **Raster**: found while closing out this branch, and it narrows what the branch's own commit
    message claimed about itself. `Cel.fillImage` is documented as composited *underneath*
    `bakedImage` and `raster`'s live strokes (`Cel.swift:10-11`), and both `PixelOps.rasterizeUncached`
    (`PixelOps.swift:209-211`) and `commitInteractiveFill`'s raster branch
    (`CanvasManager+Fill.swift:254-255`) draw `cel.raster`'s strokes last, on top, when flattening —
    so a line drawn in an earlier gesture on the *same* raster layer stays exactly where it was,
    unpainted-over, both live and after commit. `LassoFillLogicTests` doesn't catch this because it
    asserts only on the flood session's own region bytes, before they're composited with anything else.
    The common coloring-book workflow (line art on a reference layer, colour filled on a separate layer
    beneath it) never exercises this, since the tier order that defeats it is a same-*cel* thing — that
    workflow's "line" lives on a different cel entirely. Verified by reproducing the two draw calls in
    isolation (not by running the full gesture through `CanvasManager` — Core Graphics draw order is
    unambiguous and doesn't need the simulator to confirm, but the exact pixel boundary is unconfirmed
    against the real app). BUGS.md, new entry.
  Fixing either is a real design decision (a per-fill z-order flag for vector; painting fill pixels
  directly into `cel.raster` rather than staying in the bottom tier for raster — and the two fixes are
  unrelated), not something to patch quietly alongside a doc pass.
- **Fill tool option: treat the canvas edge as a line boundary. Default on.** The fill was never able
  to escape the canvas — the flood runs over a buffer that *is* the canvas — the real defect was the
  flood running around the *end* of a boundary stroke that stops short of the border, through the open
  paper above its tip and into the next compartment. `fillCanvasEdgeIsBoundary` (default true, a
  toggle under Gap Closing) puts the canvas edge in the wall set: a pixel joins the wall when the
  nearest artwork and the edge are together within the gap-closing radius, so a gap up to r-1 px seals
  and nothing wider does. Additive only (background to wall), so it can't break a fill that already
  worked, and inert at a zero radius. The obvious formulation — add the canvas exterior to the wall set
  and close it — was tried first and rejected: a true close rounds off the canvas's own interior
  corners (92 px of a blank 128×128 canvas unfillable, scaling to 40 px with the slider), which keying
  the bridge off distance-to-real-artwork avoids entirely. Also the first time the fill's GPU pipeline
  is reachable from the fast tier: `Fill.metal` is now a member of the UI-test target's Sources phase
  and `MetalFillEngine` resolves its library via `Bundle(for:)` rather than `Bundle.main`, so
  `FillBoundaryLogicTests` drives the real kernels headlessly in under a second, where `FillUITests` —
  26 minutes away — used to be the only place the fill ran at all.
- **One colour picker, not two.** The canvas background swatch, a value layer's flat colour, an
  effect's colour and a gradient stop each opened SwiftUI's stock `ColorPicker` — a second
  implementation from the brush's `ColorPickerPanel` (SV square, hue bar, opacity, hex field,
  palette library). `ColorPickerPanel` used to write `canvasManager.brushColor` by name, which is
  exactly what `LayerOptionsPanel.valueColorRow` had recorded as its objection to reusing the panel
  elsewhere; it now takes a `Binding<Color>` instead, and all five call sites build the same panel.
  No stock `ColorPicker` is left in the app (`grep -rn "ColorPicker(" PaintSoftware/` returns
  nothing). **`supportsOpacity` is the one capability a bare swap would have dropped**: the gradient
  stop passed `supportsOpacity: false`, since `Effect.gradientTable` maps luminance to an opaque
  colour, and the panel now carries the same flag — the opacity row isn't built, and alpha is pinned
  at 1 in `applyHSBA`, the single funnel every inbound colour passes through, so an 8-digit hex or a
  swatch saved with alpha can't smuggle transparency past a control that shows no slider for it. A
  later change to `applyHSBA` should keep that pin; it's the only thing standing between a gradient
  stop and a colour it isn't allowed to have.
- **An eyedropper on the left sidebar**, below the opacity slider — a tool you select and then tap
  the canvas with, not a swatch that opens a picker. Samples the full composite, paper background
  included, via `makeRenderRequest(...includeBackground: true)`, built fresh on the main actor from
  live model state (no cache) so a still-adjustable preview picks up exactly what's shown; that
  builder deliberately skips `renderResolution`, so a reduced live preview still yields the true
  colour. Pencil-only mode goes through the existing `TouchTypePressRecognizer` (a third instance of
  the mechanism `fillPress`/`catchAll` already use, not a fourth gate). Reverts to the previously
  selected tool after a pick, on a miss as well as a hit. The composite runs on the existing serial
  `sandwichQueue` rather than a separate one, so a pick can't race a sandwich rebuild. 18 new
  `EyedropperLogicTests` plus one XCUITest.
  Shipped with a bug the owner found on device: the picking touch also painted a brush stroke,
  because `CanvasView`'s `shouldInteract` excluded `.fill` from the active layer's host but never
  grew a matching exclusion for `.eyedropper`, so the host stayed interactive and the touch reached
  both recognizers. Fixed by replacing that hand-maintained list — and `handleCatchAllTap`'s
  separate hand-written twin of it — with one property, `Tool.paintsOnCanvas`: an exhaustive
  `switch` with no `default:`, so a future tool cannot silently default into painting. Also defers
  the eyedropper's tool-revert until the touch lifts, so a new contact arriving mid-gesture (a palm,
  a steadying finger) can't be hit-tested into a host re-enabled early. 6 new `ToolLogicTests`.
- **Say what an undo or redo just undid.** Reuses the existing `CanvasNotice` banner rather than adding
  a second mechanism, but the real substance was upstream: `UndoHistory.Action.name` was a plain
  `String`, hand-typed at each of ~70 registration sites with nothing stopping a typo or a missed site
  from compiling clean. It's now `HistoryActionLabel`, a ~70-case enum threaded through `recordUndo`,
  `withStructureUndo`, `commitStructureGesture`, `withInterpolationUndo` and the five private
  `register*Undo` helpers, so every one of those ~70 call sites had to name a case to keep building —
  the compiler enumerates them, not a convention. `HistoryActionLabel.phrase`'s own switch has no
  `default:` either, so a case added later without a phrase also fails to build. Found one real bug
  while enumerating: raster erasing always recorded `"Stroke"` regardless of `isEraser`, unlike the
  vector path, which already distinguished — fixed to `isEraser ? .erase : .brushStroke`.
- The `try?` in `ProjectStore` that discarded a whole vector cel on one unreadable field. It wrapped
  the entire decode and fell back to `VectorCanvas.empty`, so a single field it could not read threw
  away every stroke, fill, image and erase mark on the cel — silently, and the next save wrote the loss
  to disk for good. `VectorCanvasData` now decodes its display list one element at a time through a
  `LossySlot` wrapper whose `init(from:)` never throws: `JSONDecoder`'s unkeyed container only advances
  past a slot once it decodes successfully, so the obvious try/catch/continue loop would have re-read
  the failing slot forever. An unknown `kind` (a newer file opened by an older build) and a malformed
  known `kind` (an actual defect) are told apart at the discriminator and logged at different
  severities rather than collapsed into one silent failure; the counts land in a `DecodeReport` and a
  log line, not a banner, because `ProjectBackupManager` already stashes the pre-save package on every
  save, so the intact original survives a load that dropped something. Whether a partial load should
  also refuse to overwrite is a save-semantics call left to the owner. 12 new
  `VectorCanvasDataLogicTests`, on counts and identities rather than "did not throw" — the exact signal
  the old code gave while it destroyed the drawing. Closes the BUGS.md entry and leaves four collateral
  findings behind it: `validateProject` cannot see this class of damage either, the manifest's
  layer/cel arrays decode the same all-or-nothing way one level up, a corrupt raster PNG loses its cel
  with no log at all, and one bad swatch drops an artist's entire palette library.
- Smart-shape snap, and with it the whole shape-gesture branch that had been stuck behind it (handles
  sized in screen points, the oval and rectangle anchoring their opposite node, pinch-from-centre, the
  hold measured on the pen's own clock). The cause was `UIGestureRecognizer.requiresExclusiveTouchType`,
  which **defaults to `YES`** and was set nowhere in the app: a recognizer that takes the pencil at
  touch-down is closed to finger touches until it resets, and the filtering happens *at binding*, so
  the recognizer is never offered the touch and its `ignore` hook never runs. The previous
  `isMultipleTouchEnabled` fix was necessary but could never have been sufficient — that flag is per
  *view*, exclusivity is per *recognizer*. Confirmed on the owner's iPad. The palm baseline that
  shipped alongside it is **not** proven and is recorded in BUGS.md as open.
- Pinch to merge two layers. Two independent faults: the row pair was latched in `.began`, which fires
  only after the fingers have already moved, so a finger near a boundary had drifted into the next row
  by the time it was read; and the long-press reorder drag was taking the gesture outright, a race its
  own `secondTouchGraceInterval` comment had already documented and left open. Positions are now
  captured in `shouldReceive`, at the instant a touch lands, and an in-progress reorder drag is
  cancelled deterministically rather than on a timer. The decision logic lives in `PinchMergeGate` so
  it can be tested headlessly — XCUITest has no API for a vertical two-finger pinch on two given rows.
- Rectangle smart-shape node dragging, rotated. Two defects: a corner drag pinned its anchor in the
  shape's *local* frame while `rotationTransform` pivots about a centre that the drag itself moves, so
  a rotated rectangle transformed wrongly; and dragging a node past the opposite corner re-derived the
  anchor every frame, so once the drag crossed it, "the corner opposite the dragged one" started naming
  the finger's own corner instead. Fix removes the default from `ShapeGeometry.draggingCorner`'s
  `anchor` parameter, so every call site must state the latched point rather than silently re-deriving
  it. Swept 23,144 checks of "the opposite node does not move" across 11 rotations and drags
  overshooting the far edge; the same sweep fails 7,120 checks against the pre-fix code.
- The two lasso bugs. Lasso answered a finger in pencil-only mode: `SelectionOverlayView` used stock
  `UIPanGestureRecognizer`/`UITapGestureRecognizer`, whose `@objc` actions never see a `UITouch` — the
  third instance of the `fillPress`/`catchAll` hole — now replaced with `TouchTypePanGestureRecognizer`/
  `TouchTypeTapGestureRecognizer`. And a stroke that left the selection and re-entered counted as one
  stroke instead of two: `endVectorStroke` filtered samples and then built a single `VectorStroke`;
  `StrokeGeometry.splitRuns(_:inside:)` now yields one stroke per surviving run.
