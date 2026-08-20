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

*Nothing. The next owner ask starts here.*

## Queued

New this pass (owner, 2026-08-17):

- [ ] **A performance pass, calibrated to 2048×1024 — every item is now resolved, and the ask stays
      open on the owner's iPad.**
      The owner asked for it directly: *"any performance enhancements that can be made to reduce
      memory, stop lagspikes, or increase fps?"* [PERFORMANCE.md](PERFORMANCE.md) is the fifteen-item
      programme; **all fifteen are now resolved** (see "Done this pass" for what that means item by
      item) — thirteen built, item 10 measured and deliberately left alone, item 14 measured and
      declined. **This stays queued for one reason only, and it is the larger of the two it used to
      have**: **none of the wins has been seen on the owner's iPad.** Every after-figure in the
      document is a simulator in Debug, so the shape of each result transfers and the multiplier does
      not. Nothing further should be built here until they have run a Release build and said what
      changed.
      - **Item 10 is now measured (2026-08-20), and still not fixed on purpose.** A Mode 3
        (`cutToIntersection`) live-drag cut costs ~95 ms per cut sample (a full vector-layer
        re-stamp), against ~0 ms for a sample that does not cut — MEASURED, simulator, isolated run.
        50 cuts in one 334-sample drag over a 200-stroke layer. Real and now a number, but narrow: it
        fires only mid-drag, only on samples that cross a stroke. Any fix touches the eraser
        machinery `tmp/crosseraser` rewrote hours before this measurement, so it waits for that to
        settle. **9(b) has now landed, which promotes this**: at ~95 ms a cut sample is four times the
        whole cold sandwich rebuild, so it is the largest single-frame cost left anywhere in the app.
      - **Item 13 is built (2026-08-20).** `UndoHistory.maxCost` was the one memory budget in the app
        that knew nothing about the machine — a bare 300 MiB literal, and the *largest* single budget
        there, against 192 MiB apiece for two caches sized from a measured crash. It is now
        `physicalMemory / 16` on `CompositorBudget`'s own rule, and a memory warning trims it rather
        than clearing it, which is a response to pressure it simply did not have before. On the
        owner's iPad 9 that is 300 → 192 MiB: ~11,400 cropped freehand strokes either way (MEASURED at
        17,680 bytes a stroke), and 18 → 12 whole-cel operations.
      - **Item 14 is measured and declined (2026-08-20).** A drawn raster cel is **6.6 MiB resident**
        at 2048×1024 (MEASURED; the estimate was 8.0), unbounded in cel count, so 120 cels is 787 MB —
        more than every budget in item 13 put together. It is declined rather than built because the
        cheap half turned out to be worth **zero bytes** (the derived render memo is copy-on-write on
        the same buffer, measured at 0.0 MiB a cel), and the expensive half is a contract flip across
        drawing, undo, thumbnails, compositing and save with no confirmed harm to prevent.
      - **One question would settle item 14 and it is the owner's, not a run's: how many drawn cels
        does a real document of theirs carry?** 787 MB is 120 cels; at 30 it is ~200 MB and the item
        does not exist.

Carried over:

- [ ] **Leaving to the gallery — measured for the first time and made 4× shorter; the *report* is not
      closed.** Both halves are now fixed and neither has been seen on the owner's iPad, so this
      stands in exactly the position the 17 fps item below does.
      **The number, which was the point**: leaving a 32-cel document at 2048×1024 cost **480 ms** —
      **95% of it a single `pngData()` loop** (455 ms), against 12 ms of actual file writing and 2.5 ms
      for the thumbnail snapshot Tier A item 5 already shrank. That is **15.0 ms a cel and flat from 8
      cels to 32**, so [PERFORMANCE.md](PERFORMANCE.md) §1's "scales with cel count, not area" is
      confirmed rather than assumed, and **~3 s is simply a ~150-cel document on their iPad**
      (INFERRED) — the report needed no other explanation. It is now **117 ms** for that document,
      ~0.37 s at a hundred cels: the per-cel encode runs across cores (item 15).
      *What would close it*: the owner leaves a real document to the gallery on their iPad and says.
      **They do still need to be asked** — every figure above is a Debug simulator on 8 cores and
      theirs is a Release build on an A13 with 2+4, so the shape transfers and the multiplier does
      not. If it still feels like seconds, the next question is what their cel count actually is, and
      [PERFORMANCE.md](PERFORMANCE.md) §5's memo — encoding only the cels whose pixels moved — is the
      one remaining lever, deliberately unbuilt because it is the data-loss class of risk.

