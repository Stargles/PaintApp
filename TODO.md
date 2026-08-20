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

- [ ] **The "To Cross" eraser leaves stubs, and its size does nothing** — owner, on device, 2026-08-18:
      *"The cross eraser behaviour is a bit weird. I want it to erase the lines right at the point that
      the line crosses the center of another line, but in many cases it leaves stubs. Also, the eraser
      brush size should be the radius around which everything is erased. For example if I erase the
      section where two lines intersect, it should erase both of them (up to any other lines they
      hit)."*
      Two rulings in one ask, against `VectorEraserMode.cutToIntersection`:
      **(a) cut at the centreline crossing, not at the ink boundary.** `cutToIntersection` brackets the
      touch with `low = max(p)` / `high = min(p)` over crossings found at a **width-aware tolerance**
      (the sum of the two strokes' half-widths, `VectorEraser.swift:449-483`), so the surviving piece
      runs to the *near edge of the tolerance band* rather than to where the centrelines actually meet
      — which is a stub roughly a half-width long, sticking through the line that was supposed to stop
      it. Hypothesis, to be verified before it is fixed.
      **(b) the eraser radius selects the victims.** Today one drag cuts the single stroke under the
      tip; the owner wants every stroke inside the brush's footprint cut, each back to *its own*
      neighbouring crossings.

- [ ] **A second fill breaks the first — the transient never bakes, and the second never renders** —
      owner, on device, 2026-08-19: *"Using the fill tool more than once breaks it sometimes. I think
      it has to do something with it being in the transient state, then another thing is filled, and
      it doesnt bake the first one properly before going to the second."*
      **The owner's reading is right, and there is a specific race behind it.** `beginInteractiveFill`
      does its work asynchronously on `fillQueue` (composite the reference, upload it, run the GPU
      flood), then publishes the preview back with a `DispatchQueue.main.async`. A second tap that
      lands before that publish runs is the failure, and it breaks three ways at once:
      **(a) the first fill is dropped.** `commitInteractiveFill` bails on
      `guard cel.fillImage != nil` — "nothing was previewed" — which is true whenever the first
      fill's render has not reached the main thread yet. No undo entry, no pixels, silent.
      **(b) the second fill never renders.** The first gesture's `drainFillWork` is still looping. It
      re-reads `fillPending` (now the second gesture's key), sets `fillRendered` to it, and renders
      *that key* against the **first** session — so when the second gesture's own worker finally gets
      a session, `key == fillRendered` and it returns without drawing anything at all.
      **(c) the render it does produce is wrong.** That stale loop pairs the second tap's
      `fillGestureSeed` with the first tap's `fillSeedColor` and reference composite, so the preview
      on screen is a flood from the new point against the old picture at the old tolerance.
      The invariant this violates is written down at `CanvasManager.swift:1227` — *"the rest is set on
      the main thread in `beginInteractiveFill` before any `fillQueue` work runs, then only read
      after."* A second gesture is exactly the case that breaks it. The fix wants a per-gesture
      generation the worker carries and checks before it renders and before it publishes, and a
      commit path that does not depend on the async publish having landed.

- [ ] **A stroke that interrupts a menu is still broken — two menus, two different breakages** — owner,
      on device, 2026-08-18, and they name the real concern themselves: *"This signals an alarm to me that
      whatever partial fix was previously done did not fix the root cause. It also raises concerns that
      multiple UI menus have different versions of this problem, which may signal bad architecture."*
      **Symptom 1, the timeline menus.** *"Although the canvas can move freely after interrupting the menu
      now, the stroke behaviour is weird. The stroke goes for only a certain amount and then stops
      responding. This stroke seems to not be baked yet, as when the user then starts another stroke, the
      first stroke disappears."* So `8ae8613` fixed the *transform* recognizers and moved the damage onto
      the stroke: the touch sequence is still torn down mid-gesture, and the partial stroke is discarded
      rather than committed.
      **Symptom 2, the onion skin panel.** *"the canvas freezing happens in the onion menu, although the
      stroke this time does not only go partially. However, after the stroke is lifted, the user cannot
      paint again until the project is quitted (gallery) and then re-entered."* That is the **original**
      freeze, unfixed, in a menu the fix never covered.
      **The architecture is the finding, and it is the same shape this repo has already been burned by.**
      `CanvasManager.interactionBegan` has exactly **two** subscribers — `AnimationTimeline` (which clears
      `timelineMenu` and *only* `timelineMenu`, `AnimationTimeline.swift:163`) and `DrawingView`. The onion
      skin popover is presented from the very same view, through a separate `@State showOnionSkinOptions`
      (`AnimationTimeline.swift:424`), and nothing clears it. Every dismissible presentation has to opt in
      by hand, so a new one is broken by default — which is `Tool.paintsOnCanvas` before session 40 made an
      exhaustive `switch` refuse to compile. **The fix wanted here is that mechanism, not a third opt-in.**

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
      performance enhancements that can be made to reduce memory, stop lagspikes, or increase fps?"*
      **The investigation has been run; nothing has been built yet, which is why this stays open.**
      Its output is [PERFORMANCE.md](PERFORMANCE.md) — a fourteen-item programme in three tiers, the
      work deliberately *not* worth doing, and the open questions with the measurement that closes
      each. The conclusion in one line: **the felt problems are not the compositor and not the canvas
      size — they are a save that fires three times per app switch, a project open that blocks the
      main thread for an unmeasured multi-second stretch, and two ungated main-thread costs on every
      timeline tick.** Tier A is seven changes, none of which needs a device run to justify.

Carried over:

- [ ] **17 fps drawing on a 4K canvas.** Diagnosed and **not** the compositor: one dab costs 53.8 ms on
      a vector layer at 4096² against 4.0 ms on raster, because `StrokeCanvasView.refreshDisplay`'s
      `.overlay` branch allocates a fresh canvas-sized bitmap per touch-move. `renderResolution` never
      reaches that path, which is why the owner's 50% test changed nothing. Fix is to give the scratch
      its own layer; wants its own branch. Numbers in BUGS.md.
      **The owner confirmed (2026-08-18) that the 17 fps was measured at 4096×4096**, not at their
      usual 2048×1024 — so the area model holds and the extrapolated ~10.2 ms/dab at their canvas
      stands. [PERFORMANCE.md](PERFORMANCE.md) item 11.
- [ ] **Returning from another app freezes for a few seconds**, with no memory warning fired.
      **Cause found, 2026-08-18.** The owner confirmed the app returns *"exactly where I left off"*,
      which rules out a jetsam kill (a relaunch provably resets to the Gallery), so it is the app's
      own main-thread work: `ContentView`'s scene-phase guard has no direction check, so one round
      trip fires three full saves and one of them lands on the way back in. One-line fix,
      [PERFORMANCE.md](PERFORMANCE.md) item 1; the defect is in BUGS.md.
- [ ] **Leaving to the gallery takes ~3 s.** The thumbnail composites the full 4K canvas for a 320×320
      tile; already in BUGS.md.

## Done this pass

- **The lasso fill fills the whole canvas** — merged 2026-08-19. Rebuilt to
  [LASSO_FILL.md](LASSO_FILL.md): the loop's ring seeds the flood, the flood may never leave the loop
  (`lassoBarrier`), and the result is `loopMask ∧ ¬reached` — so the loop bounds the fill by
  construction rather than by connectivity the artist does not control. Circling a closed box now
  paints the box and nothing else (0.4004 of the canvas, its exact footprint) where it used to paint
  1.000. All three traps the spec warned about held: the loop is not a literal wall, `fillExpand` is
  forced to 0 in this mode, and there is no connected-component filter. §7's signal ships too — the
  sentence, the redrawn fence, and the tinted collar.
  **One correction to the spec, made while reviewing the unreviewed WIP that wired §7**: the collar
  tint cannot show a leak, because a leak is not an empty result — ink is never passable, so a leaked
  fill still paints the outline and the empty check never fires. On the path where the tint *is*
  shown it is congruent to the loop's interior, and it says the true thing for that case ("everything
  in here read as background"). Shipped, with the claim corrected in three doc comments and the
  reasoning written into LASSO_FILL.md §7. **Whether a leak deserves its own signal is an open
  question for the owner** — detecting one properly is a diagnostic-only connected-component pass.


- **The canvas border does not act as a fill boundary once there is padding** — merged 2026-08-19.
  Both suspected causes were real and both are fixed. `setCanvasPadding` grows `canvasSize` itself, so
  "the canvas edge" is an *artwork rect* inset from the pixel buffer by `canvasPadding`; the shader now
  carries that inset (`FillParams.edgeInset`, in the slot that was `_pad0`) and every edge rule is
  written against the inset rect, collapsing to the old buffer-rim formula at inset 0. And the edge rule
  was only ever a gap-closing *bridge*, conditional on artwork being within the gap radius — so a long
  stretch of bare border was never a wall. It is now an unconditional **barrier** inside
  `floodHoriz`/`floodVert`, living *between* pixels rather than as ink in the wall mask: ink would have
  cost an unfillable notch in every corner (measured: 92 px of a blank 128² canvas, 23 per corner),
  a barrier costs none.

