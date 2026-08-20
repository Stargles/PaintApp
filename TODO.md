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

- [ ] **A performance pass, calibrated to 2048×1024 — Tier A is built; Tiers B and C are not.**
      The owner asked for it directly: *"any performance enhancements that can be made to reduce
      memory, stop lagspikes, or increase fps?"* [PERFORMANCE.md](PERFORMANCE.md) is the fourteen-item
      programme; **items 1–7 are now resolved** (see "Done this pass" for what that means item by
      item). **This stays queued because seven items remain**, and the two that matter most are the
      instruments rather than the fixes:
      - **Item 9(a)** — instrument project open. Still *the largest unmeasured quantity in the app*:
        nobody can say whether tapping a project costs 200 ms or 4 s. Item 2 gave it a spinner, which
        changed what the wait looks like and not how long it is.
      - **Item 9(b)** — move the per-cel decode/rasterize fan-out off `@MainActor`. **Promoted by a
        measurement taken on 2026-08-20**: the same fan-out runs inside every sandwich rebuild as
        `renderSources`, at **78.2 ms on the main actor** for six layers at 2048×1024 when the
        playhead moves to a new frame, against 22.2 ms for all three composites together. It is now
        the largest main-thread term on a playback tick, and fixing it buys project open *and*
        scrubbing.
      - Item 8 (a 2048×1024 point for the vector-vs-raster preview) is device-only.
      - Tier C — items 11 to 14 — is real, recorded, and deliberately not urgent.

Carried over:

- [ ] **Leaving to the gallery takes ~3 s — the thumbnail half is fixed, the wait is probably not.**
      The tile now composites 320×160 instead of the whole canvas (Tier A item 5), so the save is far
      cheaper. But [PERFORMANCE.md](PERFORMANCE.md) §1 says the multi-second wait was never the
      thumbnail: navigation gates on a whole-document PNG re-encode whose cost scales with **cel
      count**, not with area. Unmeasured at any resolution. Worth asking the owner whether it still
      feels like ~3 s now.

- [ ] **17 fps drawing on a 4K canvas.** Diagnosed and **not** the compositor: one dab costs 53.8 ms on
      a vector layer at 4096² against 4.0 ms on raster, because `StrokeCanvasView.refreshDisplay`'s
      `.overlay` branch allocates a fresh canvas-sized bitmap per touch-move. `renderResolution` never
      reaches that path, which is why the owner's 50% test changed nothing. Fix is to give the scratch
      its own layer; wants its own branch. Numbers in BUGS.md.
      **The owner confirmed (2026-08-18) that the 17 fps was measured at 4096×4096**, not at their
      usual 2048×1024 — so the area model holds and the extrapolated ~10.2 ms/dab at their canvas
      stands. [PERFORMANCE.md](PERFORMANCE.md) item 11.

## Done this pass

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