- [ ] **17 fps drawing on a 4K canvas — the fix is merged; the *report* is not closed.** The cost is
      gone (see Done this pass), but every after-figure is the simulator and 17 fps is something the
      owner measured on their iPad. **This stays until they draw on the 4096² canvas and say.** If it
      still feels like 17 fps, the remaining cost is somewhere nobody has looked — start at
      [PERFORMANCE.md](PERFORMANCE.md) items 4, 5 and 9(b), which are the other terms of that frame,
      and treat the fix below as ruled out rather than as suspect.
      *What would close it*: a Release build on their iPad — `deploy.sh` pulls `main`, so run its
      steps from the worktree — and one sentence from them.

## Done this pass

- **Performance, Tier C items 13 and 14 — merged 2026-08-20. The last two on the board: one built,
  one measured and declined.** With these the fifteen-item programme is closed.
  **Item 13 — the undo budget now knows what device it is on, and the app's five memory budgets tell
  one story.** `UndoHistory.maxCost` was `300 * 1024 * 1024`, a bare literal, and the *largest single
  memory budget in the app* — bigger than either of the two caches that were sized from a measured
  crash on the owner's own iPad. It is now `physicalMemory / 16`, character for character
  `CompositorBudget`'s rule, with a test pinning the two equal so they cannot drift. On the iPad 9
  that is 300 → 192 MiB, and the cut is stated rather than glossed: a cropped freehand stroke costs
  **17,680 bytes** (MEASURED), so 192 MiB is ~11,400 of them and the cut is inert for drawing; it
  bites on whole-cel operations, **18 → 12**. What pays for it is that undo was the only one of the
  five budgets with **no response to a memory warning at all** — the caches drop wholesale, this sat
  at its high-water mark. It now trims the oldest steps to half the budget and puts the budget back,
  because a cache entry costs one recomputation and an undo step costs work the artist cannot get
  back.
  **Item 14 — measured, and the build declined on what the measurement found.** A drawn raster cel is
  **6.6 MiB resident** at 2048×1024 (MEASURED, twice, under opposite host loads; the estimate it
  replaced was 8.0 MiB), linear in cel count with nothing bounding it, so 120 cels is **787 MB** —
  more than all five budgets above put together. Declined for two reasons neither of which was known
  before the run: **the cheap half is worth zero bytes** (the derived render memo shares the context's
  buffer copy-on-write — 0.0 MiB a cel, measured rather than assumed), and item 9(c)'s thumbnail
  backfill touches every cel within a second of an open, so any lazy scheme is defeated unless
  thumbnails are persisted first. That precondition is now written down.
  **What is still owed on both**: the same thing owed on everything else here — a Release build on the
  owner's iPad. And for item 14, one sentence from them: how many drawn cels a real document carries.

