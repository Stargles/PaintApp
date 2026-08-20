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

- **Add Text, in the Actions menu — Stage 1 merged 2026-08-20. The ask itself is not finished:
  Stages 3-6 remain**, and [ADD_TEXT.md](ADD_TEXT.md) §3 is the live list of them. What the owner
  can do on the iPad today: Actions ▸ Add Text on a **raster** layer, tap the canvas to place a box,
  type into it, drag its outline to move it, and set font family, face, size, tracking, line height,
  line and paragraph spacing, alignment and colour. It bakes into the layer the moment anything else
  touches the canvas — a stroke, an eraser, a fill, a layer or frame switch, a save — exactly as the
  fill tool and the smart shapes already do, as one undo step per session however much was typed.
  Undo while the caret is live steps back through the typing, and only once you tap away does it
  remove the text object; that is the owner's own ruling of 2026-08-17.
  **Not there yet, and deliberately so:** vector layers (the row is disabled with a note explaining
  why, so the stage ships nothing it has to un-ship), rotate, scale, the four-corner perspective
  distort, and font packs. Fonts are iOS's own, behind the `FontProvider` seam the owner asked for —
  adding a pack later is "append a provider", not a change to any call site.
  **Two things want the owner.** *(1)* **Which faces belong on a favourites strip** at the top of the
  font picker — ADD_TEXT.md §5 item 5, the one question Stage 1 could not answer for itself. It
  shipped with all ~60-80 families grouped and no strip, because inventing a shortlist would have
  made it the answer by default. *(2)* **The keyboard over the canvas has never been tried on a real
  iPad** — first-responder handoff across panel toggles, the keyboard covering a box near the bottom
  of the screen, a box at 0.3× zoom, and iOS's own Scribble recognizer against the canvas's. None of
  it is reachable headlessly; `ActionRecorder` is how to get a session of it off the device.

- **A second fill breaks the first** — merged 2026-08-20. The owner's reading was right and all
  three mechanisms were confirmed by a test that fails on the parent commit. **(a)** The first fill
  was dropped: `commitInteractiveFill`, reached through `beginCanvasEdit` at the top of the *next*
  `begin*Fill`, bailed on `guard cel.fillImage != nil` — and `fillImage` is written by the render's
  hop to main, so a rendered fill that had not yet reached the main thread read as "nothing was
  previewed". **(b)** The second fill never rendered: the superseded worker re-read `fillPending`,
  booked `fillRendered` against the new gesture's key, and the new gesture's own worker then found
  `key == fillRendered` and returned having drawn nothing. **(c)** What it rendered instead paired
  the new tap's seed with the *old* session, reference composite and sampled colour, and installed
  itself anyway, because the publish only ever asked whether *some* fill was active.
  **The fix is a per-gesture generation plus a snapshot.** Every `begin*Fill` claims a
  `fillGeneration` under `fillLock` (commit and cancel retire it), and the worker carries an
  immutable `FillGestureContext` instead of reading `fillGestureSeed`/`fillGestureColor`/the target
  ids off the queue — so pairing a new seed with an old session is now unrepresentable rather than
  merely warned against. The generation is checked before a key is claimed, before a result is
  stored, and again on main before it is installed. `drainFillWork` also stores each render under
  the lock the *moment* it exists, so the commit can bake a fill whose pixels are real but have not
  reached main; an empty lasso stores none, so LASSO_FILL.md §7.1's no-undo-entry rule still falls
  out of the same guard. `beginInteractiveLassoFill` had the identical exposure and is covered.
  **`FillGestureRestartLogicTests` forces both interleavings exactly rather than racing for them** —
  `fillQueue.sync {}` is "rendered, not yet published", and a semaphore on the serial queue orders a
  superseded worker after the gesture that replaced it. A race test that hopes to lose a race is
  worth nothing in either direction.

- **The "To Cross" eraser leaves stubs, and its size does nothing** — merged 2026-08-20. Both
  rulings shipped, and hypothesis (a) was **confirmed by measurement, not accepted**: the cut landed
  short of the true centreline crossing by the *whole* width-aware tolerance, not the half-width the
  hypothesis guessed, and the miss grows as `tolerance / sin(angle)`. Measured on the unmodified
  engine with a standalone `swiftc` harness — **10.0 pt** at a square crossing of two 20 pt brushes,
  **18.0** at 36 pt, **22.0** at 26°, **29.0** at 11°; **0.0000 pt** in all of them after, and
  **0.0** for the `tolerance == 0` control both before and after, which is what isolates tolerance as
  the cause.
  **The cause was `StrokeGeometry.intersections(between:and:tolerance:)`, not the bracket.** Its halo
  suppression and its clustering were both written in *sample-index* units — drop a near-contact
  within ±1 index of an exact crossing, chain candidates within 1 index on both polylines — while
  `tolerance` is a physical distance, the sum of two brush half-widths, 10–20 pt. A real stroke
  arrives sampled every point or two, so a genuine crossing came wrapped in a disk of near-contacts
  tens of samples wide that the ±1 shadow excluded almost none of: **25 entries where there is one**
  at 90°, **51** at 26°, **109** at 11°. `cutToIntersection`'s `max`/`min` bracket then mechanically
  picked the entry furthest from the crossing and nearest the touch. Regrouped over *contact along the
  stroke* instead — every segment with a qualifying partner joins a region, touching regions merge, a
  region holding exact crossings reports those and nothing else — which is unit-correct and
  density-independent; all three cases now report exactly 1.
  **Every existing test missed it because every one of them spaced its samples wider than the
  tolerance it tested** — a two-point crosser, which no real stroke is. That is the coverage gap, and
  it is why the new tests assert the cut's *distance in points* from the crossing rather than that a
  cut happened.
  Ruling (b) went in as asked: the footprint now selects **every** stroke whose centreline it covers,
  each cut back to its own neighbouring crossings, computed against the pristine display list and
  spliced in descending index so two lines cut in one tap each see the other's original geometry. A
  crossing *inside* the footprint is no longer an obstacle — otherwise a tap on an X would leave
  exactly the ink the artist aimed at. The driver's single "am I armed" bit became a set of stroke
  ids, because one bit goes dead after the first position once a wide footprint is almost never over
  nothing (pinned by a test: the same drag cuts 4 uprights with the set, 1 with the bit). A
  canvas-accurate footprint ring is drawn under the finger during the gesture, since a selection
  radius that acts at a distance and cannot be seen is guesswork.
  **One defect found reviewing the WIP**: it threaded the touch pressure into the footprint, so the
  selection radius shrank under a light pencil (a finger reports pressure 1, a pencil reports
  `force / maximumPossibleForce`) while the ring was drawn at full size. Pinned to the brush size,
  which is what the owner's sentence says and what makes the ring an exact promise. Invisible to
  every existing test — they all use `dynamics: .fixed`, which has no pressure term to leak.
  **Two things the owner should rule on**, both consequences of taking the ask literally: a line the
  circle covers that crosses *nothing* is deleted whole, so one tap near a busy corner can also wipe
  a stray line nearby; and a stroke is taken by its **centreline**, so the eraser clipping only the
  edge of a thick line leaves it alone (the circle is exactly the rule, rather than acting slightly
  larger than it looks).

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

