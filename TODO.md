# TODO

The owner's asks. [BUGS.md](BUGS.md) is for what we find. An item leaves when merged, not when a
branch exists. **Three in flight at once**, unless the extras need no simulator — see
`tools/simlock.sh`.

**At the start of a pass, empty "Done this pass".** It is a record of the pass you are in, not a
changelog — `git log` is the real history, and a list carried across passes stops meaning anything.
Prune it first, before adding the new asks.

## In flight

## The canvas size that actually matters

**The owner works at 2048×1024, or 1080p — "likely the former" (2026-08-17).** Not 4096².

Every performance number this project has collected was measured at 4096², which is **eight times the
pixels** of 2048×1024. Any cost that scales with area is therefore overstated by roughly 8× against the
document the owner actually animates on, and a conclusion drawn at 4K may be about a canvas nobody uses.
Benchmark at 2048×1024 first and treat 4096² as the stress case, not the baseline. This applies to the
17 fps entry below, the gallery thumbnail, and the onion skin composite alike.

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
- [ ] **Onion skin gets a real panel, modelled on ToonSquid's.** The owner supplied a screenshot and
      [the reference](https://toonsquid.com/handbook/layers/onion_skin/). Controls, top to bottom:
      **Drawings | Frames** (neighbouring drawings, vs neighbouring frames inside one drawing);
      **Behind | In Front** (default Behind); a **Previous** and a **Next** count slider with a **loop**
      toggle between them that wraps the skins around the first and last frame for cycle work;
      **Tinted | Original Colors**; a tint gradient bar, red for previous and green for next, drawn over
      a checkerboard so the alpha reads; **per-slot opacity sliders**, one per skin either side; and a
      row of dots beneath them.
      **Linked opacity is on by default** — the owner's emphasis: with it on the sliders move together,
      linearly with each other, so dragging one drags the rest. Unlinking frees them individually.
      The dots are ToonSquid's **out-of-pegs** — each temporarily offsets that skin via transform
      handles, the centre one toggles them all, and the onion button turns red while any offset is
      active. **Out of scope for now** (owner, 2026-08-17): build the panel without them. It is a
      per-skin transform surface with its own handles and undo behaviour, and leaving it out roughly
      halves this feature. Do not design the panel in a way that forecloses adding the row later.
- [ ] **Lasso flood fill**, as a *type* option under the existing flood fill tool, behaving like Clip
      Studio Paint's. Two distinct requirements, and the second is the one that makes it different from
      an ordinary fill: it **bridges gaps smartly**; and **the only boundary is the outer encirclement
      of the lasso**, so if the lassoed region spans two compartments separated by a line, *the line is
      filled too* rather than acting as a wall.
- [ ] **Fill tool option: treat the canvas edge as a line boundary. Default on.**
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