- **Performance, item 15 — merged 2026-08-20. Leaving to the gallery was measured for the first time,
  and then made 4× shorter.** Both stages shipped.
  **The answer**: a 32-cel document at the owner's 2048×1024 cost **480.3 ms** to leave —
  **455.2 ms of it `pngData()`**, 11.7 ms of file writes, 7.8 ms of the atomic-swap machinery and
  2.5 ms for the thumbnail snapshot. **15.0 ms a cel, flat from 8 cels to 32**, so ~1.50 s at a
  hundred cels and ~1.95 s on their iPad 9 (INFERRED) — the owner's "~3 s" is a ~150-cel document.
  [PERFORMANCE.md](PERFORMANCE.md) §1 had claimed for two months that this cost scales with cel count
  rather than area and that the file I/O was the shape of it; the first half is now confirmed and the
  second was wrong by a lot — **the write is 2% of a save**.
  It is now **117.1 ms** for that document, ~0.37 s at a hundred cels: `writePackage` flattens the
  cel tree and runs the per-cel encode through the same `PixelOps.parallelMap` item 9(b) added, with
  the manifest's order rebuilt from the job list rather than from completion.
  **The 4.1× is checkable rather than asserted**: two arms alternated three times inside one test read
  500.3 vs 96.2 ms (5.20×) at +0.2% peak memory, and the two phases the change did not touch — the
  snapshot and the atomic swap — read the same across the before and after runs.
  **Nothing about what gets written changed.** §5's memo, which would skip the encode for a cel whose
  pixels have not moved, stays unbuilt: it is the data-loss class of risk and it belongs beside
  `RasterLayerTexture`'s existing version-keyed cache, not in a second identity scheme.

- **Performance, item 9 — merged 2026-08-20. Project open was measured for the first time, and then
  made 5.7× shorter.** All three stages shipped.
  **The answer, which was the point of the item**: tapping a project cost **303.6 ms** on a 32-cel
  document at the owner's 2048×1024 — 207.3 ms decoding the cels, 96.3 ms building thumbnails —
  which is **~0.95 s on a hundred-cel project**. [PERFORMANCE.md](PERFORMANCE.md) had carried a guess
  of "1-3 s" for two months and called it the largest unmeasured quantity in the app; the real figure
  is about three times smaller, which is the same shape of error as the 4K recalibration.
  It is now **53.5 ms** for that document, ~0.17 s at a hundred cels: the per-cel decode runs across
  cores and off the main thread, and the thumbnails no longer happen before the canvas appears — the
  cels arrive on the blank placeholder the timeline already draws, and a background pass fills them
  in a layer at a time.
  **The same fan-out is what every sandwich rebuild runs**, so scrubbing and playback got it too:
  **78.2 ms → ~22 ms** of main-actor work on the tick where the playhead moves to a new frame. That
  claim is checkable rather than asserted — the same test's three composites are unchanged code and
  read within 4% across the before and after runs, which is what says the two machines were
  comparable.
  **Two honest limits.** The 3.9× is on eight cores; the owner's iPad 9 has two performance cores and
  four efficiency ones, so expect less there. And everything above is a simulator in Debug — the shape
  transfers, the multiplier does not.
  **What it cost to get right**: a machine three other sessions were also testing on made the same
  test report 303 ms, 448 ms and 527 ms for the same work, so the figures that survived are the ones
  taken at 79-81% idle with nothing else running, and the paired serial-versus-parallel cases that
  measure both sides in one run.

- **Performance, items 8 and 11 — merged 2026-08-20. The live vector stroke gets its own layer.**
  `StrokeCanvasView.refreshDisplay` flattened the committed render and the in-progress stroke into a
  fresh canvas-sized bitmap on **every touch-move** — a 64 MiB allocation and two full-canvas blits
  per dab at 4096², to produce something Core Animation was going to composite anyway. It now hands
  the live stroke to a sibling image view and lets Core Animation do it.
  MEASURED per dab, simulator/CoreGraphics, machine 93.6% idle with nothing else running, before →
  after: **8.0 → 2.2 ms** at 2048×1024, **16.1 → 2.5 ms** at 2048², **47.1 → 3.9 ms** at 4096². The
  raster path costs 2.1 / 2.4 / 3.6 ms at those sizes, so drawing on a vector layer now costs what
  drawing on a raster layer costs. Item 8 landed first, as its own commit: it added the owner's own
  2048×1024 to the measurement, replacing a two-point fit that said ~10.2 ms with a reading of 8.0.
  **This was the highest-risk item on the board** — `.replacement` (Mode 1) and `.none` (Modes 2/3)
  were already one-operation paths where a regression shows up as an eraser that does nothing until
  you lift, not as slow ink. Neither gained an operation, and the three roles are now pinned in the
  fast tier by `VectorPreviewPlanLogicTests` instead of only by a 22-minute UI suite.
  **It has not been seen on the owner's iPad** — see the entry still open in Queued, and
  [PERFORMANCE.md](PERFORMANCE.md) item 11.

