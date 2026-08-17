# TODO

The owner's asks. [BUGS.md](BUGS.md) is for what we find. An item leaves when merged, not when a
branch exists. **Three in flight at once**, unless the extras need no simulator — see
`tools/simlock.sh`.

**At the start of a pass, empty "Done this pass".** It is a record of the pass you are in, not a
changelog — `git log` is the real history, and a list carried across passes stops meaning anything.
Prune it first, before adding the new asks.

## In flight

- [ ] **Rectangle nodes misbehave once the rectangle is rotated.** Flat, dragging a node is correct.
      Rotated, it produces unintended transforms. **The rule, in the owner's words: the node opposite
      the one being dragged must not move.** Second half of the same ask: dragging a node *past* the
      opposite edge should let the rectangle keep working, inverted into the other quadrants — today it
      pushes the opposite edge instead. The rectangle twin of the oval fix on `tmp/shapedev` ("oval
      handles rotate with the opposite node anchored"), so it is built on that branch and reuses its
      headless harness. `tmp/rectnode`.
- [ ] **The two lasso bugs**, taken together — a stroke leaving the selection and re-entering counts as
      one and not two, and the lasso answers a finger while pencil-only mode is on. The second is
      likely a third instance of the `fillPress`/`catchAll` hole: a recognizer whose action never sees
      a `UITouch` and so cannot ask the touch type. `tmp/lasso`.

## Queued

New this pass (owner, 2026-08-17):

- [ ] **The `try?` in `ProjectStore` that discards a whole cel — do this next** (owner's call,
      2026-08-17). Full entry in [BUGS.md](BUGS.md); it is a permanent-data-loss path, it is small and
      self-contained, and it has to land before any text object reaches disk regardless.
- [ ] **One colour picker, not two.** The canvas colour changer differs from the brush's; they should be
      the same control. If a second implementation exists, delete it rather than leaving it unreferenced.
- [ ] **An eyedropper on the left sidebar, below the opacity slider.** Confirmed with the owner
      2026-08-17: a *tool* you select and then tap the canvas with to pick up the colour under it, not
      a swatch that opens a picker.
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
- [ ] **Say what an undo or redo just undid.** A brief notice naming the action, using the same
      transient notice mechanism already used elsewhere in the app (the owner does not recall where —
      find it and reuse it rather than adding a second kind). Must not block or freeze the screen.

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