- **Performance, Tier A — merged 2026-08-20. Six changes, one of them already there, and one
  sub-item declined on a measurement.** The owner's ask is not finished (Tiers B and C remain, above);
  this is the half that needed no device run to justify.
  **1. The app-switch freeze — already fixed 2026-08-18**, two days before this document said it was
  outstanding. `ScenePhaseSaveGate` makes one round trip out and back fire **one** save instead of
  three, on the way out only, and `ProjectSaveLogicTests` proves it by replaying the phase sequence
  SwiftUI actually delivers rather than by asserting on the predicate. **Whether the freeze the owner
  reported is gone or merely smaller wants their iPad** — the count is provably 1, but one save is
  still a save.
  **2. Opening a project now shows a spinner** on the tile you tapped, and refuses a second tap while
  it runs. It is not faster — that is item 9 — but an app that goes dead on the first tap of a session
  reads as one that crashed. The state machine, not the spinner, is what carries the two rules that
  fail silently: one load at a time (two loads is a lottery between two projects), and *every* load
  ends, including the one that returns nil for a damaged package, or the gallery is stuck behind a
  spinner that never stops.
  **3. The timeline stops re-laying-out on every SwiftUI pass.** A key gates it, and a scrub takes a
  playhead-only fast path — two view frames, no redraw — because keying on `currentFrame` would move
  the key on every sample of the gesture the gate exists for. Honestly sized in the doc: it is a
  large constant factor, not an asymptotic win, since building the key walks the same cels. The
  ruler's `draw` now consults its dirty rect, which buys less than it reads and the doc says so.
  **4a. A layer tap composites twice instead of three times.** `full` is the whole tree, uncut, so
  switching layers changes only where the tree is cut — it was recompositing an image byte-identical
  to the one on screen. **4b was declined, on a number rather than on nerve**: making `below`/`above`
  lazy would remove ~11% of a playback tick, in the half that was never on the main thread, in
  exchange for a stroke whose first frames have no visible ink. The estimate that made it look like
  "from missing the 24 fps budget to fitting inside it" was arithmetic over a per-layer slope.
  **5. The gallery tile composites 320×160, not 2048×1024** — 41× the pixels, on the main actor,
  inside every save. The hint is a bounding box rather than a size, so the one thing that is silent
  when wrong (which dimension binds) is written once and shared with the thumbnail renderer.
  **6. A memory warning now reaches the mask cache**, which its own doc comment had claimed for two
  months while every caller in the tree was a test. Small bytes; the point is closing the lie before
  a third instance of it — `PixelOps` records the identical defect being found and fixed once
  already.
  **7. Onion skin was already merged** (session 42). Checked before anything was written; nothing
  rebuilt.
  **The instrument that came out of it may outlast the fixes.** `CompositeProbe` counts composites
  and their sizes, so two of these claims are integers about the calls rather than milliseconds about
  a machine — which matters on a Mac where contention is documented to make suites return wrong
  answers, not merely slow ones.

- **Add Text, in the Actions menu — Stages 1 and 3 merged 2026-08-20. The ask itself is not
  finished: Stages 4, 5 and 6 remain**, and [ADD_TEXT.md](ADD_TEXT.md) §3 is the live list of them.
  What the owner can do on the iPad today: Actions ▸ Add Text on **any raster or vector layer**, tap
  the canvas to place a box, type into it, drag its outline to move it, and set font family, face,
  size, tracking, line height, line and paragraph spacing, alignment and colour.
  **On a raster layer it bakes** into the pixels the moment anything else touches the canvas — a
  stroke, an eraser, a fill, a layer or frame switch, a save — exactly as the fill tool and the smart
  shapes already do, as one undo step per session however much was typed.
  **On a vector layer it stays text, forever.** The object goes into the layer's display list, saves
  into the project as itself, and comes back out of a reload as itself: tap it again and it re-opens
  with the words and the type settings it was committed with, ready to retype or restyle, in the same
  place in the stack it was before. Delete every character and the object goes away. The eraser hides
  it like anything else but does not carve the letterforms — the owner's ruling of 2026-08-17.
  Undo while the caret is live steps back through the typing, and only once you tap away does it
  remove or restore the whole text object; that is the owner's ruling too.
  **Not there yet, and deliberately so:** rotate, scale, the four-corner perspective distort (Stages
  4-5), and font packs (Stage 6). Fonts are iOS's own, behind the `FontProvider` seam the owner asked
  for — adding a pack later is "append a provider", not a change to any call site.
  **Two things want the owner.** *(1)* **Which faces belong on a favourites strip** at the top of the
  font picker — ADD_TEXT.md §5 item 5, the one question Stage 1 could not answer for itself. It
  shipped with all ~60-80 families grouped and no strip, because inventing a shortlist would have
  made it the answer by default. *(2)* **The keyboard over the canvas has never been tried on a real
  iPad** — first-responder handoff across panel toggles, the keyboard covering a box near the bottom
  of the screen, a box at 0.3× zoom, and iOS's own Scribble recognizer against the canvas's. None of
  it is reachable headlessly; `ActionRecorder` is how to get a session of it off the device. Stage 3
  adds one more to that list and no others: **whether tapping an existing label re-opens it under a
  fingertip**, since the target is the box and the tap is also what would place a new box beside it.

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

- **A stroke that interrupts a menu is still broken — two menus, two different breakages** — merged
  2026-08-20. The owner's real concern was the architecture, and it was right: `interactionBegan` was a
  bare signal with two hand-written subscribers clearing one named variable each, so a presentation was
  **broken by default** and became safe only if whoever added it remembered a line. A read-only sweep
  ([MENU_PRESENTATION_CENSUS.md](MENU_PRESENTATION_CENSUS.md)) found **seven** such popovers — including
  two declared nine lines below the sink written to fix exactly this class of bug — and twelve further
  presentations nothing in the repo could rule on.
  **The fix is the mechanism they asked for, not a third opt-in.** `CanvasPresentation` is a
  `CaseIterable` enum of every bindable presentation whose `overlapsLiveCanvas` is an exhaustive
  `switch` with no `default:`, in `Tool.paintsOnCanvas`'s image; `View.canvasPresentation` is the single
  declaration site; `CanvasManager.dismissPresentationsOverLiveCanvas()` is the rule, in one place.
  **And closing popovers earlier was never sufficient** — it only moves the teardown a frame, which is
  how the previous fix turned a freeze into a vanishing stroke. So the other half is `StrokeGiveUp`:
  a second finger arriving still rolls the stroke back (`.handedOver`, which is what stops a pan-dab
  becoming a permanent un-undoable mark), while a sequence that simply stopped being delivered now
  **commits with an undo step** (`.interrupted`). Symptom 2, the onion-skin freeze, is covered because
  that popover is one of the seven.
  **Measured, and it halves the problem**: a SwiftUI `Menu`'s dismiss region absorbs the whole touch —
  the drag neither reaches the canvas nor even closes the menu — so the twelve unverifiable ones are
  **safe**, and the defect was seven, not nineteen.
  **Honest limit**: adding a *case* is now compiler-forced, but writing a raw `.popover` and adding no
  case is not. That half is a test-time gate instead —
  `CanvasPresentationLogicTests.testNoBarePopoverIsDeclaredOutsideTheModifier` reads the real source
  tree off `#filePath` and fails naming the file and line, with `tools/presentation-census.sh` as the
  same check from a shell. Two remaining costs are recorded in [BUGS.md](BUGS.md): the interrupted
  stroke is still *short*, and the touch that finds the stranded stroke is spent finding it.

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

